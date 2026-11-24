import MapKit
import SwiftUI
import UniformTypeIdentifiers

/// The diary: the totals of always, the trips to come and the days saved, season by season. The
/// map of the places skied is behind the sheet (see `Backdrop`).
struct DaysView: View {
    @Environment(Library.self) private var library
    @State private var season: Season?
    @State private var path: [UUID] = []
    @State private var importing = false
    @State private var writing = Demo.screen == "manual"
    @State private var trip: Trip?
    @State private var newTrip: Trip?
    @State private var error: String?
    @State private var numbers = ["stats", "heat", "recap", "pistes", "piste"].contains(Demo.screen ?? "")

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 14) {
                    ErrorBanner(error: $error)
                    if !library.days.isEmpty { lifetime }
                    upcoming
                    if library.days.isEmpty {
                        empty
                    } else {
                        if library.seasons.count > 1 { seasonPicker }
                        totals
                        ForEach(shown) { day in
                            NavigationLink(value: day.id) { DayCard(day: day) }
                                .buttonStyle(PressStyle())
                        }
                    }
                }
                .padding(16)
            }
            .screen()
            .navigationTitle("Giornate")
            .navigationDestination(for: UUID.self) { DayDetailView(id: $0) }
            .navigationDestination(isPresented: $numbers) { StatsView() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { newTrip = blankTrip } label: { Label("Viaggio", systemImage: "airplane.departure") }
                        Button { writing = true } label: { Label("Attività manuale", systemImage: "square.and.pencil") }
                        Button { importing = true } label: { Label("Importa da file", systemImage: "doc") }
                    } label: {
                        Label("Aggiungi", systemImage: "plus")
                    }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml, .xml],
                          allowsMultipleSelection: true) { result in
                bring(result)
            }
            .sheet(isPresented: $writing) { ManualDayView() }
            .sheet(item: $trip) { TripEditor(trip: $0) }
            .sheet(item: $newTrip) { TripEditor(trip: $0, isNew: true) }
            .onAppear {
                if season == nil { season = library.seasons.first }
                // The screenshots of a day open the newest one.
                let inside = ["day", "timeline", "run", "replay", "share"]
                if inside.contains(Demo.screen ?? ""), path.isEmpty, let first = library.days.first { path = [first.id] }
            }
        }
    }

    private var blankTrip: Trip {
        let start = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        return Trip(name: "", start: start, end: start.addingTimeInterval(2 * 86_400), resort: nil)
    }

    /// The files chosen become days; the last one is opened.
    private func bring(_ result: Result<[URL], Error>) {
        do {
            var last: UUID?
            for url in try result.get() {
                let id = try library.importGPX(url)
                last = id
                Task { await library.enrich(id) }
            }
            season = nil
            if let last { path = [last] }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private var current: Season? { season ?? library.seasons.first }
    private var shown: [DaySummary] { library.days(in: current) }

    // MARK: The numbers of always

    private var lifetime: some View {
        let s = library.days.map(\.stats)
        return Button { numbers = true } label: {
            HStack(spacing: 14) {
                lifetimeFigure("\(Set(library.days.map { Calendar.current.startOfDay(for: $0.start) }).count) \(String(localized: "giorni"))", "registrati", "calendar")
                Rectangle().fill(Theme.line).frame(width: 1, height: 36)
                lifetimeFigure(Fmt.height(s.reduce(0) { $0 + $1.vertical }), "dislivello", "arrow.down")
                Spacer(minLength: 4)
                Image(systemName: "chart.bar.xaxis").font(.body.weight(.semibold)).foregroundStyle(Theme.sub)
                Image(systemName: "chevron.right").font(.subheadline.weight(.bold)).foregroundStyle(Theme.sub)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .accessibilityHint(Text("Statistiche, record e mappa di calore"))
        }
        .buttonStyle(PressStyle())
    }

    private func lifetimeFigure(_ value: String, _ label: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            FigureText(value).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.caption2.weight(.bold))
                Text(LocalizedStringKey(label)).font(.subheadline)
            }
            .foregroundStyle(Theme.sub).lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    // MARK: The trips to come

    @ViewBuilder private var upcoming: some View {
        let trips = library.upcomingTrips
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Prossimamente")
            ForEach(trips) { item in
                Button { trip = item } label: { TripCard(trip: item) }
                    .buttonStyle(PressStyle())
            }
            if trips.isEmpty {
                Button { newTrip = blankTrip } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus").font(.subheadline.weight(.bold)).foregroundStyle(Theme.accent)
                            .frame(width: 40, height: 40)
                            .iconBox()
                        Text("Aggiungi il tuo prossimo viaggio").font(.headline).foregroundStyle(Theme.accent)
                            .lineLimit(2).multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .padding(20)
                    .card()
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
    }

    // MARK: The seasons

    private var seasonPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(library.seasons) { s in
                    let on = s == current
                    Button { withAnimation(.snappy) { season = s } } label: {
                        ChoicePill(title: s.label, on: on)
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
    }

    private var totals: some View {
        let days = shown
        let s = days.map(\.stats)
        let label = current?.label ?? ""
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(String(localized: "Stagione \(label)"))
            StatGrid {
                StatTile(value: "\(days.count)", label: "Giornate", symbol: "calendar")
                StatTile(value: "\(s.reduce(0) { $0 + $1.runs })", label: "Discese", symbol: "figure.skiing.downhill")
                StatTile(value: Fmt.height(s.reduce(0) { $0 + $1.vertical }), label: "Dislivello", symbol: "arrow.down.right")
                StatTile(value: Fmt.distance(s.reduce(0) { $0 + $1.runDistance }), label: "Sciati", symbol: "point.topleft.down.to.point.bottomright.curvepath")
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "figure.skiing.downhill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 84, height: 84)
                .iconBox()
            Text("Ancora nessuna giornata").font(.title3.weight(.heavy)).foregroundStyle(Theme.text)
            Text("Registra una giornata con il pulsante tondo qui a destra. Con il + in alto puoi scriverne una a mano o importare un file GPX. Per vedere com'è, in Impostazioni puoi crearne una di prova.")
                .prose().font(.subheadline).foregroundStyle(Theme.sub).multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .card()
    }
}

/// One day in the list: the date, the place, and how much was skied.
struct DayCard: View {
    let day: DaySummary

    private static let month: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM")
        return f
    }()

    var body: some View {
        VStack(spacing: 12) {
            row
            if let legs = day.shape, legs.count > 1 {
                DayProfile(legs: legs, lineWidth: 2)
                    .frame(height: 34)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .card()
        .contentShape(Rectangle())
    }

    private var row: some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: day.start))").font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(Theme.text)
                Text(Self.month.string(from: day.start).replacingOccurrences(of: ".", with: "")).font(.footnote).foregroundStyle(Theme.sub)
            }
            .frame(width: 42)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(Fmt.day(day.start)))
            VStack(alignment: .leading, spacing: 4) {
                Text(day.title ?? String(localized: "Giornata sulla neve"))
                    .font(.headline).foregroundStyle(Theme.text).lineLimit(1)
                HStack(spacing: 6) {
                    Image(systemName: (day.sport ?? .ski).symbol).font(.caption.weight(.semibold))
                        .accessibilityLabel(Text(LocalizedStringKey((day.sport ?? .ski).label)))
                    Text("\(day.stats.runs) discese · \(Fmt.height(day.stats.vertical))").font(.subheadline).lineLimit(1).minimumScaleFactor(0.8)
                    if day.manual == true {
                        Image(systemName: "square.and.pencil").font(.caption2)
                            .accessibilityLabel(Text("Scritta a mano"))
                    }
                }
                .foregroundStyle(Theme.sub)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.subheadline.weight(.bold)).foregroundStyle(Theme.sub)
        }
    }
}
