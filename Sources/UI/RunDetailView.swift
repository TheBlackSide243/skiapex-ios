import Charts
import MapKit
import SwiftUI

/// One run: where it went on the map, its numbers, and the speed from top to bottom.
struct RunDetailView: View {
    let day: SkiDay
    let run: Segment
    @AppStorage(Prefs.mapLook) private var mapLook = MapLook.standard.rawValue
    @State private var tracks: [MapTrack] = []
    @State private var profile: [ProfilePoint] = []

    private var look: MapLook { MapLook(rawValue: mapLook) ?? .standard }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Map(initialPosition: region) {
                    TrackMapContent(tracks: tracks, highlight: run.id)
                }
                .mapStyle(look.style)
                .frame(height: 300)
                .clipShape(Theme.round)
                .overlay(Theme.round.strokeBorder(Theme.line, lineWidth: 1))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Discesa \(run.number)").font(.display(.title3)).foregroundStyle(Theme.text)
                    Text("\(Fmt.time(run.startTime)) – \(Fmt.time(run.endTime))").font(.caption).foregroundStyle(Theme.sub)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
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
        .navigationTitle("Discesa \(run.number)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            tracks = MapTrack.build(points: day.points, segments: day.segments)
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
