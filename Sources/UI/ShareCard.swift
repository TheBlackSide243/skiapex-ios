import CoreLocation
import SwiftUI
import UIKit

/// The shape of a picture to send: for a post, or tall for a story.
enum CardFormat: String, CaseIterable, Identifiable {
    case post, story

    var id: String { rawValue }
    var label: String { self == .post ? "Post" : "Storia" }
    var size: CGSize { self == .post ? CGSize(width: 360, height: 450) : CGSize(width: 360, height: 640) }
}

/// The foot of every picture to send: the icon in use and the name of the app.
struct CardFoot: View {
    var symbol = "figure.skiing.downhill"

    var body: some View {
        HStack(spacing: 9) {
            Image(IconArt.previewInUse)
                .resizable()
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
            Text(verbatim: "SKI APEX").font(.system(size: 13, weight: .heavy, design: .rounded)).tracking(1.6).foregroundStyle(Theme.text)
            Spacer()
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent)
        }
    }
}

/// One number of a picture to send, with its unit small beside it and what it counts under it.
struct CardFigure: View {
    let value: String
    let label: String
    var size: CGFloat = 18
    var color: Color = Theme.text

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            FigureText(value, big: .system(size: size, weight: .bold, design: .rounded),
                       small: .system(size: max(9, size * 0.5), weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(LocalizedStringKey(label)).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(Theme.sub)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The day as a picture to send: its runs drawn in the color of their piste, its profile, where
/// and when, and its numbers. Made only of shapes and text, so that it can be turned into an image.
struct ShareCard: View {
    let day: SkiDay
    let tracks: [MapTrack]
    var format = CardFormat.post

    /// The pistes of the day, the ones skied most first.
    struct Piste: Identifiable, Hashable {
        let name: String
        let difficulty: String?
        let ref: String?
        let times: Int

        var id: String { name }
    }

    static func pistes(of day: SkiDay) -> [Piste] {
        var order: [String] = []
        var found: [String: (difficulty: String?, ref: String?, times: Int)] = [:]
        for run in day.runs {
            guard let name = run.name, !name.isEmpty else { continue }
            if found[name] == nil { order.append(name) }
            let before = found[name]
            found[name] = (run.difficulty ?? before?.difficulty, run.ref ?? before?.ref, (before?.times ?? 0) + 1)
        }
        return order.compactMap { name in found[name].map { Piste(name: name, difficulty: $0.difficulty, ref: $0.ref, times: $0.times) } }
            .sorted { $0.times > $1.times }
    }

    var body: some View {
        let s = day.stats
        let pistes = format == .story ? Array(Self.pistes(of: day).prefix(4)) : []
        VStack(alignment: .leading, spacing: 0) {
            header
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.deep.opacity(0.85))
                if tracks.contains(where: { $0.kind == .run }) {
                    TrackSketch(tracks: tracks).padding(16)
                } else {
                    Image(systemName: (day.sport ?? .ski).symbol).font(.system(size: 64, weight: .semibold)).foregroundStyle(Theme.accent.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 14)
            if let legs = Leg.of(day), legs.count > 1 {
                DayProfile(legs: legs, lineWidth: 2.2)
                    .frame(height: format == .story ? 52 : 34)
                    .padding(.top, 12)
            }
            HStack(alignment: .bottom, spacing: 0) {
                CardFigure(value: Fmt.height(s.vertical), label: "Dislivello", size: 34, color: Theme.accent)
                CardFigure(value: "\(s.runs)", label: "Discese", size: 34)
                    .frame(width: 96)
            }
            .padding(.top, 14)
            HStack(spacing: 0) {
                CardFigure(value: Fmt.speed(s.maxSpeed), label: "Velocità max")
                CardFigure(value: Fmt.distance(s.runDistance), label: "Sciati")
                CardFigure(value: Fmt.duration(s.runTime > 0 ? s.runTime : s.totalTime), label: "Tempo in pista")
            }
            .padding(.top, 12)
            if !pistes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(pistes) { piste in
                        HStack(spacing: 9) {
                            PisteBadge(difficulty: piste.difficulty, ref: piste.ref, size: 22)
                            Text(piste.name).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text).lineLimit(1)
                            Spacer(minLength: 6)
                            Text(verbatim: "×\(piste.times)").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Theme.sub)
                        }
                    }
                }
                .padding(.top, 16)
            }
            Rectangle().fill(Theme.line).frame(height: 1).padding(.top, 14)
            CardFoot(symbol: (day.sport ?? .ski).symbol).padding(.top, 12)
        }
        .padding(22)
        .frame(width: format.size.width, height: format.size.height)
        .background(
            LinearGradient(stops: [.init(color: Theme.sky, location: 0), .init(color: Theme.bg, location: 0.5), .init(color: Theme.deep, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        )
        .fontDesign(.rounded)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(day.title ?? String(localized: "Giornata sulla neve"))
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2).minimumScaleFactor(0.6)
                Text(Fmt.day(day.start).capitalized + " " + day.start.formatted(.dateTime.year()))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.sub)
            }
            Spacer(minLength: 8)
            if let weather = day.weather {
                VStack(alignment: .trailing, spacing: 3) {
                    Image(systemName: weather.symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.accent)
                    Text(Fmt.temperature(weather.tempMax)).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.sub)
                }
            }
        }
    }
}

/// The lines of a day without a map under them, fitted to the space they are given: the lifts
/// thin and grey, each run in the color of its piste with a white edge, as on the map.
struct TrackSketch: View {
    let tracks: [MapTrack]

    var body: some View {
        let runs = tracks.filter { $0.kind == .run }
        ZStack {
            ForEach(tracks.filter { $0.kind == .lift }) { track in
                TrackLine(coordinates: track.coordinates, bounds: bounds)
                    .stroke(Theme.sub.opacity(0.75), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round, dash: [4, 4]))
            }
            ForEach(runs) { track in
                TrackLine(coordinates: track.coordinates, bounds: bounds)
                    .stroke(Color.white.opacity(0.92), style: StrokeStyle(lineWidth: 4.6, lineCap: .round, lineJoin: .round))
            }
            ForEach(runs) { track in
                TrackLine(coordinates: track.coordinates, bounds: bounds)
                    .stroke(Theme.difficultyColor(track.difficulty) ?? Theme.track, style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
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
    @State private var format = Demo.screen == "story" ? CardFormat.story : CardFormat.post

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Picker("Formato", selection: $format) {
                    ForEach(CardFormat.allCases) { Text(LocalizedStringKey($0.label)).tag($0) }
                }
                .pickerStyle(.segmented)
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
            .task(id: format) { render() }
        }
        .modifier(Dressed())
    }

    @MainActor private func render() {
        let tracks = MapTrack.build(points: day.points, segments: day.segments, maxPoints: 200)
        let card = ShareCard(day: day, tracks: tracks, format: format)
        let renderer = ImageRenderer(content: card.environment(\.colorScheme, Theme.dark ? .dark : .light))
        renderer.scale = 3
        guard let made = renderer.uiImage, let data = made.pngData() else { return }
        image = made
        let name = DateFormatter()
        name.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ski Apex \(name.string(from: day.start)) \(format.rawValue).png")
        try? data.write(to: url, options: .atomic)
        file = url
    }
}
