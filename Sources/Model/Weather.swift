import Foundation

/// The weather of a day at the resort, from Open-Meteo: free, with no key and no account. The
/// place is sent rounded to about a hundred meters.
enum Weather {
    static func fetch(for day: SkiDay) async throws -> DayWeather {
        guard let top = day.points.max(by: { $0.alt < $1.alt }) else { throw URLError(.badURL) }
        let format = DateFormatter()
        format.calendar = Calendar(identifier: .gregorian)
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "GMT")
        format.dateFormat = "yyyy-MM-dd"
        // The forecast service keeps about three months; before that, the archive.
        let old = Date().timeIntervalSince(day.end) > 80 * 86_400
        var parts = URLComponents(string: old ? "https://archive-api.open-meteo.com/v1/archive" : "https://api.open-meteo.com/v1/forecast")!
        parts.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", top.lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", top.lon)),
            URLQueryItem(name: "elevation", value: String(format: "%.0f", (day.stats.topAlt + day.stats.lowAlt) / 2)),
            URLQueryItem(name: "hourly", value: "temperature_2m,snowfall,wind_speed_10m,weather_code"),
            URLQueryItem(name: "start_date", value: format.string(from: day.start.addingTimeInterval(-86_400))),
            URLQueryItem(name: "end_date", value: format.string(from: day.end)),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: "GMT"),
        ]
        guard let url = parts.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("SkiApex iOS app", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try parse(data, start: day.start, end: day.end)
    }

    /// The hours of the day out of the hourly answer.
    static func parse(_ data: Data, start: Date, end: Date) throws -> DayWeather {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hourly = root["hourly"] as? [String: Any],
              let times = hourly["time"] as? [Double] else { throw URLError(.cannotParseResponse) }
        func values(_ key: String) -> [Double?] {
            (hourly[key] as? [Any] ?? []).map { ($0 as? NSNumber)?.doubleValue }
        }
        let temps = values("temperature_2m"), snow = values("snowfall"), wind = values("wind_speed_10m"), codes = values("weather_code")
        let from = start.timeIntervalSince1970 - 3600, to = end.timeIntervalSince1970
        var tempMin = Double.infinity, tempMax = -Double.infinity, windMax = 0.0, snowfall = 0.0
        var sky: [Int: Int] = [:]
        for (i, t) in times.enumerated() {
            if t > to - 86_400, t <= to, i < snow.count, let s = snow[i] { snowfall += s }
            guard t >= from, t <= to else { continue }
            if i < temps.count, let v = temps[i] {
                tempMin = min(tempMin, v)
                tempMax = max(tempMax, v)
            }
            if i < wind.count, let v = wind[i] { windMax = max(windMax, v) }
            if i < codes.count, let v = codes[i] { sky[Int(v), default: 0] += 1 }
        }
        guard tempMin.isFinite, tempMax.isFinite else { throw URLError(.cannotParseResponse) }
        // Between two skies as frequent, the worse one.
        let code = sky.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key ?? 3
        return DayWeather(tempMin: tempMin, tempMax: tempMax, snowfall: snowfall, windMax: windMax, code: code)
    }
}
