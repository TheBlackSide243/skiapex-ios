import Foundation

/// The pistes of a ski area, each with whether you skied it: how much of the place you have done.
struct PisteTally: Equatable {
    struct Piste: Identifiable, Hashable {
        let label: String
        var ref: String?
        var difficulty: String?
        /// How long it is, all its stretches together.
        var meters: Double
        var done: Bool

        var id: String { label }
    }

    /// One for each name, the ones still to ski first and then by name.
    var pistes: [Piste] = []

    var total: Int { pistes.count }
    var done: Int { pistes.filter(\.done).count }
    var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }
    var missing: [Piste] { pistes.filter { !$0.done } }
    var complete: Bool { total > 0 && done == total }

    /// The pistes of one color of the signs: how many there are, how many are done.
    struct Grade: Identifiable, Equatable {
        let difficulty: String
        let done: Int
        let total: Int

        var id: String { difficulty }
    }

    /// How many are done and how many there are of each difficulty, in the order of the signs.
    var byDifficulty: [Grade] {
        let order = ["novice", "easy", "intermediate", "advanced", "expert", "freeride"]
        return order.compactMap { grade in
            let of = pistes.filter { $0.difficulty == grade }
            return of.isEmpty ? nil : Grade(difficulty: grade, done: of.filter(\.done).count, total: of.count)
        }
    }

    static func == (a: PisteTally, b: PisteTally) -> Bool { a.pistes == b.pistes }
}

enum Completion {
    /// How a name is compared: without capitals and spaces around.
    static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// The names of the pistes skied around a place, from the days of the diary. A run that
    /// followed several pistes counts for each of them.
    static func skied(_ days: [DaySummary], nearLat lat: Double, lon: Double, within meters: Double = PisteBook.together) -> Set<String> {
        var out: Set<String> = []
        for day in days {
            guard let notes = day.pistes, let dayLat = day.lat, let dayLon = day.lon,
                  Geo.distance(lat1: lat, lon1: lon, lat2: dayLat, lon2: dayLon) <= meters else { continue }
            for note in notes {
                for name in note.n.components(separatedBy: " · ") where !name.isEmpty {
                    out.insert(key(name))
                }
            }
        }
        return out
    }

    /// The pistes with a name of a ski area, each once, with whether it is among the ones skied.
    static func tally(_ ways: [OSMWay], skied: Set<String>) -> PisteTally {
        var found: [String: PisteTally.Piste] = [:]
        for way in ways where way.kind == .piste {
            guard let label = way.label else { continue }
            let id = key(label)
            if var known = found[id] {
                known.meters += way.meters
                if known.difficulty == nil { known.difficulty = way.difficulty }
                if known.ref == nil { known.ref = way.ref }
                found[id] = known
            } else {
                found[id] = PisteTally.Piste(label: label, ref: way.ref, difficulty: way.difficulty, meters: way.meters, done: skied.contains(id))
            }
        }
        let sorted = found.values.sorted {
            $0.done != $1.done ? !$0.done : $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
        return PisteTally(pistes: sorted)
    }
}
