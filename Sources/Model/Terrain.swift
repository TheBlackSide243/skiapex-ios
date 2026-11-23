import Foundation

/// A place to eat or to warm up by the pistes.
struct Hut: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let lat: Double
    let lon: Double
}

/// The pistes, the lifts and the huts of a ski area, from OpenStreetMap, with the altitude of the
/// two ends of each line (Open-Meteo): it tells which way a piste goes down and a lift goes up.
struct Terrain {
    var ways: [OSMWay] = []
    var huts: [Hut] = []

    var pistes: Int { ways.filter { $0.kind == .piste }.count }
    var lifts: Int { ways.filter { $0.kind == .lift }.count }
    var pisteMeters: Double { ways.filter { $0.kind == .piste }.reduce(0) { $0 + $1.meters } }

    /// The line closest to a point, within `meters`: its place in `ways`.
    func nearest(lat: Double, lon: Double, within meters: Double, where wanted: (OSMWay) -> Bool = { _ in true }) -> Int? {
        var best: Int?
        var bestDistance = meters
        for (i, way) in ways.enumerated() where wanted(way) && way.mayBeNear(lat: lat, lon: lon, meters: meters) {
            let d = way.distance(lat: lat, lon: lon)
            if d < bestDistance {
                best = i
                bestDistance = d
            }
        }
        return best
    }

    // MARK: From the internet

    /// Half the side of the square asked for, in degrees of latitude: about 5.5 km.
    static let reach = 0.05

    static func query(lat: Double, lon: Double) -> String {
        let dLon = reach / max(0.3, cos(lat * .pi / 180))
        let box = String(format: "%.5f,%.5f,%.5f,%.5f", lat - reach, lon - dLon, lat + reach, lon + dLon)
        return """
        [out:json][timeout:40];
        (way["piste:type"="downhill"](\(box));way["aerialway"](\(box)););
        out tags geom;
        (nwr["tourism"="alpine_hut"]["name"](\(box));nwr["amenity"~"^(restaurant|cafe|bar|pub|fast_food)$"]["name"](\(box)););
        out tags center 600;
        """
    }

    /// The pistes, lifts and huts around a place. The altitudes are asked for too; without them
    /// the lines keep the direction they were drawn in.
    static func load(lat: Double, lon: Double) async throws -> Terrain {
        let data = try await Pistes.ask(query(lat: lat, lon: lon))
        var terrain = Terrain()
        terrain.ways = try Pistes.parse(data).ways.filter { $0.lats.count >= 2 }
        terrain.huts = parseHuts(data, near: terrain.ways)
        if let heights = try? await altitudes(ofEndsOf: terrain.ways) {
            apply(heights, to: &terrain.ways)
        }
        return terrain
    }

    /// The huts and restaurants of an Overpass answer that are by a piste or a lift.
    static func parseHuts(_ data: Data, near ways: [OSMWay], within meters: Double = 120, limit: Int = 60) -> [Hut] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = root["elements"] as? [[String: Any]] else { return [] }
        var out: [Hut] = []
        for element in elements where element["geometry"] == nil {
            guard let tags = element["tags"] as? [String: String], let name = tags["name"], !name.isEmpty,
                  tags["tourism"] == "alpine_hut" || tags["amenity"] != nil else { continue }
            let center = element["center"] as? [String: Any]
            guard let lat = ((center?["lat"] ?? element["lat"]) as? NSNumber)?.doubleValue,
                  let lon = ((center?["lon"] ?? element["lon"]) as? NSNumber)?.doubleValue else { continue }
            guard ways.contains(where: { $0.mayBeNear(lat: lat, lon: lon, meters: meters) && $0.distance(lat: lat, lon: lon) <= meters }) else { continue }
            let kind = element["type"] as? String ?? "?"
            let number = (element["id"] as? NSNumber)?.stringValue ?? "\(lat),\(lon)"
            if !out.contains(where: { $0.name == name && Geo.distance(lat1: $0.lat, lon1: $0.lon, lat2: lat, lon2: lon) < 80 }) {
                out.append(Hut(id: kind + number, name: name, lat: lat, lon: lon))
            }
            if out.count >= limit { break }
        }
        return out
    }

    // MARK: Altitudes

    /// The altitude of the first and of the last point of each line, in the order of the lines:
    /// two numbers each. Open-Meteo answers a hundred points at a time.
    static func altitudes(ofEndsOf ways: [OSMWay]) async throws -> [Double] {
        var lats: [Double] = [], lons: [Double] = []
        for way in ways {
            lats.append(way.lats[0])
            lons.append(way.lons[0])
            lats.append(way.lats[way.lats.count - 1])
            lons.append(way.lons[way.lons.count - 1])
        }
        var out: [Double] = []
        var i = 0
        while i < lats.count {
            let end = min(i + 100, lats.count)
            var parts = URLComponents(string: "https://api.open-meteo.com/v1/elevation")!
            parts.queryItems = [
                URLQueryItem(name: "latitude", value: lats[i..<end].map { String(format: "%.5f", $0) }.joined(separator: ",")),
                URLQueryItem(name: "longitude", value: lons[i..<end].map { String(format: "%.5f", $0) }.joined(separator: ",")),
            ]
            guard let url = parts.url else { throw URLError(.badURL) }
            var request = URLRequest(url: url, timeoutInterval: 30)
            request.setValue("SkiApex iOS app", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let part = try parseAltitudes(data)
            guard part.count == end - i else { throw URLError(.cannotParseResponse) }
            out += part
            i = end
        }
        return out
    }

    static func parseAltitudes(_ data: Data) throws -> [Double] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["elevation"] as? [Any] else { throw URLError(.cannotParseResponse) }
        return list.map { ($0 as? NSNumber)?.doubleValue ?? 0 }
    }

    /// Gives each line the altitude of its ends, and turns around the ones drawn against the
    /// way they are used: a piste starts at the top, a lift at the bottom.
    static func apply(_ altitudes: [Double], to ways: inout [OSMWay]) {
        guard altitudes.count == ways.count * 2 else { return }
        for i in ways.indices {
            ways[i].startAlt = altitudes[i * 2]
            ways[i].endAlt = altitudes[i * 2 + 1]
            let rise = altitudes[i * 2 + 1] - altitudes[i * 2]
            switch ways[i].kind {
            case .piste:
                if rise > 5 { ways[i] = ways[i].reversed() }
            case .lift:
                if rise < -5, !ways[i].bothWays { ways[i] = ways[i].reversed() }
            }
        }
    }

    // MARK: For the pictures

    /// A made-up ski area around a place: three lifts from a village and the pistes back down.
    static func demo(lat: Double, lon: Double) -> Terrain {
        let kx = 111_320 * cos(lat * .pi / 180), ky = 111_320.0
        func line(_ points: [(Double, Double)], wiggle: Double = 0) -> (lats: [Double], lons: [Double]) {
            // Each stretch in ten steps, swaying from side to side like a piste.
            var lats: [Double] = [], lons: [Double] = []
            for i in 0..<(points.count - 1) {
                let a = points[i], b = points[i + 1]
                let len = max(1, hypot(b.0 - a.0, b.1 - a.1))
                for k in 0..<10 {
                    let t = Double(k) / 10
                    let sway = wiggle * sin(Double(i * 10 + k) * 0.9)
                    let x = a.0 + (b.0 - a.0) * t - (b.1 - a.1) / len * sway
                    let y = a.1 + (b.1 - a.1) * t + (b.0 - a.0) / len * sway
                    lats.append(lat + y / ky)
                    lons.append(lon + x / kx)
                }
            }
            if let last = points.last {
                lats.append(lat + last.1 / ky)
                lons.append(lon + last.0 / kx)
            }
            return (lats, lons)
        }
        // Meters east and north of the village; the altitude grows with the north.
        let village = (0.0, -1400.0), west = (-1700.0, 900.0), top = (100.0, 1900.0), east = (1900.0, 700.0), middle = (300.0, 300.0)
        func alt(_ p: (Double, Double)) -> Double { 2050 + (p.1 + 1400) * 0.33 }
        var ways: [OSMWay] = []
        func add(_ kind: OSMWay.Kind, _ name: String, _ difficulty: String?, _ lift: String?, _ points: [(Double, Double)], wiggle: Double = 0) {
            let made = line(points, wiggle: wiggle)
            guard var way = OSMWay(kind: kind, name: name, ref: nil, difficulty: difficulty, lats: made.lats, lons: made.lons,
                                   lift: lift, id: Int64(ways.count + 1)) else { return }
            way.startAlt = alt(points[0])
            way.endAlt = alt(points[points.count - 1])
            ways.append(way)
        }
        add(.lift, "Cabinovia Cima Bianca", nil, "gondola", [village, middle, top])
        add(.lift, "Seggiovia Gran Bosco", nil, "chair_lift", [village, west])
        add(.lift, "Seggiovia del Sole", nil, "chair_lift", [middle, east])
        add(.piste, "Pista del Sole", "easy", nil, [east, (1300, -200), (600, -900), village], wiggle: 70)
        add(.piste, "Gran Bosco", "intermediate", nil, [west, (-1200, 0), (-600, -800), village], wiggle: 60)
        add(.piste, "Canalone", "advanced", nil, [top, (-500, 1500), (-1100, 1200), west], wiggle: 45)
        add(.piste, "Ventina", "intermediate", nil, [top, (800, 1500), (1500, 1100), east], wiggle: 60)
        add(.piste, "Campetto", "novice", nil, [middle, (150, -500), village], wiggle: 30)
        add(.piste, "Variante", "easy", nil, [east, (1000, 500), middle], wiggle: 50)
        let huts = [
            Hut(id: "demo1", name: "Rifugio Cima Bianca", lat: lat + (top.1 - 170) / ky, lon: lon + (top.0 + 260) / kx),
            Hut(id: "demo2", name: "Baita del Sole", lat: lat + (east.1 - 80) / ky, lon: lon + (east.0 - 60) / kx),
            Hut(id: "demo3", name: "Bar Gran Bosco", lat: lat + (west.1 - 70) / ky, lon: lon + (west.0 + 70) / kx),
        ]
        return Terrain(ways: ways, huts: huts)
    }
}
