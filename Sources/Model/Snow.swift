import Foundation

/// How the snow was, as you say at the end of a day: kept with the day, and, if you choose, told
/// to who skis there.
enum Snow: String, CaseIterable, Codable, Identifiable {
    case powder, groomed, hard, icy, crust, wet, wind

    var id: String { rawValue }

    var label: String {
        switch self {
        case .powder: "Farinosa"
        case .groomed: "Battuta"
        case .hard: "Dura"
        case .icy: "Ghiacciata"
        case .crust: "Crostosa"
        case .wet: "Bagnata"
        case .wind: "Ventata"
        }
    }

    /// A few words to tell one from the other.
    var hint: String {
        switch self {
        case .powder: "Fresca e leggera"
        case .groomed: "Compatta, ben tirata"
        case .hard: "Compatta e veloce"
        case .icy: "Lastre di ghiaccio"
        case .crust: "Crosta che cede"
        case .wet: "Pesante, primaverile"
        case .wind: "Lavorata dal vento"
        }
    }

    var symbol: String {
        switch self {
        case .powder: "snowflake"
        case .groomed: "line.3.horizontal"
        case .hard: "square.fill"
        case .icy: "diamond.fill"
        case .crust: "square.split.diagonal"
        case .wet: "drop.fill"
        case .wind: "wind"
        }
    }
}

/// What the server knows of a ski area, from who skied there and chose to tell.
struct PlaceInfo: Decodable, Equatable {
    struct Count: Decodable, Equatable, Identifiable {
        let kind: String
        let count: Int
        var id: String { kind }
        var snow: Snow? { Snow(rawValue: kind) }
    }

    struct Latest: Decodable, Equatable {
        let kind: String
        /// yyyy-MM-dd.
        let date: String
        var snow: Snow? { Snow(rawValue: kind) }
    }

    /// The average day of who skied there.
    struct Averages: Decodable, Equatable {
        let days: Int
        let vertical: Double
        let distance: Double
        let runTime: Double
        let liftTime: Double
        let avgSpeed: Double
        let runs: Double
    }

    /// A friend who said they were there.
    struct Visitor: Decodable, Equatable, Identifiable {
        let id: String
        let name: String
        let photo: Double?
        let days: Int
        let last: String
    }

    /// How the snow was in the last days: the kinds told, the most told first.
    let snow: [Count]
    let latest: Latest?
    let reports: Int
    let averages: Averages?
    let friends: [Visitor]
    /// How many of your own days are told there.
    let mine: Int

    static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

/// The snow and the sky of a ski area today, hour by hour, and the snow of the last week: from
/// Open-Meteo, like the forecast.
struct SnowNow: Equatable {
    /// A stretch of the day: the night before, the morning, midday, the afternoon.
    struct Block: Equatable, Identifiable {
        /// The hours it goes from and to, on the clock of the place: 16 to 6, 6 to 10...
        let from: Int
        let to: Int
        /// Centimeters of snow fallen in it.
        let snow: Double
        let tempMin: Double
        let tempMax: Double
        /// km/h, the strongest gust.
        let gust: Double
        let code: Int

        var id: Int { from }
        var label: String { "\(from)–\(to)" }
        var symbol: String { DayWeather(tempMin: tempMin, tempMax: tempMax, snowfall: snow, windMax: gust, code: code).symbol }
        var windy: Bool { gust >= 40 }
    }

    /// Centimeters fallen from yesterday afternoon to this morning, and during today.
    var overnight = 0.0
    var daytime = 0.0
    /// Centimeters fallen in the seven days before today.
    var lastWeek = 0.0
    /// km/h, the strongest gust of today.
    var gustMax = 0.0
    var blocks: [Block] = []

    var today: Double { overnight + daytime }

    static func fetch(lat: Double, lon: Double) async throws -> SnowNow {
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        parts.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", lon)),
            URLQueryItem(name: "hourly", value: "snowfall,temperature_2m,wind_gusts_10m,weather_code"),
            URLQueryItem(name: "past_days", value: "7"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = parts.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("SkiApex iOS app", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try parse(data)
    }

    /// The hours of the answer are the last eight days, today the last of them, on the clock of
    /// the place (the times with the offset read as its hours).
    static func parse(_ data: Data) throws -> SnowNow {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hourly = root["hourly"] as? [String: Any],
              let times = hourly["time"] as? [Any], !times.isEmpty else { throw URLError(.cannotParseResponse) }
        let offset = (root["utc_offset_seconds"] as? NSNumber)?.doubleValue ?? 0
        func values(_ key: String) -> [Double?] {
            (hourly[key] as? [Any] ?? []).map { ($0 as? NSNumber)?.doubleValue }
        }
        let snow = values("snowfall"), temp = values("temperature_2m"), gust = values("wind_gusts_10m"), code = values("weather_code")
        // Each hour as hours since the midnight today began with: below 0, the days before.
        let local = times.map { (($0 as? NSNumber)?.doubleValue ?? 0) + offset }
        guard let last = local.last else { throw URLError(.cannotParseResponse) }
        let midnight = (last / 86_400).rounded(.down) * 86_400
        let hours = local.map { Int((($0 - midnight) / 3600).rounded()) }
        func at(_ list: [Double?], _ i: Int) -> Double? { i < list.count ? list[i] : nil }
        func inside(_ range: Range<Int>) -> [Int] { hours.indices.filter { range.contains(hours[$0]) } }
        func sum(_ range: Range<Int>) -> Double {
            var total = 0.0
            for i in inside(range) { total += at(snow, i) ?? 0 }
            return total
        }
        func block(_ range: Range<Int>, from: Int, to: Int) -> Block? {
            let inside = inside(range)
            let temps = inside.compactMap { at(temp, $0) }
            guard let low = temps.min(), let high = temps.max() else { return nil }
            let gusts = inside.compactMap { at(gust, $0) }
            // The sky met most often in the stretch.
            var seen: [Int: Int] = [:]
            for i in inside { if let c = at(code, i) { seen[Int(c), default: 0] += 1 } }
            let sky = seen.max { $0.value < $1.value }?.key ?? 3
            return Block(from: from, to: to, snow: sum(range), tempMin: low, tempMax: high, gust: gusts.max() ?? 0, code: sky)
        }
        var now = SnowNow()
        now.overnight = sum(-8..<6)
        now.daytime = sum(6..<17)
        now.lastWeek = sum(-168..<0)
        now.gustMax = inside(0..<24).compactMap { at(gust, $0) }.max() ?? 0
        now.blocks = [block(-8..<6, from: 16, to: 6), block(6..<10, from: 6, to: 10), block(10..<13, from: 10, to: 13),
                      block(13..<17, from: 13, to: 16)].compactMap { $0 }
        return now
    }
}
