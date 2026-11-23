import MapKit
import SwiftUI

/// The map of a ski area: its pistes in the colors of the signs, its lifts and its huts, from
/// OpenStreetMap. Touch a piste or a lift to see what it is, and to set where you leave from and
/// where you want to get: the way is found along the pistes and the lifts.
struct ExploreView: View {
    let name: String
    let center: CLLocationCoordinate2D

    @Environment(Recorder.self) private var recorder
    @AppStorage(Prefs.mapLook) private var mapLook = MapLook.standard.rawValue
    @State private var camera: MapCameraPosition
    @State private var terrain: Terrain?
    @State private var graph: RouteGraph?
    @State private var loading = false
    @State private var failed = false
    @State private var showPistes = true
    @State private var showLifts = true
    @State private var showHuts = true
    /// The line touched: its place in `terrain.ways`, and where it was touched.
    @State private var picked: Int?
    @State private var pickedAt: CLLocationCoordinate2D?
    @State private var from: CLLocationCoordinate2D?
    @State private var to: CLLocationCoordinate2D?
    @State private var level = RouteLevel.all
    @State private var route: Route?
    @State private var noRoute = false

    init(name: String, center: CLLocationCoordinate2D) {
        self.name = name
        self.center = center
        _camera = State(initialValue: .region(MKCoordinateRegion(center: center, latitudinalMeters: 6500, longitudinalMeters: 6500)))
    }

    private var look: MapLook { MapLook(rawValue: mapLook) ?? .standard }

    /// A line of the map, ready to be drawn.
    private struct Line: Identifiable {
        let id: Int
        let coordinates: [CLLocationCoordinate2D]
        let color: Color
        let style: StrokeStyle
    }

    var body: some View {
        let drawn = lines()
        ZStack(alignment: .bottom) {
            MapReader { proxy in
                Map(position: $camera) {
                    ForEach(drawn) { line in
                        MapPolyline(coordinates: line.coordinates).stroke(line.color, style: line.style)
                    }
                    if showHuts, let terrain {
                        ForEach(terrain.huts) { hut in
                            Annotation(hut.name, coordinate: CLLocationCoordinate2D(latitude: hut.lat, longitude: hut.lon)) {
                                Image(systemName: "fork.knife")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Theme.onAccent)
                                    .frame(width: 22, height: 22)
                                    .background(Theme.warn, in: Circle())
                            }
                        }
                    }
                    if let from {
                        Annotation("Partenza", coordinate: from) { EndDot(symbol: "figure.skiing.downhill", color: Theme.good) }
                    }
                    if let to {
                        Annotation("Arrivo", coordinate: to) { EndDot(symbol: "flag.checkered", color: Theme.accent) }
                    }
                    UserAnnotation()
                }
                .mapStyle(look.style)
                .onTapGesture { point in
                    if let place = proxy.convert(point, from: .local) { touch(place) }
                }
            }
            .ignoresSafeArea(edges: .bottom)

            panel
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
        .overlay(alignment: .top) { layers.padding(.top, 8) }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task { await load() }
        .onChange(of: level) { _, _ in findRoute() }
    }

    // MARK: The map

    private func lines() -> [Line] {
        guard let terrain else { return [] }
        var out: [Line] = []
        let round = StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
        for (i, way) in terrain.ways.enumerated() {
            let coordinates = zip(way.lats, way.lons).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) }
            let chosen = picked == i
            switch way.kind {
            case .piste:
                guard showPistes else { continue }
                let color = Theme.difficultyColor(way.difficulty) ?? Theme.sub
                // A black piste on a dark map is seen by its light edge.
                if ["advanced", "expert"].contains(way.difficulty ?? "") {
                    out.append(Line(id: -i - 1, coordinates: coordinates, color: Color.white.opacity(0.8),
                                    style: StrokeStyle(lineWidth: chosen ? 8 : 5.5, lineCap: .round, lineJoin: .round)))
                }
                out.append(Line(id: i, coordinates: coordinates, color: color,
                                style: chosen ? StrokeStyle(lineWidth: 6.5, lineCap: .round, lineJoin: .round) : round))
            case .lift:
                guard showLifts else { continue }
                out.append(Line(id: i, coordinates: coordinates, color: Theme.lift,
                                style: StrokeStyle(lineWidth: chosen ? 5 : 2.5, lineCap: .round, lineJoin: .round, dash: [7, 6])))
            }
        }
        if let route, route.lats.count >= 2 {
            let coordinates = zip(route.lats, route.lons).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) }
            out.append(Line(id: 1_000_000, coordinates: coordinates, color: Theme.deep.opacity(0.85),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round)))
            out.append(Line(id: 1_000_001, coordinates: coordinates, color: Theme.accent,
                            style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round)))
        }
        return out
    }

    /// What to show, on glass at the top.
    private var layers: some View {
        HStack(spacing: 8) {
            LayerChip(title: "Piste", symbol: "figure.skiing.downhill", on: $showPistes)
            LayerChip(title: "Impianti", symbol: "cablecar", on: $showLifts)
            LayerChip(title: "Rifugi", symbol: "fork.knife", on: $showHuts)
        }
    }

    // MARK: The panel

    @ViewBuilder private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if loading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Cerco piste e impianti…").font(.subheadline).foregroundStyle(Theme.text)
                }
            } else if failed {
                Text("Non riesco a scaricare le piste di questa zona. Controlla la connessione e riprova.")
                    .prose().font(.subheadline).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Button { Task { await load() } } label: { Label("Riprova", systemImage: "arrow.clockwise") }
                    .buttonStyle(SecondaryButtonStyle())
            } else if let terrain {
                if terrain.ways.isEmpty {
                    Text("Qui OpenStreetMap non ha piste o impianti.").prose().font(.subheadline).foregroundStyle(Theme.text)
                } else if let route {
                    routeSummary(route)
                } else if let picked, picked < terrain.ways.count {
                    wayCard(terrain.ways[picked])
                } else {
                    Text("\(terrain.pistes) piste · \(terrain.lifts) impianti · \(Fmt.distance(terrain.pisteMeters))")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    Text(hint).prose().font(.caption).foregroundStyle(Theme.sub)
                        .fixedSize(horizontal: false, vertical: true)
                    if from != nil || to != nil {
                        Button { clear() } label: { Label("Ricomincia", systemImage: "xmark") }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass()
    }

    private var hint: LocalizedStringKey {
        if noRoute { return "Non trovo un percorso tra questi due punti con le piste scelte. Tocca un'altra pista o un altro impianto." }
        if from != nil { return "Ora tocca la pista o l'impianto dove vuoi arrivare." }
        if to != nil { return "Ora tocca la pista o l'impianto da cui parti." }
        return "Tocca una pista o un impianto per vedere cos'è e per calcolare un percorso."
    }

    private func wayCard(_ way: OSMWay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if way.kind == .piste {
                    DifficultyDot(difficulty: way.difficulty, size: 12)
                } else {
                    Image(systemName: "cablecar").font(.footnote.weight(.semibold)).foregroundStyle(Theme.lift)
                }
                Text(way.label ?? Self.nameless(way.kind))
                    .font(.headline).foregroundStyle(Theme.text).lineLimit(2)
                Spacer(minLength: 6)
                Button { picked = nil } label: { Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(Theme.sub) }
                    .accessibilityLabel(Text("Chiudi"))
            }
            HStack(spacing: 8) {
                if way.kind == .piste, let label = Theme.difficultyLabel(way.difficulty) {
                    Chip(symbol: "flag", text: String(localized: String.LocalizationValue(label)))
                }
                Chip(symbol: "ruler", text: Fmt.distance(way.meters))
                if let drop = way.drop, drop >= 5 {
                    Chip(symbol: way.kind == .piste ? "arrow.down.right" : "arrow.up.right", text: Fmt.height(drop))
                }
            }
            HStack(spacing: 10) {
                Button { set(start: true) } label: { Label("Parto da qui", systemImage: "figure.skiing.downhill") }
                    .buttonStyle(SecondaryButtonStyle())
                Button { set(start: false) } label: { Label("Arrivo qui", systemImage: "flag.checkered") }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private func routeSummary(_ route: Route) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.duration(route.seconds)).font(.display(.title3)).foregroundStyle(Theme.text)
                Text("· \(Fmt.distance(route.meters))").font(.subheadline).foregroundStyle(Theme.sub)
                Spacer(minLength: 6)
                Button { clear() } label: { Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(Theme.sub) }
                    .accessibilityLabel(Text("Chiudi"))
            }
            Picker("Piste", selection: $level) {
                ForEach(RouteLevel.allCases) { Text(LocalizedStringKey($0.label)).tag($0) }
            }
            .pickerStyle(.segmented)
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(route.steps.enumerated()), id: \.offset) { _, step in
                        HStack(spacing: 9) {
                            if step.kind == .piste {
                                DifficultyDot(difficulty: step.difficulty, size: 11).frame(width: 18)
                            } else {
                                Image(systemName: "cablecar").font(.caption.weight(.semibold)).foregroundStyle(Theme.lift).frame(width: 18)
                            }
                            Text(step.label ?? Self.nameless(step.kind))
                                .font(.subheadline).foregroundStyle(Theme.text).lineLimit(1)
                            Spacer(minLength: 6)
                            Text(Fmt.duration(step.seconds)).font(.caption).monospacedDigit().foregroundStyle(Theme.sub)
                        }
                    }
                }
            }
            // As tall as its steps, up to five of them: then it scrolls.
            .frame(height: min(140, CGFloat(route.steps.count) * 28))
            Text("Tempi indicativi. Controlla sempre i cartelli e le piste aperte.")
                .prose().font(.caption2).foregroundStyle(Theme.sub)
        }
    }

    private static func nameless(_ kind: OSMWay.Kind) -> String {
        switch kind {
        case .piste: String(localized: "Pista senza nome")
        case .lift: String(localized: "Impianto senza nome")
        }
    }

    // MARK: What the touches do

    private func load() async {
        guard terrain == nil, !loading else { return }
        loading = true
        failed = false
        defer { loading = false }
        if Demo.isOn {
            show(Terrain.demo(lat: center.latitude, lon: center.longitude))
            // For the picture: from the top to the village, on the easy pistes.
            if let top = terrain?.ways.first(where: { $0.name == "Canalone" }), let low = terrain?.ways.first(where: { $0.name == "Gran Bosco" }) {
                from = CLLocationCoordinate2D(latitude: top.lats[0], longitude: top.lons[0])
                to = CLLocationCoordinate2D(latitude: low.lats[low.lats.count - 1], longitude: low.lons[low.lons.count - 1])
                level = .medium
                findRoute()
            }
            return
        }
        do {
            // The ones downloaded are here with no signal; the others come from OpenStreetMap.
            show(try await Terrains.shared.terrain(lat: center.latitude, lon: center.longitude))
        } catch {
            failed = true
        }
    }

    private func show(_ loaded: Terrain) {
        terrain = loaded
        graph = RouteGraph(ways: loaded.ways)
        bringInView(loaded.ways.flatMap(\.lats), loaded.ways.flatMap(\.lons))
    }

    /// Brings some points in view above the panel, which covers the lower part of the map.
    private func bringInView(_ lats: [Double], _ lons: [Double]) {
        guard let south = lats.min(), let north = lats.max(), let west = lons.min(), let east = lons.max() else { return }
        // The points take less than half the height, under the buttons at the top.
        let height = max(0.006, north - south) / 0.42
        let top = north + height * 0.17
        let center = CLLocationCoordinate2D(latitude: top - height / 2, longitude: (west + east) / 2)
        let span = MKCoordinateSpan(latitudeDelta: height, longitudeDelta: max(0.006, (east - west) * 1.25))
        withAnimation { camera = .region(MKCoordinateRegion(center: center, span: span)) }
    }

    /// A touch on the map: the piste or the lift under the finger, if it is shown.
    private func touch(_ place: CLLocationCoordinate2D) {
        guard let terrain, route == nil else { return }
        let found = terrain.nearest(lat: place.latitude, lon: place.longitude, within: 90) { way in
            way.kind == .piste ? showPistes : showLifts
        }
        picked = found
        pickedAt = found == nil ? nil : place
    }

    /// The line touched becomes where the way starts, or where it ends.
    private func set(start: Bool) {
        guard let terrain, let picked, picked < terrain.ways.count else { return }
        let way = terrain.ways[picked]
        // A lift is taken at its bottom and left at its top; a piste where it was touched.
        let place: CLLocationCoordinate2D
        if way.kind == .lift {
            let i = start ? 0 : way.lats.count - 1
            place = CLLocationCoordinate2D(latitude: way.lats[i], longitude: way.lons[i])
        } else {
            place = pickedAt ?? CLLocationCoordinate2D(latitude: way.lats[0], longitude: way.lons[0])
        }
        if start { from = place } else { to = place }
        self.picked = nil
        findRoute()
    }

    private func findRoute() {
        noRoute = false
        guard let graph, let from, let to else {
            route = nil
            return
        }
        route = graph.route(fromLat: from.latitude, fromLon: from.longitude, toLat: to.latitude, toLon: to.longitude, level: level)
        if let route { bringInView(route.lats, route.lons) }
        if route == nil {
            noRoute = true
            // To choose again where to get.
            self.to = nil
        }
    }

    private func clear() {
        from = nil
        to = nil
        route = nil
        picked = nil
        noRoute = false
    }
}

/// Where the way starts or ends, on the map.
private struct EndDot: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Theme.onAccent)
            .frame(width: 30, height: 30)
            .background(color, in: Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 2))
            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
    }
}

/// Shows or hides a kind of thing on the map.
private struct LayerChip: View {
    let title: String
    let symbol: String
    @Binding var on: Bool

    var body: some View {
        Button { on.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.caption.weight(.semibold))
                Text(LocalizedStringKey(title)).font(.caption.weight(.semibold))
            }
            .foregroundStyle(on ? Theme.text : Theme.sub)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glass(in: Capsule(), tint: on ? Theme.accent : nil)
            .opacity(on ? 1 : 0.75)
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: on)
    }
}
