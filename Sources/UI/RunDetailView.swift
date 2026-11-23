import Charts
import MapKit
import SwiftUI

/// One run: where it went on the map, drawn in the colors of its speed, its numbers, and the
/// speed and the altitude from top to bottom.
struct RunDetailView: View {
    let day: SkiDay
    let run: Segment
    @AppStorage(Prefs.mapLook) private var mapLook = MapLook.standard.rawValue
    @State private var tracks: [MapTrack] = []
    @State private var chunks: [SpeedChunk] = []
    @State private var profile: [ProfilePoint] = []

    private var look: MapLook { MapLook(rawValue: mapLook) ?? .standard }
    private var title: String { run.name ?? String(localized: "Discesa \(run.number)") }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 10) {
                    PlaceMap(tracks: tracks, dimmed: true,
                             lines: chunks.map { MapLine(coordinates: $0.coordinates, color: UIColor(Theme.speedColors[$0.bucket]), width: 6) })
                        .frame(height: 300)
                        .id(chunks.count)
                    HStack(spacing: 8) {
                        Text("Lento").font(.caption2).foregroundStyle(Theme.sub)
                        LinearGradient(colors: Theme.speedColors, startPoint: .leading, endPoint: .trailing)
                            .frame(height: 6)
                            .clipShape(Capsule())
                        Text(Fmt.speed(run.maxSpeed)).font(.caption2).foregroundStyle(Theme.sub)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Colori della velocità, da lento a veloce"))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.display(.title3)).foregroundStyle(Theme.text)
                    HStack(spacing: 8) {
                        Text("\(Fmt.time(run.startTime)) – \(Fmt.time(run.endTime))").font(.caption).foregroundStyle(Theme.sub)
                        if let label = Theme.difficultyLabel(run.difficulty) {
                            HStack(spacing: 5) {
                                DifficultyDot(difficulty: run.difficulty)
                                Text(LocalizedStringKey(label)).font(.caption).foregroundStyle(Theme.text)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                StatGrid {
                    StatTile(value: Fmt.speed(run.maxSpeed), label: "Velocità max", symbol: "speedometer")
                    StatTile(value: Fmt.speed(run.avgSpeed), label: "Velocità media", symbol: "gauge.with.dots.needle.50percent")
                    StatTile(value: Fmt.height(run.drop), label: "Dislivello", symbol: "arrow.down.right")
                    StatTile(value: Fmt.distance(run.distance), label: "Lunghezza", symbol: "point.topleft.down.to.point.bottomright.curvepath")
                    StatTile(value: Fmt.duration(run.duration), label: "Durata", symbol: "stopwatch")
                    StatTile(value: Fmt.percent(run.slope), label: "Pendenza media", symbol: "triangle")
                    StatTile(value: Fmt.height(run.topAlt), label: "Partenza", symbol: "arrow.up.to.line")
                    StatTile(value: Fmt.height(run.bottomAlt), label: "Arrivo", symbol: "arrow.down.to.line")
                }

                if profile.count > 2 {
                    Panel("Velocità") {
                        SpeedChart(points: profile, start: run.startTime)
                            .frame(height: 170)
                    }
                    Panel("Quota") {
                        AltitudeChart(points: profile)
                            .frame(height: 150)
                    }
                }
            }
            .padding(16)
        }
        .screen()
        .navigationTitle(String(localized: "Discesa \(run.number)"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            tracks = MapTrack.build(points: day.points, segments: day.segments).filter { $0.id != run.id }
            chunks = SpeedChunk.make(day.points[run.start...run.end], top: run.maxSpeed)
            profile = ProfilePoint.make(day, in: run.start...run.end, maxPoints: 300)
        }
    }

    /// The run, with a little room around it.
    private var region: MapCameraPosition {
        let pts = day.points[run.start...run.end]
        guard let minLat = pts.map(\.lat).min(), let maxLat = pts.map(\.lat).max(),
              let minLon = pts.map(\.lon).min(), let maxLon = pts.map(\.lon).max() else { return .automatic }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.004, (maxLat - minLat) * 1.4), longitudeDelta: max(0.004, (maxLon - minLon) * 1.4))
        return .region(MKCoordinateRegion(center: center, span: span))
    }
}

/// A piece of a run skied at about the same speed: one line on the map, in the color of that speed.
struct SpeedChunk: Identifiable {
    let id: Int
    /// From 0, the slowest fifth of the run's top speed, to 4.
    let bucket: Int
    let coordinates: [CLLocationCoordinate2D]

    static func make(_ points: ArraySlice<TrackPoint>, top: Double) -> [SpeedChunk] {
        guard points.count > 1, top > 0 else { return [] }
        let step = max(1, points.count / 400)
        let count = Theme.speedColors.count
        var out: [SpeedChunk] = []
        var current: [CLLocationCoordinate2D] = []
        var bucket = -1
        var i = points.startIndex
        while i < points.endIndex {
            let p = points[i]
            let b = min(count - 1, max(0, Int(max(0, p.speed) / top * Double(count))))
            if b != bucket, !current.isEmpty {
                // The pieces share a point, so that the line has no holes.
                current.append(p.coordinate)
                out.append(SpeedChunk(id: out.count, bucket: bucket, coordinates: current))
                current = []
            }
            bucket = b
            current.append(p.coordinate)
            i += step
        }
        if current.count > 1 { out.append(SpeedChunk(id: out.count, bucket: bucket, coordinates: current)) }
        return out
    }
}

/// The speed along a run, against the time from its start.
struct SpeedChart: View {
    let points: [ProfilePoint]
    let start: Date

    var body: some View {
        let factor = Units.current == .metric ? 3.6 : 2.236_94
        Chart(points) { p in
            AreaMark(x: .value("Tempo", p.t.timeIntervalSince(start)), y: .value("Velocità", p.speed * factor))
                .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.35), Theme.accent.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Tempo", p.t.timeIntervalSince(start)), y: .value("Velocità", p.speed * factor))
                .foregroundStyle(Theme.accent)
                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .interpolationMethod(.monotone)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel {
                    if let s = value.as(Double.self) { Text(Fmt.clock(s).replacingOccurrences(of: "0:", with: "", options: .anchored)).font(.caption2).foregroundStyle(Theme.sub) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text("\(Int(v))").font(.caption2).foregroundStyle(Theme.sub) }
                }
            }
        }
        .chartYAxisLabel(Fmt.speedUnit)
    }
}
