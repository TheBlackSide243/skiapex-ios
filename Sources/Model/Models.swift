import CoreLocation
import Foundation

/// One fix of the GPS, as it is kept: about one a second while recording.
struct TrackPoint: Codable, Hashable {
    var t: Date
    var lat: Double
    var lon: Double
    /// Meters above the sea: the barometer's, kept on the level of the GPS; the GPS's alone on an
    /// iPhone without a barometer.
    var alt: Double
    /// m/s as the GPS measured it; below 0 when it did not.
    var speed: Double
    /// How far off the position may be, in meters.
    var hAcc: Double
    /// How far off the speed may be, in m/s; below 0 when unknown.
    var sAcc: Double

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

enum SegmentKind: String, Codable {
    /// Going down on skis.
    case run
    /// Going up on a chairlift, a gondola, a drag lift.
    case lift
    /// Standing, queuing, walking, at the bar.
    case idle
}

/// A stretch of the day: one run, one lift, or the time between them. `start` and `end` are the
/// indices of its first and last point in the day's points.
struct Segment: Codable, Hashable, Identifiable {
    var kind: SegmentKind
    var start: Int
    var end: Int
    var startTime: Date
    var endTime: Date
    /// Meters on the ground.
    var distance: Double
    /// Meters down from its first point to its last (runs).
    var drop: Double
    /// Meters up from its first point to its last (lifts).
    var gain: Double
    var maxSpeed: Double
    var avgSpeed: Double
    var topAlt: Double
    var bottomAlt: Double
    /// Its place among the runs, or among the lifts, from 1; 0 for the idle stretches.
    var number: Int
    /// The piste or the lift it was on, from OpenStreetMap; nil when not known.
    var name: String? = nil
    /// The `piste:difficulty` of OpenStreetMap: novice, easy, intermediate, advanced, expert, freeride.
    var difficulty: String? = nil

    var id: Int { start }
    var duration: TimeInterval { endTime.timeIntervalSince(startTime) }
    /// The mean steepness, as a percentage: meters down per 100 meters across (`distance` is
    /// measured on the map, flat).
    var slope: Double { distance > 1 ? drop / distance * 100 : 0 }
}

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

/// The numbers of a day.
struct DayStats: Codable, Hashable {
    var runs = 0
    var lifts = 0
    /// Meters skied down, summed over the runs.
    var vertical = 0.0
    /// Meters taken up by the lifts.
    var climb = 0.0
    var runDistance = 0.0
    var totalDistance = 0.0
    var maxSpeed = 0.0
    var avgRunSpeed = 0.0
    var topAlt = 0.0
    var lowAlt = 0.0
    var runTime = 0.0
    var liftTime = 0.0
    var totalTime = 0.0
    /// The longest run, in meters.
    var longestRun = 0.0
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

    var runs: [Segment] { segments.filter { $0.kind == .run } }
    /// The name given by hand or the town; the ski area when there is neither.
    var title: String? { place ?? resort }
    var summary: DaySummary {
        DaySummary(id: id, start: start, end: end, place: place, stats: stats, sport: sport, resort: resort)
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

    var season: Season { Season(start) }
    var title: String? { place ?? resort }
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

enum Geo {
    /// Meters between two points on the ground (haversine).
    static func distance(_ a: TrackPoint, _ b: TrackPoint) -> Double {
        distance(lat1: a.lat, lon1: a.lon, lat2: b.lat, lon2: b.lon)
    }

    static func distance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6_371_000.0
        let la1 = lat1 * .pi / 180, la2 = lat2 * .pi / 180
        let dla = la2 - la1, dlo = (lon2 - lon1) * .pi / 180
        let h = sin(dla / 2) * sin(dla / 2) + cos(la1) * cos(la2) * sin(dlo / 2) * sin(dlo / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }

    /// The compass direction from one point to another, in degrees.
    static func bearing(from a: TrackPoint, to b: TrackPoint) -> Double {
        let la1 = a.lat * .pi / 180, la2 = b.lat * .pi / 180
        let dlo = (b.lon - a.lon) * .pi / 180
        let y = sin(dlo) * cos(la2)
        let x = cos(la1) * sin(la2) - sin(la1) * cos(la2) * cos(dlo)
        let deg = atan2(y, x) * 180 / .pi
        return deg < 0 ? deg + 360 : deg
    }
}
