import CoreLocation
import Foundation

// The points of a day and what they are cut into. These few types are also in the Apple Watch
// app, which records and counts runs by itself: nothing here leans on the rest of the iPhone app.

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
