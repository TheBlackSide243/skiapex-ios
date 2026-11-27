import Foundation

/// Your best time down a piste, with the track of that run: what the run under way is measured
/// against, to say whether you are ahead of yourself or behind.
struct GhostLap: Identifiable, Equatable {
    let id: String
    let name: String
    /// Your best time on it.
    let seconds: Double
    let date: Date
    /// The points of that run, one every couple of seconds.
    let points: [TrackPoint]
}

/// The run going on, or the last one: where and when it began and where it got to.
struct LiveRun: Equatable {
    let start: TrackPoint
    let end: TrackPoint
    /// Still going down.
    let live: Bool
}

enum Ghost {
    /// How close to the track of the best run a run must begin, and stay, in meters.
    static let startReach = 80.0
    static let reach = 60.0

    /// How you stand against your best on a piste.
    struct Standing: Equatable {
        let name: String
        /// Seconds: below zero ahead of your best, above it behind.
        let delta: Double
        /// Your best time on the whole piste.
        let best: Double
        /// How much of the best run, in time, the stretch compared covers: from 0 to 1.
        let share: Double

        var ahead: Bool { delta < 0 }
        /// Too close to call with the GPS of a phone.
        var even: Bool { abs(delta) < 0.5 }
    }

    /// Where a lap passes closest to a point, from a place of it on. nil when it never comes
    /// within the meters given.
    static func index(of point: TrackPoint, in lap: GhostLap, from start: Int = 0, within meters: Double) -> Int? {
        var best: Int?
        var least = meters
        var i = max(0, start)
        while i < lap.points.count {
            let distance = Geo.distance(point, lap.points[i])
            if distance <= least {
                best = i
                least = distance
            }
            i += 1
        }
        return best
    }

    /// How a run stands against the best laps around: from where it began to where it is now,
    /// against the time the best run took between the same two places. The lap whose track the
    /// run began closest to; nil when it began on none, or left it.
    static func standing(start: TrackPoint, now: TrackPoint, among laps: [GhostLap]) -> Standing? {
        var found: Standing?
        var closest = Double.infinity
        let mine = now.t.timeIntervalSince(start.t)
        guard mine > 0 else { return nil }
        for lap in laps where lap.points.count > 2 {
            guard let from = index(of: start, in: lap, within: startReach),
                  let to = index(of: now, in: lap, from: from, within: reach), to > from else { continue }
            let reference = lap.points[to].t.timeIntervalSince(lap.points[from].t)
            let whole = lap.points[lap.points.count - 1].t.timeIntervalSince(lap.points[0].t)
            guard reference > 0, whole > 0 else { continue }
            let off = Geo.distance(start, lap.points[from])
            if off < closest {
                closest = off
                found = Standing(name: lap.name, delta: mine - reference, best: lap.seconds, share: min(1, reference / whole))
            }
        }
        return found
    }

    /// One point every so many seconds, with the first and the last.
    static func thin(_ points: [TrackPoint], every seconds: Double = 2) -> [TrackPoint] {
        guard var last = points.first else { return [] }
        var out = [last]
        for point in points.dropFirst() where point.t.timeIntervalSince(last.t) >= seconds {
            out.append(point)
            last = point
        }
        if let end = points.last, end != out.last { out.append(end) }
        return out
    }

    /// The best lap of each of your pistes around a place, with its track read from the day it
    /// was skied on: the pistes skied most first, a couple of dozen at most.
    static func laps(nearLat lat: Double, lon: Double, days: [DaySummary], limit: Int = 24, read: (UUID) -> SkiDay?) -> [GhostLap] {
        let entries = PisteBook.entries(days, nearLat: lat, lon: lon).sorted { $0.count > $1.count }.prefix(limit)
        var loaded: [UUID: SkiDay] = [:]
        var out: [GhostLap] = []
        for entry in entries {
            guard let best = entry.best else { continue }
            if loaded[best.day] == nil { loaded[best.day] = read(best.day) }
            guard let day = loaded[best.day],
                  let run = day.segments.first(where: { $0.kind == .run && abs($0.startTime.timeIntervalSince(best.date)) < 1 }),
                  run.start < run.end, run.end < day.points.count else { continue }
            out.append(GhostLap(id: entry.id, name: entry.name, seconds: best.seconds, date: best.date,
                                points: thin(Array(day.points[run.start...run.end]))))
        }
        return out
    }

    /// A difference of time as it is shown: "3,2 s", "1:05".
    static func text(_ delta: Double) -> String {
        let size = abs(delta)
        if size < 60 { return "\(size.formatted(.number.precision(.fractionLength(size < 10 ? 1 : 0)))) s" }
        return Fmt.lap(size)
    }
}
