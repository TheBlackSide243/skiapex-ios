import MapKit
import SwiftUI

/// The guide: the ski areas you keep, the ones around you and the ones found by name, each with
/// the snow expected in the next days.
struct GuideView: View {
    @Environment(Library.self) private var library
    @Environment(Recorder.self) private var recorder
    @Environment(Guide.self) private var guide
    /// The ski areas around, or the ones kept.
    @State private var around = Demo.isOn
    @State private var words = ""
    @State private var found: [Resort] = []
    @State private var searching = false
    @State private var noResults = false
    @State private var exploring = Demo.screen == "explore"
    @State private var showingResort = Demo.screen == "resort"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    searchField
                    if !words.trimmingCharacters(in: .whitespaces).isEmpty {
                        results
                    } else {
                        if let center { exploreCard(center) }
                        Picker("Elenco", selection: $around) {
                            Text("Preferite").tag(false)
                            Text("Vicine").tag(true)
                        }
                        .pickerStyle(.segmented)
                        if around { nearby } else { favorites }
                    }
                    Text("Stazioni: © i contributori di OpenStreetMap. Previsioni: Open-Meteo.com.")
                        .prose().font(.caption2).foregroundStyle(Theme.sub)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
            .screen()
            .navigationTitle("Guida")
            .navigationDestination(for: Resort.self) { ResortDetailView(resort: $0) }
            .navigationDestination(for: UUID.self) { DayDetailView(id: $0) }
            .navigationDestination(isPresented: $exploring) {
                // For the pictures: a made-up ski area.
                ExploreView(name: Demo.resorts[0].name, center: Demo.resorts[0].coordinate)
            }
            .navigationDestination(isPresented: $showingResort) { ResortDetailView(resort: Demo.resorts[0]) }
            .task(id: around) {
                guard around, !Demo.isOn, let center else { return }
                await guide.loadNearby(lat: center.latitude, lon: center.longitude)
            }
        }
    }

    /// Where "around" is: the iPhone, or the last day recorded.
    private var center: CLLocationCoordinate2D? {
        recorder.here?.coordinate ?? library.days.compactMap(\.coordinate).first
    }

    /// The pistes and the lifts around you, on a map.
    private func exploreCard(_ center: CLLocationCoordinate2D) -> some View {
        NavigationLink {
            ExploreView(name: String(localized: "Intorno a te"), center: center)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "map.fill").font(.body.weight(.semibold)).foregroundStyle(Theme.accent)
                    .frame(width: 42, height: 42)
                    .iconBox()
                VStack(alignment: .leading, spacing: 3) {
                    Text("Esplora la zona").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    Text("Piste, impianti e rifugi intorno a te, e il percorso da un punto all'altro.")
                        .prose().font(.caption).foregroundStyle(Theme.sub)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.sub)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
        .buttonStyle(PressStyle())
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.sub)
            TextField("Cerca una stazione o un paese", text: $words)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await search() } }
            if searching {
                ProgressView().controlSize(.small)
            } else if !words.isEmpty {
                Button {
                    words = ""
                    found = []
                    noResults = false
                } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.sub) }
                    .accessibilityLabel(Text("Cancella"))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Theme.deep, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
    }

    private func search() async {
        searching = true
        defer { searching = false }
        noResults = false
        if let list = try? await Resorts.search(words) {
            found = list
            noResults = list.isEmpty
        } else {
            found = []
            noResults = true
        }
    }

    @ViewBuilder private var results: some View {
        if found.isEmpty {
            hint(noResults ? "Non ho trovato niente con questo nome. Controlla la connessione o prova con il nome del paese."
                 : "Scrivi il nome e premi Cerca sulla tastiera.")
        } else {
            list(found)
        }
    }

    @ViewBuilder private var favorites: some View {
        if library.favorites.isEmpty {
            hint("Qui trovi le stazioni che segui. Cercane una per nome o guarda quelle vicine, poi tocca la stella.")
        } else {
            list(library.favorites)
        }
    }

    @ViewBuilder private var nearby: some View {
        if !guide.nearby.isEmpty {
            list(guide.nearby)
        } else if guide.loadingNearby {
            ProgressView().padding(30)
        } else if center == nil {
            hint("Per vedere le stazioni vicine serve sapere dove sei: permetti la posizione dalla scheda Registra, o registra una giornata.")
        } else {
            hint(guide.askedNearby ? "Non ho trovato stazioni nel raggio di 100 km."
                 : "Non sono riuscito a chiedere le stazioni vicine. Controlla la connessione e riapri la scheda.")
        }
    }

    private func list(_ resorts: [Resort]) -> some View {
        LazyVStack(spacing: 14) {
            ForEach(resorts.prefix(40)) { resort in
                NavigationLink(value: resort) { ResortCard(resort: resort, from: center) }
                    .buttonStyle(PressStyle())
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(LocalizedStringKey(text))
            .prose().font(.subheadline).foregroundStyle(Theme.sub).multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity)
            .card()
    }
}

/// One ski area in a list: its name, how far it is, and the snow of the next days.
struct ResortCard: View {
    let resort: Resort
    var from: CLLocationCoordinate2D?
    @Environment(Guide.self) private var guide
    @Environment(Library.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if library.isFavorite(resort) {
                            Image(systemName: "star.fill").font(.caption).foregroundStyle(Theme.warn)
                                .accessibilityLabel(Text("Tra le preferite"))
                        }
                        Text(resort.name).font(.display(.headline)).foregroundStyle(Theme.text).lineLimit(1)
                    }
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.sub)
            }
            if let days = guide.forecasts[resort.id] {
                SnowBars(days: days)
            } else {
                ProgressView().frame(maxWidth: .infinity).frame(height: 70)
            }
        }
        .padding(16)
        .card()
        .contentShape(Rectangle())
        .task(id: resort.id) { await guide.load(resort) }
    }

    /// The region, and how far from here.
    private var detail: String? {
        var parts: [String] = []
        if let region = resort.region { parts.append(region) }
        if let from {
            parts.append(Fmt.distance(Geo.distance(lat1: from.latitude, lon1: from.longitude, lat2: resort.lat, lon2: resort.lon)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// The snow expected day by day: a bar for each day with its centimeters on top, and the wind
/// under the days it blows hard.
struct SnowBars: View {
    let days: [ForecastDay]

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "GMT")
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f
    }()

    var body: some View {
        let top = max(10, days.map(\.snow).max() ?? 0)
        let metric = Units.current == .metric
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(days) { day in
                VStack(spacing: 4) {
                    Text(day.snow >= 0.5 ? (metric ? "\(Int(day.snow.rounded()))" : (day.snow / 2.54).formatted(.number.precision(.fractionLength(0...1)))) : "–")
                        .font(.caption2.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(day.snow >= 0.5 ? Theme.text : Theme.sub.opacity(0.6))
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.deep)
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.accent)
                            .frame(height: max(day.snow >= 0.5 ? 3 : 0, 44 * min(1, day.snow / top)))
                    }
                    .frame(height: 44)
                    Text(Self.weekday.string(from: day.date).lowercased()).font(.caption2).foregroundStyle(Theme.sub).lineLimit(1)
                    Image(systemName: "wind").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(day.windy ? Theme.warn : .clear)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Neve prevista nei prossimi giorni: \(Fmt.snow(days.reduce(0) { $0 + $1.snow })) in tutto"))
    }
}

/// One ski area: where it is, the forecast day by day, your days there.
struct ResortDetailView: View {
    let resort: Resort
    @Environment(Library.self) private var library
    @Environment(Guide.self) private var guide
    @AppStorage(Prefs.mapLook) private var mapLook = MapLook.standard.rawValue
    @State private var planning: Trip?
    /// The pistes and the lifts, for the numbers and to download them; the snow of today.
    @State private var terrain: Terrain?
    @State private var now: SnowNow?

    private var look: MapLook { MapLook(rawValue: mapLook) ?? .standard }

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "GMT")
        f.setLocalizedDateFormatFromTemplate("EEEEdMMM")
        return f
    }()

    var body: some View {
        let favorite = library.isFavorite(resort)
        let mine = library.days(near: resort)
        ScrollView {
            VStack(spacing: 14) {
                Map(initialPosition: .region(MKCoordinateRegion(center: resort.coordinate, latitudinalMeters: 9000, longitudinalMeters: 9000))) {
                    Marker(resort.name, systemImage: "mountain.2.fill", coordinate: resort.coordinate).tint(Theme.accent)
                }
                .mapStyle(look.style)
                .frame(height: 240)
                .clipShape(Theme.round)
                .overlay(Theme.round.strokeBorder(Theme.line, lineWidth: 1))

                VStack(alignment: .leading, spacing: 4) {
                    Text(resort.name).font(.display(.title3)).foregroundStyle(Theme.text)
                    if let region = resort.region {
                        Text(region).font(.caption).foregroundStyle(Theme.sub)
                    }
                    if let terrain, !terrain.ways.isEmpty {
                        ResortFacts(terrain: terrain).padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    Button { library.toggleFavorite(resort) } label: {
                        Label(LocalizedStringKey(favorite ? "Seguita" : "Segui"), systemImage: favorite ? "star.fill" : "star")
                    }
                    .buttonStyle(SecondaryButtonStyle(color: favorite ? Theme.warn : Theme.text))
                    .sensoryFeedback(.selection, trigger: favorite)
                    Button {
                        let start = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: Date())) ?? Date()
                        planning = Trip(name: resort.name, start: start, end: start.addingTimeInterval(2 * 86_400), resort: resort)
                    } label: { Label("Viaggio", systemImage: "calendar.badge.plus") }
                        .buttonStyle(SecondaryButtonStyle())
                }
                ResortMapButtons(resort: resort, terrain: terrain)
                if let now { TodayPanel(now: now) }

                if let days = guide.forecasts[resort.id] {
                    StatGrid {
                        StatTile(value: Fmt.snow(days.prefix(3).reduce(0) { $0 + $1.snow }), label: "Neve in 3 giorni", symbol: "snowflake")
                        StatTile(value: Fmt.snow(days.reduce(0) { $0 + $1.snow }), label: "Neve in 8 giorni", symbol: "cloud.snow")
                    }
                    Panel("Previsioni") {
                        SnowBars(days: days)
                        ForEach(days) { day in
                            Divider().overlay(Theme.line)
                            HStack(spacing: 10) {
                                Image(systemName: day.symbol).font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent).frame(width: 24)
                                Text(Self.day.string(from: day.date).capitalized).font(.subheadline).foregroundStyle(Theme.text).lineLimit(1)
                                Spacer(minLength: 6)
                                if day.windy {
                                    Label(Fmt.wind(day.wind), systemImage: "wind").font(.caption2).foregroundStyle(Theme.warn)
                                }
                                Text("\(Fmt.temperature(day.tempMin)) / \(Fmt.temperature(day.tempMax))").font(.caption).monospacedDigit().foregroundStyle(Theme.sub)
                                Text(day.snow >= 0.5 ? Fmt.snow(day.snow) : "–").font(.subheadline.weight(.semibold)).monospacedDigit()
                                    .foregroundStyle(day.snow >= 0.5 ? Theme.accent : Theme.sub)
                                    .frame(minWidth: 52, alignment: .trailing)
                            }
                        }
                    }
                } else {
                    ProgressView().padding(30)
                }

                CommunityPanel(lat: resort.lat, lon: resort.lon)

                if !mine.isEmpty {
                    Panel("Le tue giornate qui") {
                        ForEach(mine.prefix(10)) { day in
                            NavigationLink(value: day.id) {
                                HStack {
                                    Text(Fmt.dayShort(day.start)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                                    Spacer()
                                    Text("\(day.stats.runs) · \(Fmt.height(day.stats.vertical))").font(.caption).foregroundStyle(Theme.sub)
                                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.sub)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                }

                Button {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: resort.coordinate))
                    item.name = resort.name
                    item.openInMaps()
                } label: { Label("Apri in Mappe", systemImage: "map") }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(16)
        }
        .screen()
        .navigationTitle(resort.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await guide.load(resort) }
        .task {
            if Demo.isOn {
                terrain = Terrain.demo(lat: resort.lat, lon: resort.lon)
                now = SnowNow(overnight: 8, daytime: 1, lastWeek: 40, gustMax: 53, blocks: [
                    .init(from: 16, to: 6, snow: 8, tempMin: -12, tempMax: -6, gust: 30, code: 73),
                    .init(from: 6, to: 10, snow: 1, tempMin: -12, tempMax: -11, gust: 53, code: 3),
                    .init(from: 10, to: 13, snow: 0, tempMin: -12, tempMax: -10, gust: 45, code: 3),
                    .init(from: 13, to: 16, snow: 0, tempMin: -11, tempMax: -9, gust: 35, code: 2),
                ])
                return
            }
            now = try? await SnowNow.fetch(lat: resort.lat, lon: resort.lon)
            terrain = try? await Terrains.shared.terrain(lat: resort.lat, lon: resort.lon)
        }
        .sheet(item: $planning) { TripEditor(trip: $0, isNew: true) }
    }
}
