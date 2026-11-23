import CoreLocation
import Foundation
import Observation

/// The days saved, one JSON file each in Documents/Giornate, and a small index with their numbers
/// for the list. The folder is visible in the Files app.
@Observable final class Library {
    private(set) var days: [DaySummary] = []
    /// Goes up at every save: an open day reads itself again when it changes.
    private(set) var saves = 0
    /// The trips planned, soonest first.
    private(set) var trips: [Trip] = []
    /// The ski areas kept in the guide.
    private(set) var favorites: [Resort] = []
    /// The day just ended, to ask how the snow was: remembered until it is asked, also when the
    /// day arrived from the watch with the app closed.
    private(set) var asking: UUID?
    @ObservationIgnored private var keepsAsking = false

    /// Sets the day to ask about, or nil once it was asked.
    func ask(_ id: UUID?) {
        asking = id
        if keepsAsking { UserDefaults.standard.set(id?.uuidString, forKey: "askSnow") }
    }

    /// The days being looked up on the internet right now.
    @ObservationIgnored private var enriching: Set<UUID> = []
    private let dir: URL
    private var index: URL { dir.appendingPathComponent("indice.json") }
    private var tripsFile: URL { dir.appendingPathComponent("viaggi.json") }
    private var favoritesFile: URL { dir.appendingPathComponent("stazioni.json") }

    init(directory: URL? = nil) {
        dir = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Giornate", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: index), let saved = try? JSONDecoder().decode([DaySummary].self, from: data) {
            days = saved
        } else {
            rebuildIndex()
        }
        // The index of the first versions had no place for the pins: made again, once.
        let marker = dir.appendingPathComponent(".indice-2")
        if !FileManager.default.fileExists(atPath: marker.path) {
            if days.contains(where: { $0.lat == nil }) { rebuildIndex() }
            FileManager.default.createFile(atPath: marker.path, contents: nil)
        }
        // Only the library of the app remembers what to ask: the ones made for a test or the demo do not.
        if directory == nil {
            keepsAsking = true
            if let id = UserDefaults.standard.string(forKey: "askSnow").flatMap({ UUID(uuidString: $0) }),
               days.contains(where: { $0.id == id }) {
                asking = id
            }
        }
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: tripsFile), let saved = try? decoder.decode([Trip].self, from: data) { trips = saved }
        if let data = try? Data(contentsOf: favoritesFile), let saved = try? decoder.decode([Resort].self, from: data) { favorites = saved }
    }

    // MARK: Trips and favorite ski areas

    /// The trips not over yet, soonest first.
    var upcomingTrips: [Trip] {
        let today = Calendar.current.startOfDay(for: Date())
        return trips.filter { $0.end >= today }.sorted { $0.start < $1.start }
    }

    func saveTrip(_ trip: Trip) {
        trips.removeAll { $0.id == trip.id }
        trips.append(trip)
        trips.sort { $0.start < $1.start }
        if let data = try? JSONEncoder().encode(trips) { try? data.write(to: tripsFile, options: .atomic) }
    }

    func deleteTrip(_ id: UUID) {
        trips.removeAll { $0.id == id }
        if let data = try? JSONEncoder().encode(trips) { try? data.write(to: tripsFile, options: .atomic) }
    }

    func isFavorite(_ resort: Resort) -> Bool { favorites.contains { $0.id == resort.id } }

    func toggleFavorite(_ resort: Resort) {
        if isFavorite(resort) {
            favorites.removeAll { $0.id == resort.id }
        } else {
            favorites.append(resort)
        }
        if let data = try? JSONEncoder().encode(favorites) { try? data.write(to: favoritesFile, options: .atomic) }
    }

    /// The days recorded within a few kilometers of a place.
    func days(near resort: Resort, within meters: Double = 12_000) -> [DaySummary] {
        days.filter {
            guard let lat = $0.lat, let lon = $0.lon else { return false }
            return Geo.distance(lat1: lat, lon1: lon, lat2: resort.lat, lon2: resort.lon) <= meters
        }
    }

    var seasons: [Season] { Array(Set(days.map(\.season))).sorted(by: >) }

    func days(in season: Season?) -> [DaySummary] {
        guard let season else { return days }
        return days.filter { $0.season == season }
    }

    private func file(_ id: UUID) -> URL { dir.appendingPathComponent("\(id.uuidString).json") }

    func day(_ id: UUID) -> SkiDay? {
        guard let data = try? Data(contentsOf: file(id)) else { return nil }
        return try? JSONDecoder().decode(SkiDay.self, from: data)
    }

    func save(_ day: SkiDay) throws {
        let data = try JSONEncoder().encode(day)
        try data.write(to: file(day.id), options: .atomic)
        days.removeAll { $0.id == day.id }
        days.append(day.summary)
        days.sort { $0.start > $1.start }
        writeIndex()
        saves += 1
    }

    /// How the snow was, said at the end of the day or later. nil takes it off.
    func setSnow(_ id: UUID, to snow: Snow?, told: Bool) {
        guard var day = day(id) else { return }
        day.snow = snow
        day.told = told ? true : nil
        try? save(day)
    }

    func setSport(_ id: UUID, to sport: Sport) {
        guard var day = day(id) else { return }
        day.sport = sport
        try? save(day)
    }

    /// A day out of a GPX file, from this app or from another one.
    @discardableResult func importGPX(_ url: URL) throws -> UUID {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let points = GPXImport.points(from: try Data(contentsOf: url))
        guard points.count >= 10 else { throw ImportError.empty }
        let day = SkiDay(points: points, sport: Sport.current)
        if days.contains(where: { abs($0.start.timeIntervalSince(day.start)) < 2 && abs($0.end.timeIntervalSince(day.end)) < 2 }) {
            throw ImportError.duplicate
        }
        try save(day)
        return day.id
    }

    /// What the internet knows about a day and the app does not yet: the town, the names of the
    /// pistes and of the lifts (OpenStreetMap), the weather (Open-Meteo). Each is asked once; what
    /// fails is asked again the next time the day is opened. Nothing is asked when "Nomi delle
    /// piste e meteo" is off in Settings.
    @MainActor func enrich(_ id: UUID) async {
        let allowed = UserDefaults.standard.object(forKey: Prefs.online) as? Bool ?? true
        guard allowed, !Demo.isOn, !enriching.contains(id), let before = day(id), !before.points.isEmpty else { return }
        guard before.place == nil || before.mapped != true || before.weather == nil else { return }
        enriching.insert(id)
        defer { enriching.remove(id) }
        var place: String?
        var map: ResortMap?
        var weather: DayWeather?
        if before.place == nil { place = await Places.name(for: before) }
        if before.mapped != true { map = try? await Pistes.fetch(around: before.points) }
        if before.weather == nil { weather = try? await Weather.fetch(for: before) }
        // Read again: it may have been renamed, or deleted, in the meantime.
        guard var day = day(id), place != nil || map != nil || weather != nil else { return }
        if day.place == nil, let place { day.place = place }
        if let map {
            Pistes.apply(map, to: &day)
            day.mapped = true
        }
        if day.weather == nil, let weather { day.weather = weather }
        try? save(day)
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: file(id))
        days.removeAll { $0.id == id }
        writeIndex()
        saves += 1
    }

    func rename(_ id: UUID, to place: String) {
        guard var day = day(id) else { return }
        let name = place.trimmingCharacters(in: .whitespacesAndNewlines)
        day.place = name.isEmpty ? nil : name
        try? save(day)
    }

    /// Every day in one zip file, in the temporary folder: to keep somewhere else, or to move
    /// to another iPhone.
    func exportBackup() throws -> URL {
        let name = DateFormatter()
        name.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ski Apex \(name.string(from: Date())).zip")
        try? FileManager.default.removeItem(at: url)
        let zip = try ZipWriter(url: url)
        for day in days {
            try zip.add("\(day.id.uuidString).json", file: file(day.id))
        }
        try zip.finish()
        return url
    }

    /// The days of a copy that are not here yet are added; none is replaced. Returns how many.
    func restore(from url: URL) throws -> Int {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let zip = try ZipReader(url: url)
        let decoder = JSONDecoder()
        var added = 0
        for entry in zip.entries where entry.name.hasSuffix(".json") && !entry.name.contains("/") {
            guard let day = try? decoder.decode(SkiDay.self, from: zip.data(entry)) else { continue }
            let here = days.contains {
                $0.id == day.id || (abs($0.start.timeIntervalSince(day.start)) < 2 && abs($0.end.timeIntervalSince(day.end)) < 2)
            }
            if here { continue }
            try save(day)
            added += 1
        }
        return added
    }

    private func writeIndex() {
        if let data = try? JSONEncoder().encode(days) { try? data.write(to: index, options: .atomic) }
    }

    /// The index made again from the files: when it is missing or cannot be read.
    private func rebuildIndex() {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        days = files.filter { $0.pathExtension == "json" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
            .compactMap { try? decoder.decode(SkiDay.self, from: Data(contentsOf: $0)).summary }
            .sorted { $0.start > $1.start }
        writeIndex()
    }
}

/// The name of the place of a day, from the map: the town (or the area) around its highest point.
enum Places {
    static func name(for day: SkiDay) async -> String? {
        guard let top = day.points.max(by: { $0.alt < $1.alt }) else { return nil }
        let location = CLLocation(latitude: top.lat, longitude: top.lon)
        guard let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        return mark.locality ?? mark.subAdministrativeArea ?? mark.administrativeArea ?? mark.name
    }
}

/// A day as GPX, for Strava, Google Earth and the other apps.
enum GPX {
    static func document(_ day: SkiDay) -> String {
        let iso = ISO8601DateFormatter()
        var s = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Ski Apex" xmlns="http://www.topografix.com/GPX/1/1">
        <metadata><name>\(escape(title(day)))</name><time>\(iso.string(from: day.start))</time></metadata>
        <trk><name>\(escape(title(day)))</name><type>skiing</type>

        """
        var open = false
        var previous: TrackPoint?
        for p in day.points {
            // A new piece of track after a pause.
            if let previous, p.t.timeIntervalSince(previous.t) > Segmenter.gap, open {
                s += "</trkseg>\n"
                open = false
            }
            if !open {
                s += "<trkseg>\n"
                open = true
            }
            s += String(format: "<trkpt lat=\"%.7f\" lon=\"%.7f\"><ele>%.1f</ele><time>%@</time></trkpt>\n",
                        p.lat, p.lon, p.alt, iso.string(from: p.t))
            previous = p
        }
        if open { s += "</trkseg>\n" }
        s += "</trk>\n</gpx>\n"
        return s
    }

    /// The file, in the temporary folder, for the share sheet.
    static func file(_ day: SkiDay) throws -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ski Apex \(f.string(from: day.start)).gpx")
        try document(day).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func title(_ day: SkiDay) -> String {
        let date = day.start.formatted(date: .abbreviated, time: .omitted)
        if let place = day.title { return "\(place) · \(date)" }
        return date
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// One line on the map: a run, a lift or the time between, with at most a few hundred points.
struct MapTrack: Identifiable {
    let id: Int
    let kind: SegmentKind
    let number: Int
    let coordinates: [CLLocationCoordinate2D]

    static func build(points: [TrackPoint], segments: [Segment], maxPoints: Int = 300) -> [MapTrack] {
        guard !points.isEmpty else { return [] }
        // Before the first stretch is long enough to count, the whole track as it is.
        let parts = segments.isEmpty
            ? [Segment(kind: .idle, start: 0, end: points.count - 1, startTime: points[0].t, endTime: points[points.count - 1].t,
                       distance: 0, drop: 0, gain: 0, maxSpeed: 0, avgSpeed: 0, topAlt: 0, bottomAlt: 0, number: 0)]
            : segments
        return parts.compactMap { seg in
            guard seg.end > seg.start, seg.end < points.count else { return nil }
            let count = seg.end - seg.start + 1
            let step = max(1, count / maxPoints)
            var coords: [CLLocationCoordinate2D] = []
            coords.reserveCapacity(count / step + 2)
            var i = seg.start
            while i <= seg.end {
                coords.append(points[i].coordinate)
                i += step
            }
            if (seg.end - seg.start) % step != 0 { coords.append(points[seg.end].coordinate) }
            return MapTrack(id: seg.start, kind: seg.kind, number: seg.number, coordinates: coords)
        }
    }
}
