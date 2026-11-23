import Foundation

/// A piste or a lift of OpenStreetMap, as a line on the ground.
struct OSMWay {
    enum Kind { case piste, lift }

    let kind: Kind
    let name: String?
    let ref: String?
    let difficulty: String?
    let lats: [Double]
    let lons: [Double]
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double

    init?(kind: Kind, name: String?, ref: String?, difficulty: String?, lats: [Double], lons: [Double]) {
        guard !lats.isEmpty, lats.count == lons.count,
              let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() else { return nil }
        self.kind = kind
        self.name = name
        self.ref = ref
        self.difficulty = difficulty
        self.lats = lats
        self.lons = lons
        self.minLat = minLat
        self.maxLat = maxLat
        self.minLon = minLon
        self.maxLon = maxLon
    }

    /// What it is called: its name, or its number.
    var label: String? {
        if let name, !name.isEmpty { return name }
        if let ref, !ref.isEmpty { return kind == .piste ? String(localized: "Pista \(ref)") : ref }
        return nil
    }

    /// Whether a point can be within `meters` of it, from its box alone.
    func mayBeNear(lat: Double, lon: Double, meters: Double) -> Bool {
        let dLat = meters / 111_320, dLon = meters / (111_320 * max(0.2, cos(lat * .pi / 180)))
        return lat >= minLat - dLat && lat <= maxLat + dLat && lon >= minLon - dLon && lon <= maxLon + dLon
    }

    /// Meters from a point to the nearest part of the line.
    func distance(lat: Double, lon: Double) -> Double {
        let kx = 111_320 * cos(lat * .pi / 180), ky = 111_320.0
        var ax = (lons[0] - lon) * kx, ay = (lats[0] - lat) * ky
        var best = hypot(ax, ay)
        guard lats.count > 1 else { return best }
        for i in 1..<lats.count {
            let bx = (lons[i] - lon) * kx, by = (lats[i] - lat) * ky
            let dx = bx - ax, dy = by - ay
            let len2 = dx * dx + dy * dy
            let t = len2 > 0 ? max(0, min(1, -(ax * dx + ay * dy) / len2)) : 0
            best = min(best, hypot(ax + t * dx, ay + t * dy))
            ax = bx
            ay = by
        }
        return best
    }
}

/// The pistes and lifts around a day, and the ski areas they belong to.
struct ResortMap {
    struct Area {
        let name: String
        let lat: Double
        let lon: Double
    }

    var ways: [OSMWay] = []
    var areas: [Area] = []
}

/// The names of the pistes and of the lifts of a day, from OpenStreetMap (Overpass API): each run
/// takes the name of the piste its points are closest to, each lift the name of its line.
enum Pistes {
    static let servers = [
        URL(string: "https://overpass-api.de/api/interpreter")!,
        URL(string: "https://overpass.kumi.systems/api/interpreter")!,
    ]

    /// The Overpass question for the box around the points, with 300 m to spare.
    static func query(for points: [TrackPoint]) -> String? {
        guard let minLat = points.map(\.lat).min(), let maxLat = points.map(\.lat).max(),
              let minLon = points.map(\.lon).min(), let maxLon = points.map(\.lon).max() else { return nil }
        let pad = 0.003
        let box = String(format: "%.5f,%.5f,%.5f,%.5f", minLat - pad, minLon - pad * 1.4, maxLat + pad, maxLon + pad * 1.4)
        return """
        [out:json][timeout:30];
        (way["piste:type"="downhill"](\(box));way["aerialway"](\(box)););
        out tags geom;
        (relation["site"="piste"](\(box));nwr["landuse"="winter_sports"](\(box)););
        out tags center;
        """
    }

    static func fetch(around points: [TrackPoint]) async throws -> ResortMap {
        guard let query = query(for: points) else { return ResortMap() }
        var last: Error = URLError(.badServerResponse)
        for server in servers {
            var request = URLRequest(url: server, timeoutInterval: 45)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.setValue("SkiApex iOS app", forHTTPHeaderField: "User-Agent")
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            request.httpBody = Data(("data=" + encoded).utf8)
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                return try parse(data)
            } catch {
                last = error
            }
        }
        throw last
    }

    static func parse(_ data: Data) throws -> ResortMap {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = root["elements"] as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
        var map = ResortMap()
        for element in elements {
            let tags = element["tags"] as? [String: String] ?? [:]
            if let geometry = element["geometry"] as? [[String: Any]] {
                let lats = geometry.compactMap { $0["lat"] as? Double }
                let lons = geometry.compactMap { $0["lon"] as? Double }
                guard lats.count == geometry.count, lons.count == geometry.count else { continue }
                var kind: OSMWay.Kind?
                if tags["piste:type"] == "downhill" {
                    // A piste drawn as an area has no line to follow.
                    if tags["area"] != "yes" { kind = .piste }
                } else if let aerialway = tags["aerialway"], !["station", "pylon", "goods", "zip_line"].contains(aerialway) {
                    kind = .lift
                }
                if let kind, let way = OSMWay(kind: kind, name: tags["name"], ref: tags["piste:ref"] ?? tags["ref"],
                                              difficulty: tags["piste:difficulty"], lats: lats, lons: lons) {
                    map.ways.append(way)
                }
            } else if tags["site"] == "piste" || tags["landuse"] == "winter_sports", let name = tags["name"], !name.isEmpty {
                let center = element["center"] as? [String: Any]
                if let lat = (center?["lat"] ?? element["lat"]) as? Double, let lon = (center?["lon"] ?? element["lon"]) as? Double {
                    map.areas.append(ResortMap.Area(name: name, lat: lat, lon: lon))
                }
            }
        }
        return map
    }

    /// Gives the runs and the lifts of the day their names, and the day its ski area.
    static func apply(_ map: ResortMap, to day: inout SkiDay) {
        let pistes = map.ways.filter { $0.kind == .piste }
        let lifts = map.ways.filter { $0.kind == .lift }
        for i in day.segments.indices {
            let segment = day.segments[i]
            guard segment.start <= segment.end, segment.end < day.points.count else { continue }
            let points = day.points[segment.start...segment.end]
            switch segment.kind {
            case .run:
                let found = match(points, among: pistes, within: 40)
                day.segments[i].name = found.label
                day.segments[i].difficulty = found.difficulty
            case .lift:
                day.segments[i].name = match(points, among: lifts, within: 60).label
            case .idle:
                break
            }
        }
        if !day.points.isEmpty, !map.areas.isEmpty {
            let lat = day.points.map(\.lat).reduce(0, +) / Double(day.points.count)
            let lon = day.points.map(\.lon).reduce(0, +) / Double(day.points.count)
            day.resort = map.areas.min {
                Geo.distance(lat1: lat, lon1: lon, lat2: $0.lat, lon2: $0.lon) < Geo.distance(lat1: lat, lon1: lon, lat2: $1.lat, lon2: $1.lon)
            }?.name
        }
    }

    /// The lines a stretch followed: up to three names in the order they were met, each for at
    /// least a fifth of the way, and the difficulty met most.
    static func match(_ points: ArraySlice<TrackPoint>, among ways: [OSMWay], within meters: Double) -> (label: String?, difficulty: String?) {
        guard !points.isEmpty, !ways.isEmpty else { return (nil, nil) }
        let step = max(1, points.count / 40)
        var order: [String] = []
        var votes: [String: Int] = [:]
        var grades: [String: Int] = [:]
        var samples = 0
        var i = points.startIndex
        while i < points.endIndex {
            let p = points[i]
            samples += 1
            var best: OSMWay?
            var bestDistance = meters
            for way in ways where way.mayBeNear(lat: p.lat, lon: p.lon, meters: meters) {
                let d = way.distance(lat: p.lat, lon: p.lon)
                // Between two lines as close, the one with a name.
                if d < bestDistance - 3 || (d < bestDistance && (best?.label == nil || way.label != nil)) {
                    best = way
                    bestDistance = min(d, bestDistance)
                }
            }
            if let best {
                if let label = best.label {
                    if votes[label] == nil { order.append(label) }
                    votes[label, default: 0] += 1
                }
                if let grade = best.difficulty { grades[grade, default: 0] += 1 }
            }
            i += step
        }
        let enough = max(2, samples / 5)
        let names = order.filter { votes[$0, default: 0] >= enough }.prefix(3)
        let grade = grades.max { $0.value < $1.value }
        return (names.isEmpty ? nil : names.joined(separator: " · "),
                (grade?.value ?? 0) >= max(2, samples * 3 / 10) ? grade?.key : nil)
    }
}
