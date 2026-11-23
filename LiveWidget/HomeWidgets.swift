import AppIntents
import SwiftUI
import WidgetKit

// The widgets for the Home Screen and the Lock Screen. They read nothing of the app: one opens it
// ready to record, the other asks Open-Meteo for the snow expected at a place chosen in the widget.

// MARK: Record

/// Nothing changes over time: one entry, for ever.
struct StillProvider: TimelineProvider {
    struct Entry: TimelineEntry { let date: Date }
    func placeholder(in context: Context) -> Entry { Entry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: Date())], policy: .never))
    }
}

struct RecordWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "skiapex.record", provider: StillProvider()) { _ in
            RecordWidgetView().widgetURL(URL(string: "skiapex://record"))
        }
        .configurationDisplayName("Registra")
        .description("Apre Ski Apex pronto a registrare la giornata.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct RecordWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "figure.skiing.downhill").font(.title2.weight(.semibold))
            }
            .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "figure.skiing.downhill").font(.title2.weight(.semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ski Apex").font(.headline)
                    Text("Registra la giornata").font(.caption)
                }
                Spacer(minLength: 0)
            }
            .containerBackground(for: .widget) { Color.clear }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "figure.skiing.downhill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Ink.bg)
                    .frame(width: 46, height: 46)
                    .background(Ink.accent, in: Circle())
                Spacer(minLength: 0)
                Text("Registra").font(.system(.headline, design: .monospaced)).foregroundStyle(Ink.text)
                Text("Tocca per iniziare la giornata").font(.caption2).foregroundStyle(Ink.sub)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { Ink.bg }
        }
    }
}

// MARK: Snow to come

/// A place to see the snow of: its name and where it is. All of it is in the id, so that a
/// widget set up once needs nothing else to find it again.
struct PlaceEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Località"
    static var defaultQuery = PlaceQuery()

    var id: String
    var name: String
    var region: String
    var lat: Double
    var lon: Double

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(region)")
    }

    init(name: String, region: String, lat: Double, lon: Double) {
        self.name = name
        self.region = region
        self.lat = lat
        self.lon = lon
        id = [String(format: "%.4f", lat), String(format: "%.4f", lon), name, region].joined(separator: "|")
    }

    init?(id: String) {
        let parts = id.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3, let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
        self.id = id
        self.lat = lat
        self.lon = lon
        name = parts[2]
        region = parts.count > 3 ? parts[3] : ""
    }

    /// Offered before anything is typed.
    static let known = [
        PlaceEntity(name: "Breuil-Cervinia", region: "Valle d'Aosta, Italia", lat: 45.9336, lon: 7.6295),
        PlaceEntity(name: "Courmayeur", region: "Valle d'Aosta, Italia", lat: 45.7969, lon: 6.9689),
        PlaceEntity(name: "Sestriere", region: "Piemonte, Italia", lat: 44.9580, lon: 6.8790),
        PlaceEntity(name: "Livigno", region: "Lombardia, Italia", lat: 46.5386, lon: 10.1357),
        PlaceEntity(name: "Bormio", region: "Lombardia, Italia", lat: 46.4670, lon: 10.3700),
        PlaceEntity(name: "Madonna di Campiglio", region: "Trentino, Italia", lat: 46.2296, lon: 10.8266),
        PlaceEntity(name: "Selva di Val Gardena", region: "Alto Adige, Italia", lat: 46.5560, lon: 11.7560),
        PlaceEntity(name: "Cortina d'Ampezzo", region: "Veneto, Italia", lat: 46.5405, lon: 12.1357),
        PlaceEntity(name: "Zermatt", region: "Vallese, Svizzera", lat: 46.0207, lon: 7.7491),
        PlaceEntity(name: "Chamonix", region: "Alta Savoia, Francia", lat: 45.9237, lon: 6.8694),
    ]
}

struct PlaceQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [PlaceEntity] {
        identifiers.compactMap { PlaceEntity(id: $0) }
    }

    func entities(matching string: String) async throws -> [PlaceEntity] {
        try await SnowData.search(string)
    }

    func suggestedEntities() async throws -> [PlaceEntity] {
        PlaceEntity.known
    }
}

struct SnowPlaceIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Neve in arrivo"
    static var description = IntentDescription("Scegli la località di cui vedere la neve prevista.")

    @Parameter(title: "Località")
    var place: PlaceEntity?
}

/// One day of the forecast.
struct SnowDay: Identifiable {
    /// Midnight of the day at the place, to be read in GMT.
    let date: Date
    /// Centimeters.
    let snow: Double
    /// Degrees Celsius.
    let low: Double
    let high: Double
    let code: Int

    var id: Date { date }

    var symbol: String {
        switch code {
        case 0: "sun.max.fill"
        case 1, 2: "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.fill"
        case 51...67, 80...82: "cloud.rain.fill"
        default: "cloud.fill"
        }
    }
}

/// What the snow widget asks the internet: the places by name and the forecast, both from
/// Open-Meteo. No key, no account.
enum SnowData {
    static func search(_ text: String) async throws -> [PlaceEntity] {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard words.count >= 2 else { return PlaceEntity.known }
        var parts = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        parts.queryItems = [
            URLQueryItem(name: "name", value: words),
            URLQueryItem(name: "count", value: "12"),
            URLQueryItem(name: "language", value: Locale.current.language.languageCode?.identifier ?? "it"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = parts.url else { throw URLError(.badURL) }
        return parsePlaces(try await get(url))
    }

    static func parsePlaces(_ data: Data) -> [PlaceEntity] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { place in
            guard let name = place["name"] as? String, !name.isEmpty,
                  let lat = (place["latitude"] as? NSNumber)?.doubleValue,
                  let lon = (place["longitude"] as? NSNumber)?.doubleValue else { return nil }
            let region = [place["admin1"] as? String, place["country"] as? String].compactMap { $0 }.joined(separator: ", ")
            // The separator of the id cannot be in the words.
            return PlaceEntity(name: name.replacingOccurrences(of: "|", with: " "), region: region.replacingOccurrences(of: "|", with: " "),
                               lat: lat, lon: lon)
        }
    }

    static func forecast(lat: Double, lon: Double) async throws -> [SnowDay] {
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        parts.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", lon)),
            URLQueryItem(name: "daily", value: "snowfall_sum,temperature_2m_min,temperature_2m_max,weather_code"),
            URLQueryItem(name: "forecast_days", value: "5"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = parts.url else { throw URLError(.badURL) }
        return try parseForecast(try await get(url))
    }

    static func parseForecast(_ data: Data) throws -> [SnowDay] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let daily = root["daily"] as? [String: Any],
              let times = daily["time"] as? [Any] else { throw URLError(.cannotParseResponse) }
        // The times are midnights at the place told in GMT: with the offset they read as its date.
        let offset = (root["utc_offset_seconds"] as? NSNumber)?.doubleValue ?? 0
        func values(_ key: String) -> [Double?] {
            (daily[key] as? [Any] ?? []).map { ($0 as? NSNumber)?.doubleValue }
        }
        let snow = values("snowfall_sum"), low = values("temperature_2m_min"), high = values("temperature_2m_max")
        let codes = values("weather_code")
        func at(_ list: [Double?], _ i: Int) -> Double { i < list.count ? list[i] ?? 0 : 0 }
        var days: [SnowDay] = []
        for (i, time) in times.enumerated() {
            guard let t = (time as? NSNumber)?.doubleValue else { continue }
            days.append(SnowDay(date: Date(timeIntervalSince1970: t + offset), snow: at(snow, i), low: at(low, i), high: at(high, i),
                                code: Int(at(codes, i))))
        }
        return days
    }

    private static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("SkiApex iOS widget", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}

struct SnowEntry: TimelineEntry {
    let date: Date
    let place: PlaceEntity?
    let days: [SnowDay]
    /// The forecast was asked for and did not come.
    var failed = false

    /// For the gallery of the widgets: a snowy week at a known place.
    static var sample: SnowEntry {
        let midnight = Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(TimeZone.current.secondsFromGMT()))
        let snow: [Double] = [2, 14, 22, 6, 0]
        let days = snow.enumerated().map { i, cm in
            SnowDay(date: midnight.addingTimeInterval(Double(i) * 86_400), snow: cm, low: -9 + Double(i), high: -3 + Double(i),
                    code: cm > 0 ? 73 : 1)
        }
        return SnowEntry(date: Date(), place: PlaceEntity.known[0], days: days)
    }
}

struct SnowProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnowEntry { .sample }

    func snapshot(for configuration: SnowPlaceIntent, in context: Context) async -> SnowEntry {
        if context.isPreview { return .sample }
        return await entry(for: configuration)
    }

    func timeline(for configuration: SnowPlaceIntent, in context: Context) async -> Timeline<SnowEntry> {
        let entry = await entry(for: configuration)
        // Asked again in three hours; sooner when it did not come.
        let next = Date().addingTimeInterval(entry.failed ? 30 * 60 : 3 * 3600)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func entry(for configuration: SnowPlaceIntent) async -> SnowEntry {
        guard let place = configuration.place else { return SnowEntry(date: Date(), place: nil, days: []) }
        if let days = try? await SnowData.forecast(lat: place.lat, lon: place.lon), !days.isEmpty {
            return SnowEntry(date: Date(), place: place, days: days)
        }
        return SnowEntry(date: Date(), place: place, days: [], failed: true)
    }
}

struct SnowWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "skiapex.snow", intent: SnowPlaceIntent.self, provider: SnowProvider()) { entry in
            SnowWidgetView(entry: entry).widgetURL(URL(string: "skiapex://guide"))
        }
        .configurationDisplayName("Neve in arrivo")
        .description("La neve prevista nei prossimi giorni in una località a tua scelta.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

/// Numbers in the units of the iPhone's region: the widget does not read the app's settings.
private enum WidgetUnits {
    static var metric: Bool { Locale.current.measurementSystem != .us }

    static func snow(_ cm: Double) -> String {
        metric ? "\(Int(cm.rounded())) cm" : "\((cm / 2.54).formatted(.number.precision(.fractionLength(0...1)))) in"
    }

    static func snowShort(_ cm: Double) -> String {
        metric ? "\(Int(cm.rounded()))" : (cm / 2.54).formatted(.number.precision(.fractionLength(0...1)))
    }

    static func temperature(_ c: Double) -> String {
        metric ? "\(Int(c.rounded()))°" : "\(Int((c * 9 / 5 + 32).rounded()))°"
    }
}

struct SnowWidgetView: View {
    let entry: SnowEntry
    @Environment(\.widgetFamily) private var family

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "GMT")
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f
    }()

    private var threeDays: Double { entry.days.prefix(3).reduce(0) { $0 + $1.snow } }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            lockScreen.containerBackground(for: .widget) { Color.clear }
        case .systemMedium:
            HStack(alignment: .top, spacing: 14) {
                summary.frame(maxWidth: .infinity, alignment: .leading)
                if !entry.days.isEmpty { bars.frame(maxWidth: .infinity) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(for: .widget) { Ink.bg }
        default:
            summary
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .containerBackground(for: .widget) { Ink.bg }
        }
    }

    /// The place, the snow of the next three days, today's sky and temperatures.
    @ViewBuilder private var summary: some View {
        if let place = entry.place {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "snowflake").font(.caption2.weight(.bold)).foregroundStyle(Ink.accent)
                    Text(place.name).font(.caption.weight(.semibold)).foregroundStyle(Ink.text).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let today = entry.days.first {
                    Text(WidgetUnits.snow(threeDays))
                        .font(.system(.title, design: .monospaced, weight: .semibold))
                        .foregroundStyle(threeDays >= 0.5 ? Ink.accent : Ink.text)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("di neve in 3 giorni").font(.caption2).foregroundStyle(Ink.sub).lineLimit(1)
                    HStack(spacing: 5) {
                        Image(systemName: today.symbol).font(.caption2).foregroundStyle(Ink.sub)
                        Text("\(WidgetUnits.temperature(today.low)) / \(WidgetUnits.temperature(today.high))")
                            .font(.caption2.monospacedDigit()).foregroundStyle(Ink.sub)
                    }
                    .padding(.top, 2)
                } else {
                    Text("Previsioni non disponibili ora").font(.caption).foregroundStyle(Ink.sub)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "snowflake").font(.title3.weight(.semibold)).foregroundStyle(Ink.accent)
                Spacer(minLength: 0)
                Text("Neve in arrivo").font(.system(.headline, design: .monospaced)).foregroundStyle(Ink.text)
                Text("Tieni premuto e scegli una località").font(.caption2).foregroundStyle(Ink.sub).lineLimit(3)
            }
        }
    }

    /// A bar for each day, with its centimeters on top.
    private var bars: some View {
        let top = max(10, entry.days.map(\.snow).max() ?? 0)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(entry.days) { day in
                VStack(spacing: 3) {
                    Text(day.snow >= 0.5 ? WidgetUnits.snowShort(day.snow) : "–")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(day.snow >= 0.5 ? Ink.text : Ink.sub)
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Ink.panel)
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Ink.accent)
                            .frame(height: max(day.snow >= 0.5 ? 3 : 0, 62 * min(1, day.snow / top)))
                    }
                    .frame(height: 62)
                    Text(Self.weekday.string(from: day.date).lowercased()).font(.caption2).foregroundStyle(Ink.sub).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var lockScreen: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let place = entry.place {
                Text(place.name).font(.headline).lineLimit(1)
                if let today = entry.days.first {
                    Label("\(WidgetUnits.snow(threeDays)) in 3 giorni", systemImage: "snowflake").font(.caption)
                    Text("\(WidgetUnits.temperature(today.low)) / \(WidgetUnits.temperature(today.high))").font(.caption)
                } else {
                    Text("Previsioni non disponibili ora").font(.caption)
                }
            } else {
                Text("Neve in arrivo").font(.headline)
                Text("Scegli una località").font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
