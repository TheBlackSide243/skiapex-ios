import Foundation

/// One run of a day as the book of the pistes keeps it: which piste it followed, how long it took
/// and how fast. Short names, for it is written for every run in the list of the days.
struct RunNote: Codable, Hashable {
    /// The piste, or the pistes one after the other, as OpenStreetMap calls them.
    var n: String
    /// Its number on the signs.
    var r: String?
    /// Its difficulty.
    var d: String?
    /// How long the run took, in seconds.
    var s: Double
    /// The top speed, in m/s.
    var v: Double
    /// Meters down, and meters on the ground.
    var h: Double
    var m: Double
    /// When it began.
    var t: Date

    /// The runs of a day on a piste with a name. Empty for a day with none, nil for a day with
    /// no track at all.
    static func of(_ day: SkiDay) -> [RunNote]? {
        guard !day.points.isEmpty else { return nil }
        return day.segments.compactMap { seg in
            guard seg.kind == .run, let name = seg.name, !name.isEmpty, seg.duration >= PisteBook.shortest else { return nil }
            return RunNote(n: name, r: seg.ref, d: seg.difficulty, s: seg.duration, v: seg.maxSpeed, h: seg.drop, m: seg.distance,
                           t: seg.startTime)
        }
    }
}

/// A piste you skied, with every time you did.
struct PisteEntry: Identifiable, Hashable {
    /// One time down it.
    struct Lap: Identifiable, Hashable {
        let day: UUID
        let date: Date
        let seconds: Double
        let maxSpeed: Double
        let drop: Double
        let meters: Double

        var id: String { "\(day.uuidString)-\(date.timeIntervalSince1970)" }
    }

    let name: String
    var ref: String?
    var difficulty: String?
    /// Where it is, to tell it from a piste of the same name somewhere else: the place of the
    /// first day it was met on, and what that day was called.
    let lat: Double
    let lon: Double
    var place: String?
    /// From the first time to the last.
    var laps: [Lap] = []

    var id: String { String(format: "%@|%.2f,%.2f", name, lat, lon) }
    var count: Int { laps.count }
    var topSpeed: Double { laps.map(\.maxSpeed).max() ?? 0 }
    var vertical: Double { laps.reduce(0) { $0 + $1.drop } }
    var last: Date { laps.last?.date ?? .distantPast }
    /// The most meters down in one go: what the whole piste is taken to be.
    var fullDrop: Double { laps.map(\.drop).max() ?? 0 }
    /// How long it is, as the longest time down it.
    var meters: Double { laps.map(\.meters).max() ?? 0 }

    /// The times it was skied from the top to the bottom, or nearly: a run begun halfway, or cut
    /// by a stop, is not a time to beat.
    var whole: [Lap] {
        let least = fullDrop * PisteBook.wholeShare
        return laps.filter { $0.drop >= least }
    }

    /// The fastest time down the whole of it.
    var best: Lap? { whole.min { $0.seconds < $1.seconds } }
}

/// The pistes of all the days: how many times each was skied, the best time, the top speed.
enum PisteBook {
    /// A run shorter than this many seconds is not a time on a piste.
    static let shortest = 20.0
    /// A run counts as the whole piste from this share of the biggest drop seen on it.
    static let wholeShare = 0.85
    /// Two days this close are at the same ski area: a piste of the same name is the same piste.
    static let together = 15_000.0

    /// Every piste with a name in the days given, the ones skied most first.
    static func entries(_ days: [DaySummary]) -> [PisteEntry] {
        var out: [PisteEntry] = []
        var byName: [String: [Int]] = [:]
        for day in days.sorted(by: { $0.start < $1.start }) {
            guard let notes = day.pistes, let lat = day.lat, let lon = day.lon else { continue }
            for note in notes {
                let lap = PisteEntry.Lap(day: day.id, date: note.t, seconds: note.s, maxSpeed: note.v, drop: note.h, meters: note.m)
                let known = byName[note.n, default: []].first {
                    Geo.distance(lat1: lat, lon1: lon, lat2: out[$0].lat, lon2: out[$0].lon) <= together
                }
                if let known {
                    out[known].laps.append(lap)
                    // The number and the color as the newest day has them.
                    if let ref = note.r { out[known].ref = ref }
                    if let difficulty = note.d { out[known].difficulty = difficulty }
                    if out[known].place == nil { out[known].place = day.title }
                } else {
                    byName[note.n, default: []].append(out.count)
                    out.append(PisteEntry(name: note.n, ref: note.r, difficulty: note.d, lat: lat, lon: lon, place: day.title, laps: [lap]))
                }
            }
        }
        for i in out.indices { out[i].laps.sort { $0.date < $1.date } }
        return out.sorted { $0.count != $1.count ? $0.count > $1.count : $0.last > $1.last }
    }

    /// The pistes skied within a few kilometers of a place.
    static func entries(_ days: [DaySummary], nearLat lat: Double, lon: Double, within meters: Double = 12_000) -> [PisteEntry] {
        entries(days).filter { Geo.distance(lat1: lat, lon1: lon, lat2: $0.lat, lon2: $0.lon) <= max(meters, together) }
    }

    /// The piste a run of a day was on, among the ones in the book.
    static func entry(named name: String?, of day: DaySummary?, in entries: [PisteEntry]) -> PisteEntry? {
        guard let name, let lat = day?.lat, let lon = day?.lon else { return nil }
        return entries.first { $0.name == name && Geo.distance(lat1: lat, lon1: lon, lat2: $0.lat, lon2: $0.lon) <= together }
    }

    /// What is sent of a piste to challenge the friends on it: its name, where to the kilometer,
    /// your best time down the whole of it, and how many times you did it.
    static func shared(_ entry: PisteEntry) -> [String: Any]? {
        guard let best = entry.best else { return nil }
        var out: [String: Any] = ["name": entry.name, "lat": (entry.lat * 100).rounded() / 100, "lon": (entry.lon * 100).rounded() / 100,
                                  "best": best.seconds, "speed": entry.topSpeed, "runs": entry.count,
                                  "date": PlaceInfo.dayFormat.string(from: best.date)]
        if let difficulty = entry.difficulty { out["difficulty"] = difficulty }
        return out
    }
}

extension Fmt {
    /// The time of a run down a piste: "2:41", "1:02:07".
    static func lap(_ s: TimeInterval) -> String {
        let total = Int(max(0, s).rounded())
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60) }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
