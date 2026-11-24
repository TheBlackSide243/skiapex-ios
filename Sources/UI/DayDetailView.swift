import Charts
import MapKit
import Photos
import SwiftUI

/// A picture of the day, for the list and for the sheet that shows it.
struct PhotoItem: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

/// A day saved: its map, its numbers, the weather, the altitude through the day and everything
/// that happened in it, run by run.
struct DayDetailView: View {
    let id: UUID
    @Environment(Library.self) private var library
    @Environment(Social.self) private var social
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.mapLook) private var mapLook = MapLook.standard.rawValue
    @State private var day: SkiDay?
    @State private var tracks: [MapTrack] = []
    @State private var gpx: URL?
    @State private var confirmDelete = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var run: Segment?
    @State private var missing = false
    @State private var replaying = false
    @State private var sharing = false
    @State private var photos: [PhotoItem] = []
    @State private var viewing: PhotoItem?
    @State private var canAskPhotos = DayPhotos.canAsk
    @State private var error: String?
    @State private var busy = false
    /// Everything that happened, or the runs alone.
    @State private var everything = Demo.screen == "timeline"

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
        .navigationTitle(day?.title ?? String(localized: "Giornata"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { sharing = true } label: { Label("Condividi immagine", systemImage: "photo") }
                    if let gpx {
                        ShareLink(item: gpx) { Label("Esporta GPX", systemImage: "square.and.arrow.up") }
                    }
                    Button {
                        newName = day?.place ?? ""
                        renaming = true
                    } label: { Label("Rinomina", systemImage: "pencil") }
                    Button { library.ask(id) } label: { Label("Com'era la neve", systemImage: "snowflake") }
                    Menu {
                        ForEach(Sport.allCases) { sport in
                            Button {
                                library.setSport(id, to: sport)
                            } label: {
                                if (day?.sport ?? .ski) == sport {
                                    Label(LocalizedStringKey(sport.label), systemImage: "checkmark")
                                } else {
                                    Text(LocalizedStringKey(sport.label))
                                }
                            }
                        }
                    } label: { Label("Attività", systemImage: "figure.skiing.downhill") }
                    if HealthSync.available {
                        Button { Task { await toHealth() } } label: {
                            Label(LocalizedStringKey(day?.inHealth == true ? "Aggiorna il battito da Salute" : "Salva in Salute"), systemImage: "heart")
                        }
                    }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Elimina", systemImage: "trash") }
                } label: {
                    Label("Altro", systemImage: "ellipsis")
                }
            }
        }
        .task(id: id) {
            load()
            await library.enrich(id)
        }
        .onChange(of: library.saves) { _, _ in load() }
        .alert("Nome della giornata", isPresented: $renaming) {
            TextField("Località", text: $newName)
            Button("Salva") { library.rename(id, to: newName) }
            Button("Annulla", role: .cancel) {}
        }
        .confirmationDialog("Eliminare questa giornata?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                // What was told of it to who skis there goes with it.
                if let day, day.told == true {
                    let summary = day.summary
                    Task { await social.untell(summary) }
                }
                library.delete(id)
                dismiss()
            }
        } message: {
            Text("Non si può annullare.")
        }
        .navigationDestination(item: $run) { seg in
            if let day { RunDetailView(day: day, run: seg) }
        }
        .navigationDestination(isPresented: $replaying) {
            if let day { ReplayView(day: day) }
        }
        .sheet(isPresented: $sharing) {
            if let day { ShareSheet(day: day) }
        }
        .fullScreenCover(item: $viewing) { PhotoViewer(asset: $0.asset) }
    }

    private func load() {
        guard let loaded = library.day(id) else {
            // Deleted from here: the screen is closing.
            missing = day == nil
            return
        }
        let first = day == nil
        day = loaded
        tracks = MapTrack.build(points: loaded.points, segments: loaded.segments)
        gpx = loaded.points.isEmpty ? nil : (try? GPX.file(loaded))
        if !Demo.isOn { photos = DayPhotos.assets(from: loaded.start, to: loaded.end).map { PhotoItem(asset: $0) } }
        guard first else { return }
        switch Demo.screen {
        case "run": if loaded.runs.count > 2 { run = loaded.runs[2] }
        case "replay": replaying = true
        case "share", "story": sharing = true
        default: break
        }
    }

    /// Into Apple Health as a workout, and its heart rate back from there.
    private func toHealth() async {
        busy = true
        defer { busy = false }
        do {
            try await HealthSync.save(id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    @ViewBuilder private func content(_ day: SkiDay) -> some View {
        VStack(spacing: 14) {
            ErrorBanner(error: $error)
            if !day.points.isEmpty {
                PlaceMap(tracks: tracks)
                    .frame(height: 300)
                    .id(tracks.count)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(Fmt.day(day.start).capitalized).font(.display(.title3)).foregroundStyle(Theme.text)
                Text("\(Fmt.time(day.start)) – \(Fmt.time(day.end)) · \(Fmt.duration(day.stats.totalTime))")
                    .font(.caption).foregroundStyle(Theme.sub)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Chip(symbol: (day.sport ?? .ski).symbol, text: String(localized: String.LocalizationValue((day.sport ?? .ski).label)), color: Theme.accent)
                        if day.manual == true {
                            Chip(symbol: "square.and.pencil", text: String(localized: "Scritta a mano"))
                        }
                        if let resort = day.resort, resort != day.place {
                            Chip(symbol: "mountain.2", text: resort, color: Theme.accent)
                        }
                        if let weather = day.weather {
                            Chip(symbol: weather.symbol, text: "\(Fmt.temperature(weather.tempMin)) / \(Fmt.temperature(weather.tempMax))", color: Theme.accent)
                            if weather.snowfall >= 0.5 {
                                Chip(symbol: "snowflake", text: Fmt.snow(weather.snowfall), color: Theme.accent)
                            }
                            Chip(symbol: "wind", text: Fmt.wind(weather.windMax), color: Theme.accent)
                        }
                        if let snow = day.snow {
                            Chip(symbol: snow.symbol, text: String(localized: String.LocalizationValue(snow.label)), color: Theme.accent)
                        }
                        if day.inHealth == true {
                            Chip(symbol: "heart.fill", text: String(localized: "In Salute"), color: Theme.bad)
                        }
                        if busy { ProgressView().controlSize(.small) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                if !day.points.isEmpty {
                    Button { replaying = true } label: { Label("Rivivi", systemImage: "play.fill") }
                        .buttonStyle(PrimaryButtonStyle())
                }
                Button { sharing = true } label: { Label("Condividi", systemImage: "square.and.arrow.up") }
                    .buttonStyle(SecondaryButtonStyle())
            }

            if let legs = Leg.of(day), legs.count > 1, let range = DayProfile.range(legs) {
                Panel("Profilo della giornata") {
                    DayProfile(legs: legs, lineWidth: 2.8)
                        .frame(height: 124)
                    HStack {
                        Text(Fmt.time(day.start))
                        Spacer()
                        Text("\(Fmt.height(range.low)) – \(Fmt.height(range.high))")
                        Spacer()
                        Text(Fmt.time(day.end))
                    }
                    .font(.caption).monospacedDigit().foregroundStyle(Theme.sub)
                    HStack(spacing: 12) {
                        ForEach(["easy", "intermediate", "advanced"], id: \.self) { grade in
                            if legs.contains(where: { $0.k == 0 && Theme.difficultyLabel($0.d) == Theme.difficultyLabel(grade) }),
                               let label = Theme.difficultyLabel(grade) {
                                HStack(spacing: 5) {
                                    DifficultyDot(difficulty: grade, size: 9)
                                    Text(LocalizedStringKey(label)).font(.caption2).foregroundStyle(Theme.sub)
                                }
                            }
                        }
                        if legs.contains(where: { $0.k == 0 && Theme.difficultyColor($0.d) == nil }) { legend(Theme.accent, "Discese") }
                        legend(Theme.sub, "Risalite")
                    }
                }
            }

            let s = day.stats
            StatGrid {
                StatTile(value: "\(s.runs)", label: "Discese", symbol: "figure.skiing.downhill")
                StatTile(value: Fmt.height(s.vertical), label: "Dislivello", symbol: "arrow.down.right")
                StatTile(value: Fmt.speed(s.maxSpeed), label: "Velocità max", symbol: "speedometer")
                StatTile(value: Fmt.distance(s.runDistance), label: "Sciati", symbol: "point.topleft.down.to.point.bottomright.curvepath")
                StatTile(value: Fmt.speed(s.avgRunSpeed), label: "Media in pista", symbol: "gauge.with.dots.needle.50percent")
                StatTile(value: Fmt.height(s.topAlt), label: "Quota max", symbol: "mountain.2")
                StatTile(value: Fmt.duration(s.runTime), label: "Tempo in pista", symbol: "stopwatch")
                StatTile(value: Fmt.duration(s.liftTime), label: "Tempo in risalita", symbol: "cablecar")
                if let average = day.heartAvg, let top = day.heartMax {
                    StatTile(value: "\(Int(average.rounded())) bpm", label: "Battito medio", symbol: "heart")
                    StatTile(value: "\(Int(top.rounded())) bpm", label: "Battito max", symbol: "heart.fill")
                }
            }

            if !photos.isEmpty {
                Panel("Foto della giornata") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(photos) { item in
                                Button { viewing = item } label: { PhotoThumb(asset: item.asset) }
                                    .buttonStyle(PressStyle())
                            }
                        }
                    }
                }
            } else if canAskPhotos && !Demo.isOn {
                Button {
                    Task {
                        let allowed = await DayPhotos.ask()
                        canAskPhotos = false
                        if allowed { photos = DayPhotos.assets(from: day.start, to: day.end).map { PhotoItem(asset: $0) } }
                    }
                } label: { Label("Mostra le foto di questa giornata", systemImage: "photo.on.rectangle") }
                    .buttonStyle(SecondaryButtonStyle())
            }

            if day.points.isEmpty {
                Text("Questa giornata è stata scritta a mano: ha i numeri, ma non la traccia.")
                    .prose().font(.caption).foregroundStyle(Theme.sub)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if day.runs.isEmpty {
                Panel {
                    Text("Nessuna discesa riconosciuta: servono almeno \(Int(Segmenter.minRunDrop)) m di dislivello in movimento.")
                        .prose().font(.subheadline).foregroundStyle(Theme.sub)
                }
            } else {
                Panel {
                    Picker("Elenco", selection: $everything) {
                        Text("Discese").tag(false)
                        Text("Cronologia").tag(true)
                    }
                    .pickerStyle(.segmented)
                    let rows = everything ? day.segments.filter { $0.kind != .idle || $0.duration >= 180 } : day.runs
                    ForEach(rows) { seg in
                        switch seg.kind {
                        case .run:
                            Button { run = seg } label: { RunRow(run: seg) }
                                .buttonStyle(PressStyle())
                        case .lift:
                            StretchRow(segment: seg)
                        case .idle:
                            StretchRow(segment: seg)
                        }
                        if seg.id != rows.last?.id { Divider().overlay(Theme.line) }
                    }
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
            PisteBadge(difficulty: run.difficulty, ref: run.ref, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(run.name ?? String(localized: "Discesa \(run.number)"))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text("\(Fmt.time(run.startTime)) · \(Fmt.duration(run.duration)) · \(Fmt.height(run.drop)) ↓")
                    .font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.speedValue(run.maxSpeed)).font(.display(.headline)).monospacedDigit().foregroundStyle(Theme.accent)
                Text("max \(Fmt.speedUnit)").font(.caption2).foregroundStyle(Theme.sub)
            }
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.sub)
        }
        .contentShape(Rectangle())
    }
}

/// A lift or a break in the timeline of a day.
struct StretchRow: View {
    let segment: Segment

    var body: some View {
        let lift = segment.kind == .lift
        let title: String = lift ? (segment.name ?? String(localized: "Risalita \(segment.number)")) : String(localized: "Sosta")
        let when = "\(Fmt.time(segment.startTime)) · \(Fmt.duration(segment.duration))"
        let detail: String = lift ? "\(when) · \(Fmt.height(segment.gain)) ↑" : when
        HStack(spacing: 12) {
            Image(systemName: lift ? "cablecar" : "cup.and.saucer")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(lift ? Theme.lift : Theme.sub)
                .frame(width: 34, height: 34)
                .iconBox(lift ? Theme.lift : Theme.sub)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
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
