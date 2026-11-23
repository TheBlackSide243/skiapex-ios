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

    var id: Int { start }
    var duration: TimeInterval { endTime.timeIntervalSince(startTime) }
    /// The mean steepness, as a percentage: meters down per 100 meters across (`distance` is
    /// measured on the map, flat).
    var slope: Double { distance > 1 ? drop / distance * 100 : 0 }
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
    /// Where it was: the resort or the town, from the map; nil until it is known.
    var place: String?
    var points: [TrackPoint]
    var segments: [Segment]
    var stats: DayStats

    /// A day made of the points recorded: cleaned up, then cut into runs and lifts.
    init(id: UUID = UUID(), points raw: [TrackPoint], place: String? = nil) {
        let points = Segmenter.clean(raw)
        let result = Segmenter.analyze(points)
        self.id = id
        self.points = points
        self.start = points.first?.t ?? Date()
        self.end = points.last?.t ?? Date()
        self.place = place
        self.segments = result.segments
        self.stats = result.stats
    }

    var runs: [Segment] { segments.filter { $0.kind == .run } }
    var summary: DaySummary { DaySummary(id: id, start: start, end: end, place: place, stats: stats) }
}

/// What the list of days shows, without the points: kept all together in one small file.
struct DaySummary: Codable, Identifiable, Hashable {
    var id: UUID
    var start: Date
    var end: Date
    var place: String?
    var stats: DayStats

    var season: Season { Season(start) }
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
}
