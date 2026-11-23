import Foundation

/// Cuts a day into runs, lifts and the time between them, from the points alone: no map of the
/// resort is needed. It looks at how fast the altitude changes over half a minute: going down
/// while moving is skiing, going up is a lift. Short stretches are taken into their neighbors
/// (a stop on the piste is part of the run, a stop of the chairlift part of the lift), and what
/// is too small to count (a few meters down to the lift) is left out.
enum Segmenter {
    struct Result {
        var segments: [Segment] = []
        var stats = DayStats()
        /// What is going on at the last point, even before it is big enough to count: for the
        /// screen while recording.
        var current: SegmentKind = .idle

        static let empty = Result()
    }

    // The thresholds, in meters, seconds and m/s.
    static let minRunDrop = 25.0
    static let minRunDuration = 20.0
    static let minRunTopSpeed = 4.0
    static let minLiftGain = 30.0
    /// Points further apart than this in time are not joined by a line: a pause, or no GPS.
    static let gap = 60.0
    /// Faster than this between two points is a jump of the GPS, not skiing (216 km/h).
    static let maxSpeed = 60.0

    /// The points that can be trusted, in order of time.
    static func clean(_ raw: [TrackPoint]) -> [TrackPoint] {
        var out: [TrackPoint] = []
        out.reserveCapacity(raw.count)
        for p in raw.sorted(by: { $0.t < $1.t }) {
            guard p.hAcc >= 0, p.hAcc <= 50, p.lat.isFinite, p.lon.isFinite, p.alt.isFinite else { continue }
            if let last = out.last {
                let dt = p.t.timeIntervalSince(last.t)
                if dt <= 0 { continue }
                // A jump: farther than anyone goes in that time (and more than the GPS can be off).
                let d = Geo.distance(last, p)
                if d > max(maxSpeed * dt, p.hAcc + last.hAcc + 30) && d / dt > maxSpeed { continue }
            }
            out.append(p)
        }
        return out
    }

    private enum Label { case down, up, flat, still }

    private struct Block {
        var label: Label
        var start: Int
        var end: Int
    }

    static func analyze(_ points: [TrackPoint]) -> Result {
        let n = points.count
        guard n >= 3 else { return .empty }
        let ts = points.map { $0.t.timeIntervalSinceReferenceDate }

        // The altitude smoothed over ±8 s: the barometer is quiet, the GPS much less.
        let alt = windowMean(points.map(\.alt), ts, half: 8)

        // The speed of each point: the GPS's when it is good, otherwise from the distance.
        var raw = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let p = points[i]
            if p.speed >= 0, p.sAcc < 0 || p.sAcc <= 4, p.speed < maxSpeed {
                raw[i] = p.speed
            } else if i > 0 {
                let dt = ts[i] - ts[i - 1]
                raw[i] = dt > 0 && dt <= gap ? min(maxSpeed, Geo.distance(points[i - 1], p) / dt) : 0
            }
        }
        let speed = windowMean(raw, ts, half: 4)

        // How fast the altitude changes, over ±12 s.
        var vz = [Double](repeating: 0, count: n)
        var lo = 0, hi = 0
        for i in 0..<n {
            while ts[lo] < ts[i] - 12 { lo += 1 }
            if hi < i { hi = i }
            while hi + 1 < n && ts[hi + 1] <= ts[i] + 12 { hi += 1 }
            let dt = ts[hi] - ts[lo]
            vz[i] = dt >= 5 ? (alt[hi] - alt[lo]) / dt : 0
        }

        var labels = [Label](repeating: .still, count: n)
        for i in 0..<n {
            if vz[i] > 0.3 {
                labels[i] = .up
            } else if vz[i] < -0.3 && speed[i] > 1.2 {
                labels[i] = .down
            } else {
                labels[i] = speed[i] >= 1.2 ? .flat : .still
            }
        }

        var blocks = makeBlocks(labels, ts)
        func duration(_ b: Block) -> Double { ts[b.end] - ts[b.start] + 1 }

        // Short stretches go into the longer of their neighbors, the shortest first.
        for _ in 0..<n {
            guard blocks.count > 1,
                  let k = blocks.indices.filter({ duration(blocks[$0]) < 15 }).min(by: { duration(blocks[$0]) < duration(blocks[$1]) })
            else { break }
            let prev = k > 0 ? blocks[k - 1] : nil
            let next = k + 1 < blocks.count ? blocks[k + 1] : nil
            let into: Label
            if let prev, let next { into = duration(prev) >= duration(next) ? prev.label : next.label } else { into = (prev ?? next)!.label }
            blocks[k].label = into
            blocks = merge(blocks)
        }

        // A stretch between two of the same kind belongs to them when it is short enough: a stop
        // or a flat part on the piste, a stop of the lift or a flat part of its line.
        var changed = true
        var rounds = 0
        while changed && rounds < 10 {
            changed = false
            rounds += 1
            if blocks.count >= 3 {
                for k in 1..<(blocks.count - 1) {
                    let a = blocks[k - 1].label, b = blocks[k + 1].label, d = duration(blocks[k])
                    guard a == b, blocks[k].label != a else { continue }
                    let joins: Bool
                    switch (a, blocks[k].label) {
                    case (.down, .flat): joins = d < 180
                    case (.down, .still): joins = d < 60
                    case (.up, .flat): joins = d < 150
                    case (.up, .still): joins = d < 180
                    default: joins = false
                    }
                    if joins {
                        blocks[k].label = a
                        changed = true
                    }
                }
            }
            // The flat run-out at the end of a piste, or the flat start on top.
            for k in blocks.indices where blocks[k].label == .flat && duration(blocks[k]) < 40 {
                let nearDown = (k > 0 && blocks[k - 1].label == .down) || (k + 1 < blocks.count && blocks[k + 1].label == .down)
                if nearDown {
                    blocks[k].label = .down
                    changed = true
                }
            }
            blocks = merge(blocks)
        }

        // What each stretch is, once it is measured.
        var segments: [Segment] = []
        for b in blocks {
            var seg = measure(b.start, b.end, points: points, ts: ts, alt: alt, speed: raw)
            switch b.label {
            case .down where seg.drop >= minRunDrop && seg.duration >= minRunDuration && seg.maxSpeed >= minRunTopSpeed:
                seg.kind = .run
            case .up where seg.gain >= minLiftGain:
                seg.kind = .lift
            default:
                seg.kind = .idle
            }
            if let last = segments.last, last.kind == .idle, seg.kind == .idle {
                segments[segments.count - 1] = measure(last.start, b.end, points: points, ts: ts, alt: alt, speed: raw)
            } else {
                segments.append(seg)
            }
        }
        var runs = 0, lifts = 0
        for i in segments.indices {
            switch segments[i].kind {
            case .run: runs += 1; segments[i].number = runs
            case .lift: lifts += 1; segments[i].number = lifts
            case .idle: segments[i].number = 0
            }
        }

        var stats = DayStats()
        let runSegs = segments.filter { $0.kind == .run }
        let liftSegs = segments.filter { $0.kind == .lift }
        stats.runs = runSegs.count
        stats.lifts = liftSegs.count
        stats.vertical = runSegs.reduce(0) { $0 + $1.drop }
        stats.climb = liftSegs.reduce(0) { $0 + $1.gain }
        stats.runDistance = runSegs.reduce(0) { $0 + $1.distance }
        stats.totalDistance = segments.reduce(0) { $0 + $1.distance }
        stats.runTime = runSegs.reduce(0) { $0 + $1.duration }
        stats.liftTime = liftSegs.reduce(0) { $0 + $1.duration }
        stats.maxSpeed = runSegs.map(\.maxSpeed).max() ?? 0
        stats.avgRunSpeed = stats.runTime > 0 ? stats.runDistance / stats.runTime : 0
        stats.longestRun = runSegs.map(\.distance).max() ?? 0
        stats.topAlt = alt.max() ?? 0
        stats.lowAlt = alt.min() ?? 0
        stats.totalTime = ts[n - 1] - ts[0]

        let current: SegmentKind
        switch blocks.last?.label {
        case .down?: current = .run
        case .up?: current = .lift
        default: current = .idle
        }
        return Result(segments: segments, stats: stats, current: current)
    }

    private static func makeBlocks(_ labels: [Label], _ ts: [Double]) -> [Block] {
        var blocks: [Block] = []
        for i in labels.indices {
            let afterGap = i > 0 && ts[i] - ts[i - 1] > gap
            if let last = blocks.last, last.label == labels[i], !afterGap {
                blocks[blocks.count - 1].end = i
            } else {
                blocks.append(Block(label: labels[i], start: i, end: i))
            }
        }
        return blocks
    }

    private static func merge(_ blocks: [Block]) -> [Block] {
        var out: [Block] = []
        for b in blocks {
            if let last = out.last, last.label == b.label {
                out[out.count - 1].end = b.end
            } else {
                out.append(b)
            }
        }
        return out
    }

    private static func measure(_ s: Int, _ e: Int, points: [TrackPoint], ts: [Double], alt: [Double], speed: [Double]) -> Segment {
        var distance = 0.0
        var top = alt[s], bottom = alt[s]
        var fastest = 0.0
        for i in s...e {
            top = max(top, alt[i])
            bottom = min(bottom, alt[i])
            if i > s {
                let dt = ts[i] - ts[i - 1]
                if dt <= gap { distance += Geo.distance(points[i - 1], points[i]) }
            }
            // The top speed: the middle of three, so that one wrong reading does not count.
            if i > s && i < e {
                let m = median(speed[i - 1], speed[i], speed[i + 1])
                if points[i].hAcc <= 25 { fastest = max(fastest, m) }
            }
        }
        let duration = ts[e] - ts[s]
        return Segment(kind: .idle, start: s, end: e,
                       startTime: points[s].t, endTime: points[e].t,
                       distance: distance,
                       drop: max(0, alt[s] - alt[e]),
                       gain: max(0, alt[e] - alt[s]),
                       maxSpeed: fastest,
                       avgSpeed: duration > 0 ? distance / duration : 0,
                       topAlt: top, bottomAlt: bottom, number: 0)
    }

    private static func median(_ a: Double, _ b: Double, _ c: Double) -> Double {
        max(min(a, b), min(max(a, b), c))
    }

    /// The mean of the values within ±`half` seconds of each one.
    static func windowMean(_ values: [Double], _ ts: [Double], half: Double) -> [Double] {
        let n = values.count
        guard n > 0 else { return [] }
        var prefix = [Double](repeating: 0, count: n + 1)
        for i in 0..<n { prefix[i + 1] = prefix[i] + values[i] }
        var out = [Double](repeating: 0, count: n)
        var lo = 0, hi = 0
        for i in 0..<n {
            while ts[lo] < ts[i] - half { lo += 1 }
            if hi < i { hi = i }
            while hi + 1 < n && ts[hi + 1] <= ts[i] + half { hi += 1 }
            out[i] = (prefix[hi + 1] - prefix[lo]) / Double(hi - lo + 1)
        }
        return out
    }
}
