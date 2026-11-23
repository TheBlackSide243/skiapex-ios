import Foundation

/// The way from one point of a ski area to another: down the pistes, up the lifts.
struct Route {
    /// One piste or one lift of the way.
    struct Step: Identifiable {
        let id: Int
        let kind: OSMWay.Kind
        let label: String?
        let difficulty: String?
        var meters: Double
        var seconds: Double
    }

    var steps: [Step] = []
    /// The line to draw.
    var lats: [Double] = []
    var lons: [Double] = []
    var meters = 0.0
    /// A guess: the pistes at an easy pace, the lifts with a short wait.
    var seconds = 0.0
}

/// The pistes a route may take: up to the blue ones, up to the red ones, or all.
enum RouteLevel: Int, CaseIterable, Identifiable {
    case easy, medium, all

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .easy: "Blu"
        case .medium: "Rosse"
        case .all: "Tutte"
        }
    }

    func allows(_ difficulty: String?) -> Bool {
        switch difficulty {
        case "intermediate": self != .easy
        case "advanced", "expert", "freeride", "extreme": self == .all
        default: true
        }
    }
}

/// The pistes and lifts of a ski area as a net of points to go through: a piste is followed
/// downhill from any of its points to any below, a lift from its bottom to its top (a gondola
/// both ways), and where two lines meet or come close one can pass from one to the other.
final class RouteGraph {
    private struct Edge {
        let to: Int32
        let seconds: Float
        let meters: Float
        /// The line followed, or -1 for the few steps between two lines.
        let way: Int32
    }

    private let ways: [OSMWay]
    private var lat: [Double] = []
    private var lon: [Double] = []
    private var wayOf: [Int32] = []
    /// One can get on the line here / get off it here.
    private var canStart: [Bool] = []
    private var canEnd: [Bool] = []
    private var edges: [[Edge]] = []

    /// Points of a piste are at most this far apart, so that two pistes that cross are found close.
    static let spacing = 25.0
    /// Two pistes this close are one way; a lift's station is reached from a little farther.
    static let pisteLink = 30.0
    static let liftLink = 80.0
    /// Getting on a lift: the queue and the gate.
    static let boarding = 120.0

    static func pisteSpeed(_ difficulty: String?) -> Double {
        switch difficulty {
        case "novice": 5
        case "easy": 7
        case "intermediate": 8
        case "advanced": 7.5
        case "expert": 7
        case "freeride", "extreme": 5
        default: 6.5
        }
    }

    static func liftSpeed(_ lift: String?) -> Double {
        switch lift {
        case "chair_lift": 2.6
        case "gondola", "mixed_lift": 5
        case "cable_car": 8
        case "funicular": 7
        case "magic_carpet": 0.7
        case "drag_lift", "t-bar", "j-bar", "platter", "rope_tow": 2.8
        default: 3
        }
    }

    var isEmpty: Bool { lat.isEmpty }

    init(ways: [OSMWay]) {
        self.ways = ways
        for (w, way) in ways.enumerated() where way.lats.count >= 2 {
            switch way.kind {
            case .piste:
                let dense = Self.dense(way)
                let first = lat.count
                for i in dense.lats.indices { add(dense.lats[i], dense.lons[i], way: w, start: true, end: true) }
                let speed = Self.pisteSpeed(way.difficulty)
                for i in 0..<(dense.lats.count - 1) {
                    let d = Geo.distance(lat1: dense.lats[i], lon1: dense.lons[i], lat2: dense.lats[i + 1], lon2: dense.lons[i + 1])
                    edges[first + i].append(Edge(to: Int32(first + i + 1), seconds: Float(d / speed), meters: Float(d), way: Int32(w)))
                }
            case .lift:
                let last = way.lats.count - 1
                let bottom = add(way.lats[0], way.lons[0], way: w, start: true, end: way.bothWays)
                let top = add(way.lats[last], way.lons[last], way: w, start: way.bothWays, end: true)
                let seconds = Float(way.meters / Self.liftSpeed(way.lift) + Self.boarding)
                edges[bottom].append(Edge(to: Int32(top), seconds: seconds, meters: Float(way.meters), way: Int32(w)))
                if way.bothWays {
                    edges[top].append(Edge(to: Int32(bottom), seconds: seconds, meters: Float(way.meters), way: Int32(w)))
                }
            }
        }
        link()
    }

    @discardableResult private func add(_ la: Double, _ lo: Double, way: Int, start: Bool, end: Bool) -> Int {
        lat.append(la)
        lon.append(lo)
        wayOf.append(Int32(way))
        canStart.append(start)
        canEnd.append(end)
        edges.append([])
        return lat.count - 1
    }

    /// The points of a piste with more in between, where they are far apart.
    private static func dense(_ way: OSMWay) -> (lats: [Double], lons: [Double]) {
        var lats = [way.lats[0]], lons = [way.lons[0]]
        for i in 1..<way.lats.count {
            let d = Geo.distance(lat1: way.lats[i - 1], lon1: way.lons[i - 1], lat2: way.lats[i], lon2: way.lons[i])
            let pieces = max(1, Int((d / spacing).rounded(.up)))
            for k in 1...pieces {
                let t = Double(k) / Double(pieces)
                lats.append(way.lats[i - 1] + (way.lats[i] - way.lats[i - 1]) * t)
                lons.append(way.lons[i - 1] + (way.lons[i] - way.lons[i - 1]) * t)
            }
        }
        return (lats, lons)
    }

    /// The few steps from one line to another, where they are close: found with a grid.
    private func link() {
        guard let lat0 = lat.first, let lon0 = lon.first else { return }
        let kx = 111_320 * cos(lat0 * .pi / 180), ky = 111_320.0
        let cell = Self.liftLink
        let xs = lon.map { ($0 - lon0) * kx }, ys = lat.map { ($0 - lat0) * ky }
        func key(_ cx: Int, _ cy: Int) -> Int { cx &* 1_000_003 &+ cy }
        var grid: [Int: [Int32]] = [:]
        for i in lat.indices {
            grid[key(Int((xs[i] / cell).rounded(.down)), Int((ys[i] / cell).rounded(.down))), default: []].append(Int32(i))
        }
        for a in lat.indices where canEnd[a] {
            let cx = Int((xs[a] / cell).rounded(.down)), cy = Int((ys[a] / cell).rounded(.down))
            let aIsPiste = ways[Int(wayOf[a])].kind == .piste
            for dx in -1...1 {
                for dy in -1...1 {
                    guard let near = grid[key(cx + dx, cy + dy)] else { continue }
                    for b32 in near {
                        let b = Int(b32)
                        guard wayOf[b] != wayOf[a], canStart[b] else { continue }
                        let d = hypot(xs[a] - xs[b], ys[a] - ys[b])
                        let bIsPiste = ways[Int(wayOf[b])].kind == .piste
                        guard d <= (aIsPiste && bIsPiste ? Self.pisteLink : Self.liftLink) else { continue }
                        // On foot or pushing: slow, and a moment to look around.
                        edges[a].append(Edge(to: b32, seconds: Float(d / 1.2 + 3), meters: Float(d), way: -1))
                    }
                }
            }
        }
    }

    /// The point of the net closest to a place, among the ones one can get on (or off) at.
    private func nearest(lat la: Double, lon lo: Double, start: Bool, blocked: [Bool], within meters: Double) -> Int? {
        var best: Int?
        var bestDistance = meters
        let kx = 111_320 * cos(la * .pi / 180), ky = 111_320.0
        for i in lat.indices where (start ? canStart[i] : canEnd[i]) && !blocked[Int(wayOf[i])] {
            let d = hypot((lon[i] - lo) * kx, (lat[i] - la) * ky)
            if d < bestDistance {
                best = i
                bestDistance = d
            }
        }
        return best
    }

    /// The quickest way between two places, taking only the pistes `level` allows. nil when
    /// there is none: a place far from every line, or a valley the lifts do not link.
    func route(fromLat: Double, fromLon: Double, toLat: Double, toLon: Double, level: RouteLevel = .all, snap: Double = 500) -> Route? {
        let blocked = ways.map { $0.kind == .piste && !level.allows($0.difficulty) }
        guard let start = nearest(lat: fromLat, lon: fromLon, start: true, blocked: blocked, within: snap),
              let goal = nearest(lat: toLat, lon: toLon, start: false, blocked: blocked, within: snap) else { return nil }
        var best = [Float](repeating: .infinity, count: lat.count)
        var previous = [Int32](repeating: -1, count: lat.count)
        var arrivedBy = [Edge?](repeating: nil, count: lat.count)
        var heap = Heap()
        best[start] = 0
        heap.push(0, Int32(start))
        while let (cost, v32) = heap.pop() {
            let v = Int(v32)
            if cost > best[v] { continue }
            if v == goal { break }
            for edge in edges[v] {
                if edge.way >= 0, blocked[Int(edge.way)] { continue }
                let to = Int(edge.to)
                if edge.way < 0, blocked[Int(wayOf[to])] { continue }
                let next = cost + edge.seconds
                if next < best[to] {
                    best[to] = next
                    previous[to] = v32
                    arrivedBy[to] = edge
                    heap.push(next, edge.to)
                }
            }
        }
        guard best[goal].isFinite else { return nil }

        var path = [goal]
        while let last = path.last, last != start, previous[last] >= 0 { path.append(Int(previous[last])) }
        guard path.last == start else { return nil }
        path.reverse()

        var route = Route(lats: [lat[start]], lons: [lon[start]])
        for v in path.dropFirst() {
            guard let edge = arrivedBy[v] else { continue }
            route.seconds += Double(edge.seconds)
            route.meters += Double(edge.meters)
            guard edge.way >= 0 else {
                route.lats.append(lat[v])
                route.lons.append(lon[v])
                continue
            }
            let way = ways[Int(edge.way)]
            if way.kind == .lift {
                // The whole line of the lift, from the end it was taken at.
                let last = way.lats.count - 1
                let up = hypot(way.lats[last] - lat[v], way.lons[last] - lon[v]) <= hypot(way.lats[0] - lat[v], way.lons[0] - lon[v])
                route.lats += up ? way.lats : Array(way.lats.reversed())
                route.lons += up ? way.lons : Array(way.lons.reversed())
            } else {
                route.lats.append(lat[v])
                route.lons.append(lon[v])
            }
            // A piste drawn in more pieces with the same name is one step.
            if let k = route.steps.indices.last, route.steps[k].kind == way.kind, route.steps[k].label == way.label,
               way.label != nil || route.steps[k].id == Int(edge.way) {
                route.steps[k].meters += Double(edge.meters)
                route.steps[k].seconds += Double(edge.seconds)
            } else {
                route.steps.append(Route.Step(id: Int(edge.way), kind: way.kind, label: way.label, difficulty: way.difficulty,
                                              meters: Double(edge.meters), seconds: Double(edge.seconds)))
            }
        }
        return route
    }

    /// The smallest first: for the search.
    private struct Heap {
        private var items: [(Float, Int32)] = []

        mutating func push(_ cost: Float, _ vertex: Int32) {
            items.append((cost, vertex))
            var i = items.count - 1
            while i > 0 {
                let parent = (i - 1) / 2
                if items[parent].0 <= items[i].0 { break }
                items.swapAt(parent, i)
                i = parent
            }
        }

        mutating func pop() -> (Float, Int32)? {
            guard let first = items.first else { return nil }
            let last = items.removeLast()
            if !items.isEmpty {
                items[0] = last
                var i = 0
                while true {
                    let l = 2 * i + 1, r = l + 1
                    var smallest = i
                    if l < items.count, items[l].0 < items[smallest].0 { smallest = l }
                    if r < items.count, items[r].0 < items[smallest].0 { smallest = r }
                    if smallest == i { break }
                    items.swapAt(i, smallest)
                    i = smallest
                }
            }
            return first
        }
    }
}
