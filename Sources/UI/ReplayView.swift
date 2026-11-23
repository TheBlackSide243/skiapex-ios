import Combine
import MapKit
import SwiftUI

/// The day played again: a dot goes along the track on the map, which follows it, with
/// the time, the speed and the altitude of that moment. Breaks go by faster.
struct ReplayView: View {
    let day: SkiDay
    @AppStorage(Prefs.mapLook) private var mapLook = MapLook.satellite.rawValue
    @State private var tracks: [MapTrack] = []
    /// Seconds from the start of the day of each point.
    @State private var times: [Double] = []
    /// Where the replay is, in seconds from the start of the day.
    @State private var now: Double = 0
    @State private var playing = false
    /// Seconds of the day for each second of replay.
    @State private var rate: Double = 60
    @State private var follow = true
    /// Counts the times the map went back to showing the whole day.
    @State private var overview = 0

    private let frames = 20.0
    private let clock = Timer.publish(every: 1.0 / 20.0, on: .main, in: .common).autoconnect()
    private var total: Double { max(1, day.end.timeIntervalSince(day.start)) }
    private var look: MapLook { MapLook(rawValue: mapLook) ?? .satellite }

    var body: some View {
        let index = pointIndex(at: now)
        let here = position(at: now, index: index)
        ZStack(alignment: .bottom) {
            SnowMap(tracks: tracks, dot: here.coordinate,
                    region: SnowMap.fit(tracks.flatMap(\.coordinates)) ?? MKCoordinateRegion(center: here.coordinate, latitudinalMeters: 4000, longitudinalMeters: 4000),
                    regionKey: "\(tracks.count)|\(overview)", center: follow ? here.coordinate : nil, bottomInset: 170, showsUser: false)
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 12) {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        MapButton(symbol: follow ? "video.fill" : "map.fill", label: follow ? "Vista dall'alto" : "Segui") {
                            follow.toggle()
                            if !follow { overview += 1 }
                        }
                    }
                }
                Spacer()
                panel(here, index: index)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle("Rivivi la giornata")
        .navigationBarTitleDisplayMode(.inline)
        .hidesRail()
        .onAppear { prepare() }
        .onDisappear { playing = false }
        .onReceive(clock) { _ in tick() }
    }

    // MARK: Pieces

    private func panel(_ here: TrackPoint, index: Int) -> some View {
        let segment = day.segments.last { $0.start <= index }
        return VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Fmt.time(day.start.addingTimeInterval(now))).font(.display(.title2)).monospacedDigit().foregroundStyle(Theme.text)
                    Text(label(segment)).font(.caption.weight(.semibold)).foregroundStyle(color(segment)).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(Fmt.speed(max(0, here.speed))).font(.display(.headline)).monospacedDigit().foregroundStyle(Theme.text)
                    Label(Fmt.height(here.alt), systemImage: "mountain.2").font(.caption).foregroundStyle(Theme.sub)
                }
            }
            Slider(value: $now, in: 0...total) { editing in
                if editing { playing = false }
            }
            .tint(Theme.accent)
            .accessibilityLabel(Text("Momento della giornata"))
            HStack(spacing: 12) {
                Button {
                    if now >= total - 1 { now = 0 }
                    playing.toggle()
                } label: {
                    Label(LocalizedStringKey(playing ? "Pausa" : "Riproduci"), systemImage: playing ? "pause.fill" : "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                Menu {
                    ForEach([30.0, 60, 120, 300], id: \.self) { value in
                        Button("\(Int(value))×") { rate = value }
                    }
                } label: {
                    Text("\(Int(rate))×").font(.headline.weight(.semibold)).foregroundStyle(Theme.text)
                        .frame(width: 84)
                        .padding(.vertical, 15)
                        .background(Theme.input, in: Capsule())
                }
                .accessibilityLabel(Text("Velocità del replay"))
            }
        }
        .padding(18)
        .glass()
    }

    private func label(_ segment: Segment?) -> String {
        guard let segment else { return "" }
        switch segment.kind {
        case .run: return segment.name ?? String(localized: "Discesa \(segment.number)")
        case .lift: return segment.name ?? String(localized: "Risalita \(segment.number)")
        case .idle: return String(localized: "Sosta")
        }
    }

    private func color(_ segment: Segment?) -> Color {
        switch segment?.kind {
        case .run?: Theme.accent
        case .lift?: Theme.lift
        default: Theme.sub
        }
    }

    // MARK: Time

    private func prepare() {
        guard times.isEmpty else { return }
        times = day.points.map { $0.t.timeIntervalSince(day.start) }
        tracks = MapTrack.build(points: day.points, segments: day.segments)
        // The pictures of the README: stopped in the middle of the third run.
        if Demo.screen == "replay", day.runs.count > 2 {
            let run = day.runs[2]
            now = run.startTime.timeIntervalSince(day.start) + run.duration * 0.3
        } else if let first = day.segments.first(where: { $0.kind != .idle }) {
            // Not the minutes spent putting the boots on.
            now = max(0, first.startTime.timeIntervalSince(day.start) - 5)
        }
    }

    private func tick() {
        guard playing, !times.isEmpty else { return }
        let index = pointIndex(at: now)
        let idle = day.segments.last { $0.start <= index }?.kind == .idle
        now = min(total, now + rate / frames * (idle ? 6 : 1))
        if now >= total { playing = false }
    }

    /// The last point at or before a moment.
    private func pointIndex(at seconds: Double) -> Int {
        guard times.count > 1 else { return 0 }
        var lo = 0, hi = times.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if times[mid] <= seconds { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// Where the day was at a moment: between two points, in proportion.
    private func position(at seconds: Double, index i: Int) -> TrackPoint {
        guard !day.points.isEmpty else { return TrackPoint(t: day.start, lat: 0, lon: 0, alt: 0, speed: 0, hAcc: 0, sAcc: 0) }
        let a = day.points[min(i, day.points.count - 1)]
        guard i + 1 < day.points.count, i < times.count - 1 else { return a }
        let b = day.points[i + 1]
        let span = times[i + 1] - times[i]
        // Across a pause of the recording, it waits where it stopped.
        guard span > 0, span <= Segmenter.gap else { return a }
        let f = max(0, min(1, (seconds - times[i]) / span))
        return TrackPoint(t: day.start.addingTimeInterval(seconds),
                          lat: a.lat + (b.lat - a.lat) * f, lon: a.lon + (b.lon - a.lon) * f,
                          alt: a.alt + (b.alt - a.alt) * f, speed: a.speed + (b.speed - a.speed) * f,
                          hAcc: a.hAcc, sAcc: a.sAcc)
    }
}
