import CoreLocation
import Foundation

/// What was on the feet.
enum Sport: String, Codable, CaseIterable, Identifiable {
    case ski, snowboard, telemark, sled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ski: "Sci"
        case .snowboard: "Snowboard"
        case .telemark: "Telemark"
        case .sled: "Slittino"
        }
    }

    var symbol: String {
        switch self {
        case .ski, .telemark: "figure.skiing.downhill"
        case .snowboard: "figure.snowboarding"
        case .sled: "snowflake"
        }
    }

    /// The one chosen in Settings, given to the days as they are saved.
    static var current: Sport {
        Sport(rawValue: UserDefaults.standard.string(forKey: Prefs.sport) ?? "") ?? .ski
    }
}

/// The weather of a day at the resort, from Open-Meteo.
struct DayWeather: Codable, Hashable {
    /// °C, the coldest and the warmest hour of the day on the snow.
    var tempMin: Double
    var tempMax: Double
    /// Centimeters of snow fallen in the 24 hours up to the end of the day.
    var snowfall: Double
    /// km/h, the windiest hour.
    var windMax: Double
    /// The WMO code of the sky for most of the day.
    var code: Int

    var symbol: String {
        switch code {
        case 0: "sun.max"
        case 1, 2: "cloud.sun"
        case 3: "cloud"
        case 45, 48: "cloud.fog"
        case 51...67, 80...82: "cloud.rain"
        case 71...77, 85, 86: "cloud.snow"
        case 95...99: "cloud.bolt"
        default: "cloud"
        }
    }

    var label: String {
        switch code {
        case 0: "Sereno"
        case 1, 2: "Poco nuvoloso"
        case 3: "Coperto"
        case 45, 48: "Nebbia"
        case 51...67, 80...82: "Pioggia"
        case 71...77, 85, 86: "Neve"
        case 95...99: "Temporale"
        default: "Nuvoloso"
        }
    }
}

/// A day on the snow, with all its points.
struct SkiDay: Codable, Identifiable {
    var id: UUID
    var start: Date
    var end: Date
    /// Where it was: the town, from the map, or the name given by hand; nil until it is known.
    var place: String?
    var points: [TrackPoint]
    var segments: [Segment]
    var stats: DayStats
    var sport: Sport?
    /// The ski area, from OpenStreetMap.
    var resort: String?
    var weather: DayWeather?
    /// The pistes and lifts of OpenStreetMap were looked up (whether or not any was found).
    var mapped: Bool?
    /// Saved in Apple Health as a workout.
    var inHealth: Bool?
    /// Beats a minute during the day, from Apple Health: the average and the highest.
    var heartAvg: Double?
    var heartMax: Double?
    /// Written by hand, with no track: its numbers are the ones typed in.
    var manual: Bool?
    /// How the snow was, as you said at the end of the day.
    var snow: Snow?
    /// The day was told to who skis there (see `Social.tell`).
    var told: Bool?

    /// A day made of the points recorded: cleaned up, then cut into runs and lifts.
    init(id: UUID = UUID(), points raw: [TrackPoint], place: String? = nil, sport: Sport? = nil) {
        let points = Segmenter.clean(raw)
        let result = Segmenter.analyze(points)
        self.id = id
        self.points = points
        self.start = points.first?.t ?? Date()
        self.end = points.last?.t ?? Date()
        self.place = place
        self.segments = result.segments
        self.stats = result.stats
        self.sport = sport
    }

    /// A day written by hand: when, where and its numbers, with no track.
    init(manual start: Date, duration: TimeInterval, place: String?, sport: Sport, runs: Int, vertical: Double,
         distance: Double, maxSpeed: Double) {
        id = UUID()
        self.start = start
        end = start.addingTimeInterval(max(0, duration))
        self.place = place
        points = []
        segments = []
        var numbers = DayStats()
        numbers.runs = max(0, runs)
        numbers.vertical = max(0, vertical)
        numbers.runDistance = max(0, distance)
        numbers.totalDistance = max(0, distance)
        numbers.maxSpeed = max(0, maxSpeed)
        numbers.totalTime = max(0, duration)
        stats = numbers
        self.sport = sport
        manual = true
        // Nothing to look for on the map.
        mapped = true
    }

    var runs: [Segment] { segments.filter { $0.kind == .run } }
    /// The name given by hand or the town; the ski area when there is neither.
    var title: String? { place ?? resort }
    var summary: DaySummary {
        let top = points.max { $0.alt < $1.alt }
        return DaySummary(id: id, start: start, end: end, place: place, stats: stats, sport: sport, resort: resort,
                          lat: top?.lat, lon: top?.lon, manual: manual, shape: Leg.of(self), pistes: RunNote.of(self))
    }
}

/// One stretch of a day as its profile draws it: up a lift, down a piste, or a stop. Short names,
/// for it is written many times in the list of the days.
struct Leg: Codable, Hashable {
    /// 0 a run, 1 a lift, 2 a stop.
    var k: Int
    /// How long it took, in seconds.
    var s: Double
    /// The altitude it began and ended at.
    var a: Double
    var b: Double
    /// The difficulty of the piste of a run, when known.
    var d: String?

    /// The stretches of a day, at most a hundred and twenty of them. nil for a day with no track.
    static func of(_ day: SkiDay) -> [Leg]? {
        guard !day.points.isEmpty, !day.segments.isEmpty else { return nil }
        let legs: [Leg] = day.segments.compactMap { seg in
            guard seg.start <= seg.end, seg.end < day.points.count else { return nil }
            let kind = seg.kind == .run ? 0 : seg.kind == .lift ? 1 : 2
            return Leg(k: kind, s: max(1, seg.duration), a: day.points[seg.start].alt, b: day.points[seg.end].alt, d: seg.difficulty)
        }
        return legs.isEmpty ? nil : Array(legs.prefix(120))
    }
}

/// What the list of days shows, without the points: kept all together in one small file.
struct DaySummary: Codable, Identifiable, Hashable {
    var id: UUID
    var start: Date
    var end: Date
    var place: String?
    var stats: DayStats
    var sport: Sport?
    var resort: String?
    /// Where it was, for the pin on the map: its highest point. nil for a day with no track.
    var lat: Double?
    var lon: Double?
    var manual: Bool?
    /// Its ups and downs, to draw its profile in the list. nil for a day with no track, and for
    /// the days saved before there was one, until the list is made again.
    var shape: [Leg]? = nil
    /// Its runs on a piste with a name, for the book of the pistes. nil for a day with no track,
    /// and for the days saved before there was one, until the list is made again.
    var pistes: [RunNote]? = nil

    var season: Season { Season(start) }
    var title: String? { place ?? resort }
    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

/// A ski area, from OpenStreetMap.
struct Resort: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    /// The region and the country, when known: "Valle d'Aosta, Italia".
    var region: String?
    var lat: Double
    var lon: Double

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

/// One day of the forecast of a ski area, from Open-Meteo.
struct ForecastDay: Codable, Hashable, Identifiable {
    /// Midnight of the day at the resort, to be read in GMT.
    var date: Date
    /// Centimeters of snow expected in the day.
    var snow: Double
    var tempMin: Double
    var tempMax: Double
    /// km/h, the strongest of the day.
    var wind: Double
    var code: Int

    var id: Date { date }
    var symbol: String { DayWeather(tempMin: tempMin, tempMax: tempMax, snowfall: snow, windMax: wind, code: code).symbol }
    var windy: Bool { wind >= 40 }
}

/// A trip planned: where and when.
struct Trip: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var start: Date
    var end: Date
    /// The ski area, when it was picked from the guide: for the forecast.
    var resort: Resort?
}

/// A winter, from July to June: "2026/27".
struct Season: Hashable, Comparable, Identifiable {
    /// The year it begins in.
    let year: Int

    init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month], from: date)
        year = (c.month ?? 1) >= 7 ? (c.year ?? 2026) : (c.year ?? 2026) - 1
    }

    var id: Int { year }
    var label: String { String(format: "%d/%02d", year, (year + 1) % 100) }

    static func < (a: Season, b: Season) -> Bool { a.year < b.year }
}
