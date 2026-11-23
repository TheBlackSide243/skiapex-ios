import Foundation
import Observation

/// The pistes of the ski areas, kept: in memory once asked for, and on the iPhone for the ones
/// downloaded, which are there with no signal. The map under them is still Apple's, which
/// keeps only the parts it has already shown.
@Observable final class Terrains {
    static let shared = Terrains()

    /// A ski area downloaded: what the list in Settings shows.
    struct Saved: Codable, Identifiable, Hashable {
        var id: String
        var name: String
        var lat: Double
        var lon: Double
        var date: Date
        var pistes: Int
        var lifts: Int
    }

    private(set) var saved: [Saved] = []
    @ObservationIgnored private var memory: [String: Terrain] = [:]
    private let dir: URL
    private var index: URL { dir.appendingPathComponent("indice.json") }

    init(directory: URL? = nil) {
        dir = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mappe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: index), let list = try? JSONDecoder().decode([Saved].self, from: data) { saved = list }
    }

    // MARK: A line as it is written to a file

    private struct StoredWay: Codable {
        var piste: Bool
        var name: String?
        var ref: String?
        var difficulty: String?
        var lats: [Double]
        var lons: [Double]
        var lift: String?
        var id: Int64
        var startAlt: Double?
        var endAlt: Double?
    }

    private struct Stored: Codable {
        var ways: [StoredWay]
        var huts: [Hut]
    }

    static func encode(_ terrain: Terrain) throws -> Data {
        let ways = terrain.ways.map {
            StoredWay(piste: $0.kind == .piste, name: $0.name, ref: $0.ref, difficulty: $0.difficulty, lats: $0.lats, lons: $0.lons,
                      lift: $0.lift, id: $0.id, startAlt: $0.startAlt, endAlt: $0.endAlt)
        }
        return try JSONEncoder().encode(Stored(ways: ways, huts: terrain.huts))
    }

    static func decode(_ data: Data) throws -> Terrain {
        let stored = try JSONDecoder().decode(Stored.self, from: data)
        var terrain = Terrain()
        terrain.huts = stored.huts
        terrain.ways = stored.ways.compactMap { s in
            guard var way = OSMWay(kind: s.piste ? .piste : .lift, name: s.name, ref: s.ref, difficulty: s.difficulty, lats: s.lats,
                                   lons: s.lons, lift: s.lift, id: s.id) else { return nil }
            way.startAlt = s.startAlt
            way.endAlt = s.endAlt
            return way
        }
        return terrain
    }

    // MARK: Asking

    private static func key(_ lat: Double, _ lon: Double) -> String { String(format: "%.2f,%.2f", lat, lon) }

    /// The ski area downloaded that a place is in, if any: within the square each one covers.
    func savedMap(lat: Double, lon: Double) -> Saved? {
        saved.filter { Geo.distance(lat1: $0.lat, lon1: $0.lon, lat2: lat, lon2: lon) < 5000 }
            .min { Geo.distance(lat1: $0.lat, lon1: $0.lon, lat2: lat, lon2: lon) < Geo.distance(lat1: $1.lat, lon1: $1.lon, lat2: lat, lon2: lon) }
    }

    private func file(_ id: String) -> URL {
        dir.appendingPathComponent(id.filter { $0.isLetter || $0.isNumber || $0 == "-" } + ".json")
    }

    /// The pistes around a place without asking the internet: the ones downloaded, or the ones
    /// asked for a moment ago.
    func known(lat: Double, lon: Double) -> Terrain? {
        if let kept = memory[Self.key(lat, lon)] { return kept }
        guard let map = savedMap(lat: lat, lon: lon) else { return nil }
        if let kept = memory[map.id] { return kept }
        guard let data = try? Data(contentsOf: file(map.id)), let terrain = try? Self.decode(data) else { return nil }
        memory[map.id] = terrain
        return terrain
    }

    /// The pistes around a place: the ones here already, or from OpenStreetMap.
    func terrain(lat: Double, lon: Double) async throws -> Terrain {
        if let kept = known(lat: lat, lon: lon) { return kept }
        let loaded = try await Terrain.load(lat: lat, lon: lon)
        await MainActor.run { memory[Self.key(lat, lon)] = loaded }
        return loaded
    }

    // MARK: Downloading

    func isSaved(_ id: String) -> Bool { saved.contains { $0.id == id } }

    /// Keeps the pistes of a ski area on the iPhone.
    func save(_ terrain: Terrain, id: String, name: String, lat: Double, lon: Double) throws {
        try Self.encode(terrain).write(to: file(id), options: .atomic)
        saved.removeAll { $0.id == id }
        saved.append(Saved(id: id, name: name, lat: lat, lon: lon, date: Date(), pistes: terrain.pistes, lifts: terrain.lifts))
        saved.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        memory[id] = terrain
        writeIndex()
    }

    func remove(_ id: String) {
        try? FileManager.default.removeItem(at: file(id))
        saved.removeAll { $0.id == id }
        memory[id] = nil
        writeIndex()
    }

    private func writeIndex() {
        if let data = try? JSONEncoder().encode(saved) { try? data.write(to: index, options: .atomic) }
    }
}
