import Foundation

/// A made-up day on the snow: a chairlift up, a winding piste down, a queue at the bottom, again
/// and again, one point a second with the noise of a real GPS. For the tests, for the demo and for
/// "Crea una giornata di prova" in Settings, to see the app without going skiing.
enum SkiSim {
    /// A fixed sequence of random numbers, so that the same seed always gives the same day.
    struct Random {
        var state: UInt64
        mutating func next() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53)
        }
        mutating func gauss() -> Double {
            let u = max(1e-12, next()), v = next()
            return sqrt(-2 * log(u)) * cos(2 * .pi * v)
        }
    }

    private struct Spot { var x: Double; var y: Double; var alt: Double }

    /// `laps` times up and down; `stopEvery`: every so many runs a 30-second stop half way.
    static func day(laps: Int = 8, start: Date = Date(timeIntervalSinceNow: -6 * 3600), seed: UInt64 = 7,
                    lat0: Double = 45.9336, lon0: Double = 7.6295, stopEvery: Int = 3) -> [TrackPoint] {
        var rng = Random(state: seed)
        var out: [TrackPoint] = []
        var t = start
        let base = Spot(x: 0, y: 0, alt: 2050)
        let top = Spot(x: 1200, y: 1700, alt: 2780)

        func emit(_ s: Spot, speed: Double) {
            let lat = lat0 + (s.y + rng.gauss() * 2.5) / 111_320
            let lon = lon0 + (s.x + rng.gauss() * 2.5) / (111_320 * cos(lat0 * .pi / 180))
            out.append(TrackPoint(t: t, lat: lat, lon: lon, alt: s.alt + rng.gauss() * 0.4,
                                  speed: max(0, speed + rng.gauss() * 0.3), hAcc: 4 + rng.next() * 4, sAcc: 0.5))
            t = t.addingTimeInterval(1)
        }
        func wait(_ seconds: Int, at s: Spot) {
            for _ in 0..<seconds { emit(Spot(x: s.x + rng.gauss() * 0.5, y: s.y + rng.gauss() * 0.5, alt: s.alt), speed: 0.2) }
        }
        /// Along a line of spots, at a speed that depends on how far along it is (0...1).
        func travel(_ path: [Spot], speed: (Double) -> Double) {
            var lengths = [0.0]
            for i in 1..<path.count {
                let d = hypot(path[i].x - path[i - 1].x, path[i].y - path[i - 1].y)
                lengths.append(lengths[i - 1] + d)
            }
            let total = lengths.last ?? 0
            var s = 0.0
            var k = 1
            while s < total {
                while k < path.count - 1 && lengths[k] < s { k += 1 }
                let a = path[k - 1], b = path[k]
                let span = lengths[k] - lengths[k - 1]
                let f = span > 0 ? (s - lengths[k - 1]) / span : 0
                let here = Spot(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f, alt: a.alt + (b.alt - a.alt) * f)
                let v = max(0.5, speed(s / total))
                emit(here, speed: v)
                s += v
            }
        }

        // Boots on, a walk to the lift.
        wait(240, at: Spot(x: -150, y: -60, alt: base.alt - 5))
        travel([Spot(x: -150, y: -60, alt: base.alt - 5), base]) { _ in 1.1 }

        for lap in 0..<laps {
            wait(90 + Int(rng.next() * 180), at: base)
            // The chairlift: a straight line, 5 m/s along the cable.
            travel([base, top]) { _ in 4.8 }
            wait(40, at: top)
            // The piste: winding down, faster in the middle.
            let wiggle = lap % 2 == 0 ? 260.0 : 180.0
            let turns = lap % 2 == 0 ? 3.0 : 4.0
            var path: [Spot] = []
            for k in 0...80 {
                let f = Double(k) / 80
                let side = sin(f * .pi * turns) * wiggle * sin(f * .pi)
                // Perpendicular to the line from the top to the bottom.
                let dx = base.x - top.x, dy = base.y - top.y
                let len = hypot(dx, dy)
                let px = -dy / len, py = dx / len
                path.append(Spot(x: top.x + dx * f + px * side, y: top.y + dy * f + py * side,
                                 alt: top.alt + (base.alt - top.alt) * f))
            }
            let fast = 11.0 + Double(lap % 3) * 2.5
            if stopEvery > 0 && lap % stopEvery == stopEvery - 1 {
                let half = path.count / 2
                travel(Array(path[...half])) { f in fast + 4 * sin(f * .pi * 5) }
                wait(30, at: path[half])
                travel(Array(path[half...])) { f in fast + 4 * sin(f * .pi * 5) }
            } else {
                travel(path) { f in min(fast + 4 * sin(f * .pi * 5), 3 + f * 60, 3 + (1 - f) * 60) }
            }
        }
        wait(300, at: base)
        return out
    }
}
