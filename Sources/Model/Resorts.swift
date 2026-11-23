import Foundation
import Observation

/// The ski areas of the guide: found by name (Photon, the search of OpenStreetMap) or around a
/// place (Overpass), with the snow expected in the next days (Open-Meteo). No key, no account.
enum Resorts {
    // MARK: By name

    static func search(_ text: String) async throws -> [Resort] {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard words.count >= 2 else { return [] }
        // The ski areas first; then the towns, since many resorts are known by the name of theirs.
        var found = try await photon(words, tag: "landuse:winter_sports")
        if found.count < 5, let towns = try? await photon(words, tag: "place") {
            for town in towns where !found.contains(where: { $0.name == town.name && Geo.distance(lat1: $0.lat, lon1: $0.lon, lat2: town.lat, lon2: town.lon) < 20_000 }) {
                found.append(town)
            }
        }
        return found
    }

    private static func photon(_ words: String, tag: String) async throws -> [Resort] {
        var parts = URLComponents(string: "https://photon.komoot.io/api/")!
        parts.queryItems = [
            URLQueryItem(name: "q", value: words),
            URLQueryItem(name: "osm_tag", value: tag),
            URLQueryItem(name: "limit", value: "15"),
        ]
        guard let url = parts.url else { throw URLError(.badURL) }
        return try parsePhoton(try await get(url))
    }

    static func parsePhoton(_ data: Data) throws -> [Resort] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = root["features"] as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
        var out: [Resort] = []
        for feature in features {
            guard let properties = feature["properties"] as? [String: Any],
                  let name = properties["name"] as? String, !name.isEmpty,
                  let geometry = feature["geometry"] as? [String: Any],
                  let coordinates = geometry["coordinates"] as? [Double], coordinates.count >= 2 else { continue }
            let kind = properties["osm_type"] as? String ?? "?"
            let number = (properties["osm_id"] as? NSNumber)?.stringValue ?? "\(coordinates[1]),\(coordinates[0])"
            let region = [properties["state"] as? String, properties["country"] as? String].compactMap { $0 }.joined(separator: ", ")
            let resort = Resort(id: "\(kind)\(number)", name: name, region: region.isEmpty ? nil : region,
                                lat: coordinates[1], lon: coordinates[0])
            if !out.contains(where: { $0.id == resort.id }) { out.append(resort) }
        }
        return out
    }

    // MARK: Around a place

    static func near(lat: Double, lon: Double, radius: Double = 100_000) async throws -> [Resort] {
        let around = String(format: "around:%.0f,%.4f,%.4f", radius, lat, lon)
        let query = """
        [out:json][timeout:30];
        (nwr["landuse"="winter_sports"]["name"](\(around));relation["site"="piste"]["name"](\(around)););
        out tags center 120;
        """
        return try parseOverpass(try await Pistes.ask(query), lat: lat, lon: lon)
    }

    /// The ski areas of an Overpass answer, nearest first, each name once.
    static func parseOverpass(_ data: Data, lat: Double, lon: Double) throws -> [Resort] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = root["elements"] as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
        var out: [Resort] = []
        for element in elements {
            guard let tags = element["tags"] as? [String: String], let name = tags["name"], !name.isEmpty else { continue }
            let center = element["center"] as? [String: Any]
            guard let la = (center?["lat"] ?? element["lat"]) as? Double,
                  let lo = (center?["lon"] ?? element["lon"]) as? Double else { continue }
            let kind = element["type"] as? String ?? "?"
            let number = (element["id"] as? NSNumber)?.stringValue ?? "\(la),\(lo)"
            if !out.contains(where: { $0.name == name }) {
                out.append(Resort(id: "\(kind.prefix(1).uppercased())\(number)", name: name, region: nil, lat: la, lon: lo))
            }
        }
        return out.sorted {
            Geo.distance(lat1: lat, lon1: lon, lat2: $0.lat, lon2: $0.lon) < Geo.distance(lat1: lat, lon1: lon, lat2: $1.lat, lon2: $1.lon)
        }
    }

    // MARK: The snow to come

    static func forecast(lat: Double, lon: Double) async throws -> [ForecastDay] {
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        parts.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", lon)),
            URLQueryItem(name: "daily", value: "snowfall_sum,temperature_2m_min,temperature_2m_max,wind_speed_10m_max,weather_code"),
            URLQueryItem(name: "forecast_days", value: "8"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = parts.url else { throw URLError(.badURL) }
        return try parseForecast(try await get(url))
    }

    static func parseForecast(_ data: Data) throws -> [ForecastDay] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let daily = root["daily"] as? [String: Any],
              let times = daily["time"] as? [Double] else { throw URLError(.cannotParseResponse) }
        // The times are midnights at the resort told in GMT: with the offset they read as its date.
        let offset = (root["utc_offset_seconds"] as? NSNumber)?.doubleValue ?? 0
        func values(_ key: String) -> [Double?] {
            (daily[key] as? [Any] ?? []).map { ($0 as? NSNumber)?.doubleValue }
        }
        let snow = values("snowfall_sum"), low = values("temperature_2m_min"), high = values("temperature_2m_max")
        let wind = values("wind_speed_10m_max"), codes = values("weather_code")
        func at(_ list: [Double?], _ i: Int) -> Double { i < list.count ? list[i] ?? 0 : 0 }
        return times.enumerated().map { i, t in
            ForecastDay(date: Date(timeIntervalSince1970: t + offset), snow: at(snow, i), tempMin: at(low, i), tempMax: at(high, i),
                        wind: at(wind, i), code: Int(at(codes, i)))
        }
    }

    private static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("SkiApex iOS app", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}

/// What the guide has asked the internet so far: the forecasts, kept for an hour, and the ski
/// areas around. One for the whole app, so that a card and its page do not ask twice.
@Observable final class Guide {
    private(set) var forecasts: [String: [ForecastDay]] = [:]
    private(set) var nearby: [Resort] = []
    private(set) var loadingNearby = false
    /// The ski areas around were asked for, whatever came back.
    private(set) var askedNearby = false
    @ObservationIgnored private var asked: [String: Date] = [:]

    /// For the pictures of the README: made-up snow, no internet.
    init(demo: [Resort] = []) {
        guard !demo.isEmpty else { return }
        nearby = demo
        askedNearby = true
        let midnight = Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(TimeZone.current.secondsFromGMT()))
        for (k, resort) in demo.enumerated() {
            let snow: [Double] = k % 2 == 0 ? [0, 2, 14, 22, 6, 0, 0, 3] : [1, 0, 0, 5, 18, 9, 0, 0]
            forecasts[resort.id] = snow.enumerated().map { i, cm in
                ForecastDay(date: midnight.addingTimeInterval(Double(i) * 86_400), snow: cm, tempMin: -9 + Double(i % 3),
                            tempMax: -2 + Double(i % 4), wind: i == 3 ? 55 : 15, code: cm > 0 ? 73 : (i % 2 == 0 ? 0 : 2))
            }
            asked[resort.id] = Date()
        }
    }

    @MainActor func load(_ resort: Resort) async {
        if let when = asked[resort.id], Date().timeIntervalSince(when) < 3600 { return }
        asked[resort.id] = Date()
        if let days = try? await Resorts.forecast(lat: resort.lat, lon: resort.lon) {
            forecasts[resort.id] = days
        } else {
            // To be asked again at the next look.
            asked[resort.id] = nil
        }
    }

    @MainActor func loadNearby(lat: Double, lon: Double) async {
        guard !loadingNearby, !askedNearby else { return }
        loadingNearby = true
        defer { loadingNearby = false }
        if let found = try? await Resorts.near(lat: lat, lon: lon) {
            nearby = found
            askedNearby = true
        }
    }
}
