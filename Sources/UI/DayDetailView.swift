import Charts
import MapKit
import SwiftUI

/// A day saved: its map, its numbers, the altitude through the day and every run.
struct DayDetailView: View {
    let id: UUID
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.mapLook) private var mapLook = MapLook.standard.rawValue
    @State private var day: SkiDay?
    @State private var tracks: [MapTrack] = []
    @State private var profile: [ProfilePoint] = []
    @State private var gpx: URL?
    @State private var confirmDelete = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var run: Segment?
    @State private var missing = false

    private var look: MapLook { MapLook(rawValue: mapLook) ?? .standard }

    var body: some View {
        ScrollView {
            if let day {
                content(day)
            } else if missing {
                Text("Questa giornata non si trova più.").foregroundStyle(Theme.sub).padding(40)
            } else {
                ProgressView().padding(60)
            }
        }
        .screen()
        .navigationTitle(day?.place ?? String(localized: "Giornata"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let gpx {
                        ShareLink(item: gpx) { Label("Esporta GPX", systemImage: "square.and.arrow.up") }
                    }
                    Button {
                        newName = day?.place ?? ""
                        renaming = true
                    } label: { Label("Rinomina", systemImage: "pencil") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Elimina", systemImage: "trash") }
                } label: {
                    Label("Altro", systemImage: "ellipsis")
                }
            }
        }
        .task(id: id) { load() }
        .alert("Nome della giornata", isPresented: $renaming) {
            TextField("Località", text: $newName)
            Button("Salva") {
                library.rename(id, to: newName)
                load()
            }
            Button("Annulla", role: .cancel) {}
        }
        .confirmationDialog("Eliminare questa giornata?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                library.delete(id)
                dismiss()
            }
        } message: {
            Text("Non si può annullare.")
        }
        .navigationDestination(item: $run) { seg in
            if let day { RunDetailView(day: day, run: seg) }
        }
    }

    private func load() {
        guard let loaded = library.day(id) else {
            missing = true
            return
        }
        day = loaded
        tracks = MapTrack.build(points: loaded.points, segments: loaded.segments)
        profile = ProfilePoint.make(loaded)
        gpx = try? GPX.file(loaded)
    }

    @ViewBuilder private func content(_ day: SkiDay) -> some View {
        VStack(spacing: 14) {
            ZStack(alignment: .topTrailing) {
                Map(initialPosition: .automatic) {
                    TrackMapContent(tracks: tracks)
                }
                .mapStyle(look.style)
                .frame(height: 320)
                .clipShape(Theme.round)
                .overlay(Theme.round.strokeBorder(Theme.line, lineWidth: 1))
                MapButton(symbol: look == .standard ? "globe.europe.africa" : "map",
                          label: look == .standard ? "Satellite" : "Mappa") {
                    mapLook = (look == .standard ? MapLook.satellite : MapLook.standard).rawValue
                }
                .padding(10)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(Fmt.day(day.start).capitalized).font(.display(.title3)).foregroundStyle(Theme.text)
                Text("\(Fmt.time(day.start)) – \(Fmt.time(day.end)) · \(Fmt.duration(day.stats.totalTime))")
                    .font(.caption).foregroundStyle(Theme.sub)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            let s = day.stats
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                StatTile(value: "\(s.runs)", label: "Discese", symbol: "figure.skiing.downhill")
                StatTile(value: Fmt.height(s.vertical), label: "Dislivello", symbol: "arrow.down.right")
                StatTile(value: Fmt.speed(s.maxSpeed), label: "Velocità max", symbol: "speedometer")
                StatTile(value: Fmt.distance(s.runDistance), label: "Sciati", symbol: "point.topleft.down.to.point.bottomright.curvepath")
                StatTile(value: Fmt.speed(s.avgRunSpeed), label: "Media in pista", symbol: "gauge.with.dots.needle.50percent")
                StatTile(value: Fmt.height(s.topAlt), label: "Quota max", symbol: "mountain.2")
                StatTile(value: Fmt.duration(s.runTime), label: "Tempo in pista", symbol: "stopwatch")
                StatTile(value: Fmt.duration(s.liftTime), label: "Tempo in risalita", symbol: "cablecar")
            }

            if profile.count > 2 {
                Panel("Quota durante la giornata") {
                    AltitudeChart(points: profile)
                        .frame(height: 180)
                    HStack(spacing: 14) {
                        legend(Theme.accent, "Discese")
                        legend(Theme.lift, "Risalite")
                        legend(Theme.sub, "Pause")
                    }
                }
            }

            if !day.runs.isEmpty {
                Panel("Discese") {
                    ForEach(day.runs) { seg in
                        Button { run = seg } label: { RunRow(run: seg) }
                            .buttonStyle(PressStyle())
                        if seg.id != day.runs.last?.id { Divider().overlay(Theme.line) }
                    }
                }
            } else {
                Panel {
                    Text("Nessuna discesa riconosciuta: servono almeno \(Int(Segmenter.minRunDrop)) m di dislivello in movimento.")
                        .prose().font(.subheadline).foregroundStyle(Theme.sub)
                }
            }
        }
        .padding(16)
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 14, height: 4)
            Text(LocalizedStringKey(label)).font(.caption2).foregroundStyle(Theme.sub)
        }
    }
}

/// One run in the list of a day.
struct RunRow: View {
    let run: Segment

    var body: some View {
        HStack(spacing: 12) {
            Text("\(run.number)")
                .font(.display(.subheadline))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 34, height: 34)
                .background(Theme.runColor(run.number), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("\(Fmt.time(run.startTime)) · \(Fmt.duration(run.duration))")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Text("\(Fmt.height(run.drop)) ↓ · \(Fmt.distance(run.distance))")
                    .font(.caption).foregroundStyle(Theme.sub)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.speedValue(run.maxSpeed)).font(.display(.headline)).monospacedDigit().foregroundStyle(Theme.accent)
                Text("max \(Fmt.speedUnit)").font(.caption2).foregroundStyle(Theme.sub)
            }
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.sub)
        }
        .contentShape(Rectangle())
    }
}

/// A point of the altitude chart, with the kind of stretch it is in.
struct ProfilePoint: Identifiable {
    let id: Int
    let t: Date
    let alt: Double
    let speed: Double
    let kind: SegmentKind
    /// Which stretch: a new line in the chart for each.
    let segment: Int

    /// At most `maxPoints` points of the day, each with its stretch.
    static func make(_ day: SkiDay, in range: ClosedRange<Int>? = nil, maxPoints: Int = 500) -> [ProfilePoint] {
        let points = day.points
        guard !points.isEmpty else { return [] }
        let span = range ?? 0...(points.count - 1)
        let step = max(1, span.count / maxPoints)
        var out: [ProfilePoint] = []
        var segIndex = 0
        var i = span.lowerBound
        while i <= span.upperBound {
            while segIndex + 1 < day.segments.count && day.segments[segIndex].end < i { segIndex += 1 }
            let seg = day.segments.isEmpty ? nil : day.segments[segIndex]
            let p = points[i]
            out.append(ProfilePoint(id: i, t: p.t, alt: p.alt, speed: max(0, p.speed),
                                    kind: seg?.kind ?? .idle, segment: seg?.start ?? 0))
            i += step
        }
        return out
    }
}

/// The altitude through the day: runs in the accent, lifts in lilac, the rest in gray.
struct AltitudeChart: View {
    let points: [ProfilePoint]

    var body: some View {
        let lo = points.map(\.alt).min() ?? 0
        let hi = points.map(\.alt).max() ?? 1
        let pad = max(20, (hi - lo) * 0.08)
        Chart(points) { p in
            LineMark(x: .value("Ora", p.t), y: .value("Quota", p.alt), series: .value("Tratto", p.segment))
                .foregroundStyle(color(p.kind))
                .lineStyle(StrokeStyle(lineWidth: p.kind == .run ? 2.5 : 1.8, lineCap: .round))
        }
        .chartYScale(domain: (lo - pad)...(hi + pad))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel(format: .dateTime.hour().minute()).foregroundStyle(Theme.sub)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel {
                    if let m = value.as(Double.self) { Text(Fmt.height(m)).font(.caption2).foregroundStyle(Theme.sub) }
                }
            }
        }
    }

    private func color(_ kind: SegmentKind) -> Color {
        switch kind {
        case .run: Theme.accent
        case .lift: Theme.lift
        case .idle: Theme.sub.opacity(0.6)
        }
    }
}
