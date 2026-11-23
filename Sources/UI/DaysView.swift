import MapKit
import SwiftUI
import UniformTypeIdentifiers

/// The diary: the map of the places skied, the totals of always, the trips to come and the days
/// saved, season by season.
struct DaysView: View {
    @Environment(Library.self) private var library
    @State private var season: Season?
    @State private var path: [UUID] = []
    @State private var importing = false
    @State private var writing = Demo.screen == "manual"
    @State private var trip: Trip?
    @State private var newTrip: Trip?
    @State private var error: String?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 14) {
                    ErrorBanner(error: $error)
                    if !pins.isEmpty { places }
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

    // MARK: The map of the places

    /// One pin for each place: the days less than about five kilometers apart share one.
    private struct Pin: Identifiable {
        let id: String
        let name: String
        let coordinate: CLLocationCoordinate2D
        let days: Int
    }

    private var pins: [Pin] {
        var cells: [String: (name: String, coordinate: CLLocationCoordinate2D, days: Int)] = [:]
        // Oldest first, so that the name and the place of the newest day stay.
        for day in library.days.reversed() {
            guard let coordinate = day.coordinate else { continue }
            let key = "\((coordinate.latitude * 20).rounded()),\((coordinate.longitude * 20).rounded())"
            cells[key] = (day.title ?? cells[key]?.name ?? "", coordinate, (cells[key]?.days ?? 0) + 1)
        }
        return cells.map { Pin(id: $0.key, name: $0.value.name, coordinate: $0.value.coordinate, days: $0.value.days) }
            .sorted { $0.id < $1.id }
    }

    private var places: some View {
        Map(initialPosition: .automatic, interactionModes: [.pan, .zoom]) {
            ForEach(pins) { pin in
                Marker(pin.name, monogram: Text("\(pin.days)"), coordinate: pin.coordinate).tint(Theme.accent)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .frame(height: 190)
        .clipShape(Theme.round)
        .overlay(Theme.round.strokeBorder(Theme.line, lineWidth: 1))
        .accessibilityLabel(Text("Mappa dei posti dove hai sciato"))
    }

    private var lifetime: some View {
        let s = library.days.map(\.stats)
        return HStack(spacing: 0) {
            lifetimeFigure("\(Set(library.days.map { Calendar.current.startOfDay(for: $0.start) }).count)", "giorni registrati", "calendar")
            lifetimeFigure(Fmt.height(s.reduce(0) { $0 + $1.vertical }), "dislivello", "arrow.down")
            lifetimeFigure("\(pins.count)", "posti", "mappin.and.ellipse")
        }
        .padding(16)
        .card()
    }

    private func lifetimeFigure(_ value: String, _ label: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.display(.title3)).monospacedDigit().foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.6)
            Label(LocalizedStringKey(label), systemImage: symbol).font(.caption2).foregroundStyle(Theme.sub).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: The trips to come

    @ViewBuilder private var upcoming: some View {
        let trips = library.upcomingTrips
        VStack(alignment: .leading, spacing: 12) {
            Text("PROSSIMAMENTE").font(.caption.weight(.bold)).foregroundStyle(Theme.sub)
            ForEach(trips) { item in
                Button { trip = item } label: { TripCard(trip: item) }
                    .buttonStyle(PressStyle())
            }
            if trips.isEmpty {
                Button { newTrip = blankTrip } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus").font(.footnote.weight(.bold)).foregroundStyle(Theme.accent)
                            .frame(width: 34, height: 34)
                            .iconBox()
                        Text("Aggiungi il tuo prossimo viaggio").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                        Spacer()
                    }
                    .padding(16)
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
                        Text(s.label).font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .foregroundStyle(on ? Theme.onAccent : Theme.text)
                            .background(on ? Theme.accent : Theme.input, in: Capsule())
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
            Text("STAGIONE \(label)").font(.caption.weight(.bold)).foregroundStyle(Theme.sub)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
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
            Text("Ancora nessuna giornata").font(.display(.headline)).foregroundStyle(Theme.text)
            Text("Registra una giornata dalla scheda Registra. Con il + in alto puoi scriverne una a mano o importare un file GPX. Per vedere com'è, in Impostazioni puoi crearne una di prova.")
                .prose().font(.subheadline).foregroundStyle(Theme.sub).multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .card()
    }
}

/// One day in the list.
struct DayCard: View {
    let day: DaySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(day.title ?? String(localized: "Giornata sulla neve"))
                        .font(.display(.headline)).foregroundStyle(Theme.text).lineLimit(1)
                    HStack(spacing: 6) {
                        Image(systemName: (day.sport ?? .ski).symbol).font(.caption2).foregroundStyle(Theme.accent)
                            .accessibilityLabel(Text(LocalizedStringKey((day.sport ?? .ski).label)))
                        Text(Fmt.day(day.start).capitalized).font(.caption).foregroundStyle(Theme.sub)
                        if day.manual == true {
                            Image(systemName: "square.and.pencil").font(.caption2).foregroundStyle(Theme.sub)
                                .accessibilityLabel(Text("Scritta a mano"))
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.sub)
            }
            HStack(spacing: 0) {
                figure("\(day.stats.runs)", "discese")
                figure(Fmt.height(day.stats.vertical), "dislivello")
                figure(day.stats.maxSpeed > 0 ? Fmt.speedValue(day.stats.maxSpeed) : "–", "max \(Fmt.speedUnit)")
                figure(Fmt.distance(day.stats.runDistance), "sciati")
            }
        }
        .padding(16)
        .card()
        .contentShape(Rectangle())
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.accent)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(LocalizedStringKey(label)).font(.caption2).foregroundStyle(Theme.sub).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
