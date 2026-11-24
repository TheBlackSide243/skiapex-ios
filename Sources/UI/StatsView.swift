import Charts
import SwiftUI

/// The numbers of a season, or of all of them: totals, averages, the records with the day they
/// were set on, and each day side by side. Opened from the diary, inside its navigation.
struct StatsView: View {
    @Environment(Library.self) private var library
    /// nil: every season together.
    @State private var season: Season?
    @State private var all = false
    @State private var heat = Demo.screen == "heat"
    @State private var recapping = Demo.screen == "recap"
    @State private var pistes = ["pistes", "piste"].contains(Demo.screen ?? "")

    var body: some View {
        Group {
            ScrollView {
                VStack(spacing: 14) {
                    if library.days.isEmpty {
                        empty
                    } else {
                        scope
                        totals
                        records
                        Button { pistes = true } label: { pistesRow }
                            .buttonStyle(PressStyle())
                        HStack(spacing: 10) {
                            Button { heat = true } label: { Label("Mappa di calore", systemImage: "flame") }
                                .buttonStyle(SecondaryButtonStyle())
                            Button { recapping = true } label: { Label("Riepilogo", systemImage: "square.and.arrow.up") }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                        if days.count > 1 { charts }
                    }
                }
                .padding(16)
            }
            .screen()
            .navigationTitle("Statistiche")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $heat) { HeatmapView() }
            .navigationDestination(isPresented: $pistes) { PistesView() }
            .sheet(isPresented: $recapping) {
                SeasonSheet(recap: SeasonRecap(label: current?.label ?? String(localized: "Sempre"), days: days))
            }
        }
    }

    /// The way to the book of the pistes, with how many there are in it.
    private var pistesRow: some View {
        let known = Set(library.days.flatMap { day in (day.pistes ?? []).map { "\($0.n)|\(day.title ?? "")" } }).count
        return HStack(spacing: 12) {
            Image(systemName: "signpost.right.fill").font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
                .frame(width: 40, height: 40)
                .iconBox()
            VStack(alignment: .leading, spacing: 3) {
                Text("Le tue piste").font(.headline).foregroundStyle(Theme.text)
                Text(known == 0 ? String(localized: "Quante volte, tempo migliore, sfida con gli amici")
                     : String(localized: "\(known) piste: volte, tempo migliore, sfida con gli amici"))
                    .font(.caption).foregroundStyle(Theme.sub).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right").font(.subheadline.weight(.bold)).foregroundStyle(Theme.sub)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .contentShape(Rectangle())
    }

    private var current: Season? { all ? nil : (season ?? library.seasons.first) }
    private var days: [DaySummary] { library.days(in: current) }

    private var scope: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(library.seasons) { s in
                    pill(s.label, on: !all && s == current) {
                        all = false
                        season = s
                    }
                }
                if library.seasons.count > 1 {
                    pill(String(localized: "Sempre"), on: all) { all = true }
                }
            }
        }
    }

    private func pill(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { action() } } label: {
            Text(text).font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16).padding(.vertical, 9)
                .foregroundStyle(on ? Theme.onAccent : Theme.text)
                .background(on ? Theme.accent : Theme.input, in: Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var totals: some View {
        let s = days.map(\.stats)
        let count = Double(max(1, days.count))
        let vertical = s.reduce(0) { $0 + $1.vertical }
        let runs = s.reduce(0) { $0 + $1.runs }
        return VStack(spacing: 10) {
            StatGrid {
                StatTile(value: "\(days.count)", label: "Giornate", symbol: "calendar")
                StatTile(value: "\(runs)", label: "Discese", symbol: "figure.skiing.downhill")
                StatTile(value: Fmt.height(vertical), label: "Dislivello", symbol: "arrow.down.right")
                StatTile(value: Fmt.distance(s.reduce(0) { $0 + $1.runDistance }), label: "Sciati", symbol: "point.topleft.down.to.point.bottomright.curvepath")
                StatTile(value: Fmt.duration(s.reduce(0) { $0 + $1.runTime }), label: "Tempo in pista", symbol: "stopwatch")
                StatTile(value: "\(s.reduce(0) { $0 + $1.lifts })", label: "Risalite", symbol: "cablecar")
            }
            Panel("In media al giorno") {
                InfoRow("Discese", (Double(runs) / count).formatted(.number.precision(.fractionLength(1))))
                InfoRow("Dislivello", Fmt.height(vertical / count))
                InfoRow("Sciati", Fmt.distance(s.reduce(0) { $0 + $1.runDistance } / count))
                InfoRow("Tempo in pista", Fmt.duration(s.reduce(0) { $0 + $1.runTime } / count))
            }
        }
    }

    /// The most of something, and the day it happened on.
    private struct Record: Identifiable {
        let id: String
        let symbol: String
        let day: DaySummary
        let value: String
    }

    private var recordList: [Record] {
        var out: [Record] = []
        func add(_ label: String, _ symbol: String, _ key: (DayStats) -> Double, _ text: (DayStats) -> String) {
            guard let day = days.max(by: { key($0.stats) < key($1.stats) }), key(day.stats) > 0 else { return }
            out.append(Record(id: label, symbol: symbol, day: day, value: text(day.stats)))
        }
        add("Velocità max", "speedometer", { $0.maxSpeed }, { Fmt.speed($0.maxSpeed) })
        add("Più dislivello in un giorno", "arrow.down.right", { $0.vertical }, { Fmt.height($0.vertical) })
        add("Più discese in un giorno", "figure.skiing.downhill", { Double($0.runs) }, { "\($0.runs)" })
        add("Discesa più lunga", "point.topleft.down.to.point.bottomright.curvepath", { $0.longestRun }, { Fmt.distance($0.longestRun) })
        add("Più chilometri in un giorno", "road.lanes", { $0.runDistance }, { Fmt.distance($0.runDistance) })
        add("Quota più alta", "mountain.2", { $0.topAlt }, { Fmt.height($0.topAlt) })
        return out
    }

    @ViewBuilder private var records: some View {
        let list = recordList
        if !list.isEmpty {
            Panel("Record") {
                ForEach(list) { record in
                    NavigationLink(value: record.day.id) { row(record) }
                        .buttonStyle(PressStyle())
                    if record.id != list.last?.id { Divider().overlay(Theme.line) }
                }
            }
        }
    }

    private func row(_ record: Record) -> some View {
        let place = record.day.title ?? String(localized: "Giornata sulla neve")
        let when = "\(place) · \(Fmt.dayShort(record.day.start))"
        return HStack(spacing: 12) {
            Image(systemName: record.symbol).font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .iconBox()
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(record.id)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(when).font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(record.value).font(.display(.subheadline)).monospacedDigit().foregroundStyle(Theme.accent)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.sub)
        }
        .contentShape(Rectangle())
    }

    private var charts: some View {
        let ordered = days.sorted { $0.start < $1.start }
        let speed = Units.current == .metric ? 3.6 : 2.236_94
        let height = Units.current == .metric ? 1.0 : 3.280_84
        return VStack(spacing: 14) {
            Panel("Dislivello per giornata") {
                Chart(ordered) { day in
                    BarMark(x: .value("Giorno", Fmt.dayShort(day.start)), y: .value("Dislivello", day.stats.vertical * height))
                        .foregroundStyle(Theme.accent)
                        .cornerRadius(5)
                }
                .chartXAxis(ordered.count <= 4 ? .automatic : .hidden)
                .chartYAxis { axisValues }
                .frame(height: 180)
            }
            Panel("Velocità max per giornata") {
                Chart(ordered) { day in
                    LineMark(x: .value("Giorno", Fmt.dayShort(day.start)), y: .value("Velocità", day.stats.maxSpeed * speed))
                        .foregroundStyle(Theme.lift)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    PointMark(x: .value("Giorno", Fmt.dayShort(day.start)), y: .value("Velocità", day.stats.maxSpeed * speed))
                        .foregroundStyle(Theme.lift)
                }
                .chartXAxis(ordered.count <= 4 ? .automatic : .hidden)
                .chartYAxis { axisValues }
                .frame(height: 160)
            }
        }
    }

    private var axisValues: some AxisContent {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
            AxisGridLine().foregroundStyle(Theme.line)
            AxisValueLabel().foregroundStyle(Theme.sub)
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 84, height: 84)
                .iconBox()
            Text("Ancora nessun numero").font(.display(.headline)).foregroundStyle(Theme.text)
            Text("Totali, medie e record compaiono qui dopo la prima giornata.")
                .prose().font(.subheadline).foregroundStyle(Theme.sub).multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .card()
        .padding(.top, 40)
    }
}
