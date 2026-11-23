import CoreLocation
import SwiftUI
import UIKit

/// The day as a picture to send: its track drawn as a sketch, where and when, and its numbers.
/// Made only of shapes and text, so that it can be turned into an image.
struct ShareCard: View {
    let day: SkiDay
    let tracks: [MapTrack]

    static let size = CGSize(width: 360, height: 450)

    var body: some View {
        let s = day.stats
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(day.title ?? String(localized: "Giornata sulla neve"))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2).minimumScaleFactor(0.6)
                    Text(Fmt.day(day.start).capitalized + " " + day.start.formatted(.dateTime.year()))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.sub)
                }
                Spacer(minLength: 8)
                if let weather = day.weather {
                    VStack(alignment: .trailing, spacing: 3) {
                        Image(systemName: weather.symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.accent)
                        Text(Fmt.temperature(weather.tempMax)).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.sub)
                    }
                }
            }

            TrackSketch(tracks: tracks)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 0) {
                figure("\(s.runs)", "Discese")
                figure(Fmt.height(s.vertical), "Dislivello")
                figure(Fmt.speed(s.maxSpeed), "Velocità max")
            }
            .padding(.bottom, 12)
            HStack(spacing: 0) {
                figure(Fmt.distance(s.runDistance), "Sciati")
                figure(Fmt.height(s.topAlt), "Quota max")
                figure(Fmt.duration(s.runTime), "Tempo in pista")
            }

            HStack {
                Text("SKI APEX").font(.system(size: 13, weight: .bold)).tracking(1.5).foregroundStyle(Theme.accent)
                Spacer()
                Image(systemName: (day.sport ?? .ski).symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent)
            }
            .padding(.top, 16)
        }
        .padding(22)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(
            LinearGradient(colors: [Theme.sky, Theme.bg, Theme.deep],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(LocalizedStringKey(label)).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.sub)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The lines of a day without a map under them, fitted to the space they are given.
struct TrackSketch: View {
    let tracks: [MapTrack]

    var body: some View {
        ZStack {
            ForEach(tracks.filter { $0.kind == .lift }) { track in
                TrackLine(coordinates: track.coordinates, bounds: bounds)
                    .stroke(Theme.lift.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [4, 4]))
            }
            ForEach(tracks.filter { $0.kind == .run }) { track in
                TrackLine(coordinates: track.coordinates, bounds: bounds)
                    .stroke(Theme.runColor(track.number), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
    }

    /// South, west, north, east of everything drawn.
    private var bounds: [Double] {
        let all = tracks.filter { $0.kind != .idle }.flatMap(\.coordinates)
        guard let minLat = all.map(\.latitude).min(), let maxLat = all.map(\.latitude).max(),
              let minLon = all.map(\.longitude).min(), let maxLon = all.map(\.longitude).max() else { return [0, 0, 1, 1] }
        return [minLat, minLon, maxLat, maxLon]
    }
}

/// One line of the sketch: north up, the same scale across and down.
struct TrackLine: Shape {
    let coordinates: [CLLocationCoordinate2D]
    let bounds: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard coordinates.count > 1, bounds.count == 4 else { return path }
        let kx = cos((bounds[0] + bounds[2]) / 2 * .pi / 180)
        let width = max(1e-9, (bounds[3] - bounds[1]) * kx), height = max(1e-9, bounds[2] - bounds[0])
        let scale = min(Double(rect.width) / width, Double(rect.height) / height)
        let dx = Double(rect.midX) - width * scale / 2, dy = Double(rect.midY) - height * scale / 2
        for (i, c) in coordinates.enumerated() {
            let x: Double = dx + (c.longitude - bounds[1]) * kx * scale
            let y: Double = dy + (bounds[2] - c.latitude) * scale
            let point = CGPoint(x: x, y: y)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// The picture of the day, shown before it is sent.
struct ShareSheet: View {
    let day: SkiDay
    @Environment(\.dismiss) private var dismiss
    @State private var file: URL?
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Spacer(minLength: 0)
                if let image {
                    Image(uiImage: image)
                        .resizable().scaledToFit()
                        .clipShape(Theme.round)
                        .overlay(Theme.round.strokeBorder(Theme.line, lineWidth: 1))
                        .shadow(color: .black.opacity(0.4), radius: 18, y: 10)
                        .accessibilityLabel(Text("Immagine della giornata con la traccia e i numeri"))
                } else {
                    ProgressView()
                }
                Spacer(minLength: 0)
                if let file, let image {
                    ShareLink(item: file, preview: SharePreview(day.title ?? "Ski Apex", image: Image(uiImage: image))) {
                        Label("Condividi", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Condividi la giornata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Chiudi") { dismiss() } }
            }
            .task { render() }
        }
        .modifier(Dressed())
    }

    @MainActor private func render() {
        let tracks = MapTrack.build(points: day.points, segments: day.segments, maxPoints: 200)
        let renderer = ImageRenderer(content: ShareCard(day: day, tracks: tracks).environment(\.colorScheme, Theme.dark ? .dark : .light))
        renderer.scale = 3
        guard let made = renderer.uiImage, let data = made.pngData() else { return }
        image = made
        let name = DateFormatter()
        name.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ski Apex \(name.string(from: day.start)).png")
        try? data.write(to: url, options: .atomic)
        file = url
    }
}
