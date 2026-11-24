import MapKit
import SwiftUI

/// The map of a ski area: its pistes in the colors of the signs, its lifts and its huts, from
/// OpenStreetMap. Touch a piste or a lift to see what it is, and to set where you leave from and
/// where you want to get: the way is found along the pistes and the lifts. A hut, a piste or a
/// lift can be sent to the friends as the place to meet, and theirs are on the map.
struct ExploreView: View {
    let name: String
    let center: CLLocationCoordinate2D
    /// A place to meet to show as the map opens.
    var meeting: Meeting?

    @Environment(Recorder.self) private var recorder
    @Environment(Social.self) private var social
    @AppStorage(Prefs.mapLook) private var mapLook = MapLook.standard.rawValue
    @State private var region: MKCoordinateRegion
    /// Counts the times the map was asked to go somewhere.
    @State private var moves = 0
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
    /// The hut touched, the place to meet touched, and the place about to be sent to the friends.
    @State private var hut: Hut?
    @State private var met: Meeting?
    @State private var draft: MeetingDraft?

    init(name: String, center: CLLocationCoordinate2D, meeting: Meeting? = nil) {
        self.name = name
        self.center = center
        self.meeting = meeting
        _region = State(initialValue: MKCoordinateRegion(center: center, latitudinalMeters: 6500, longitudinalMeters: 6500))
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
            SnowMap(marks: marks,
                    lines: drawn.map {
                        MapLine(coordinates: $0.coordinates, color: UIColor($0.color), width: $0.style.lineWidth,
                                dash: $0.style.dash.isEmpty ? nil : $0.style.dash.map { NSNumber(value: Double($0)) })
                    },
                    linesKey: "\(picked ?? -1)|\(showPistes)|\(showLifts)|\(route?.lats.count ?? 0)|\(terrain?.ways.count ?? 0)",
                    region: region, regionKey: "\(moves)", onTap: { touch($0) })
                .ignoresSafeArea(edges: .bottom)

            panel
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
        .overlay(alignment: .top) { layers.padding(.top, 8) }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .hidesRail()
        .task { await load() }
        .onChange(of: level) { _, _ in findRoute() }
        .sheet(item: $draft) { MeetingEditor(draft: $0) }
    }

    /// The places to meet set around here, by you and by your friends.
    private var meetings: [Meeting] {
        social.meetings.filter {
            Geo.distance(lat1: $0.lat, lon1: $0.lon, lat2: center.latitude, lon2: center.longitude) < 25_000
        }
    }

    /// Where you are: the day under way, or the iPhone.
    private var here: CLLocationCoordinate2D? {
        if recorder.state == .recording, let point = recorder.lastPoint { return point.coordinate }
        return recorder.here?.coordinate
    }

    // MARK: The map

    /// The huts, and where the way starts and ends.
    private var marks: [MapMark] {
        var out: [MapMark] = []
        if showHuts, let terrain {
            out += terrain.huts.map { MapMark(id: "hut\($0.id)", lat: $0.lat, lon: $0.lon, title: $0.name, symbol: "fork.knife", color: UIColor(Theme.warn)) }
        }
        out += meetings.map(\.mark)
        if let from {
            out.append(MapMark(id: "from", lat: from.latitude, lon: from.longitude, title: String(localized: "Partenza"),
                               symbol: "figure.skiing.downhill", color: UIColor(Theme.good)))
        }
        if let to {
            out.append(MapMark(id: "to", lat: to.latitude, lon: to.longitude, title: String(localized: "Arrivo"),
                               symbol: "flag.checkered", color: UIColor(Theme.accent)))
        }
        return out
    }

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
                // Every piste has a white edge, to stand out on the snow and on the rock.
                out.append(Line(id: -i - 1, coordinates: coordinates, color: Color.white.opacity(0.9),
                                style: StrokeStyle(lineWidth: chosen ? 9 : 5.5, lineCap: .round, lineJoin: .round)))
                out.append(Line(id: i, coordinates: coordinates, color: color,
                                style: chosen ? StrokeStyle(lineWidth: 6.5, lineCap: .round, lineJoin: .round) : round))
            case .lift:
                guard showLifts else { continue }
                out.append(Line(id: i, coordinates: coordinates, color: Color(hex: 0x232a3a),
                                style: StrokeStyle(lineWidth: chosen ? 4.5 : 2, lineCap: .round, lineJoin: .round)))
            }
        }
        if let route, route.lats.count >= 2 {
            let coordinates = zip(route.lats, route.lons).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) }
            out.append(Line(id: 1_000_000, coordinates: coordinates, color: Color.white,
                            style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round)))
            out.append(Line(id: 1_000_001, coordinates: coordinates, color: Theme.track,
                            style: StrokeStyle(lineWidth: 6.5, lineCap: .round, lineJoin: .round)))
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
                } else if let met {
                    meetingCard(met)
                } else if let hut {
                    hutCard(hut)
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
        return "Tocca una pista, un impianto o un rifugio per vedere cos'è, calcolare un percorso o dire agli amici di trovarvi lì."
    }

    /// A hut touched: the way there, or the place to meet.
    private func hutCard(_ hut: Hut) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "fork.knife").font(.footnote.weight(.semibold)).foregroundStyle(Theme.warn)
                Text(hut.name).font(.headline).foregroundStyle(Theme.text).lineLimit(2)
                Spacer(minLength: 6)
                Button { self.hut = nil } label: { Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(Theme.sub) }
                    .accessibilityLabel(Text("Chiudi"))
            }
            HStack(spacing: 10) {
                Button {
                    draft = MeetingDraft(place: CLLocationCoordinate2D(latitude: hut.lat, longitude: hut.lon), label: hut.name)
                } label: { Label("Troviamoci qui", systemImage: "person.2.fill") }
                    .buttonStyle(SecondaryButtonStyle())
                Button {
                    go(to: CLLocationCoordinate2D(latitude: hut.lat, longitude: hut.lon))
                } label: { Label("Arrivo qui", systemImage: "flag.checkered") }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    /// A place to meet touched: whose it is, when, and the way there.
    private func meetingCard(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Avatar(id: meeting.id, name: meeting.name, photo: meeting.photo, size: 40, ring: Theme.track)
                VStack(alignment: .leading, spacing: 3) {
                    Text(meeting.title).font(.headline).foregroundStyle(Theme.text).lineLimit(2).minimumScaleFactor(0.8)
                    Text(meeting.detail).font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
                }
                Spacer(minLength: 6)
                Button { met = nil } label: { Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(Theme.sub) }
                    .accessibilityLabel(Text("Chiudi"))
            }
            HStack(spacing: 10) {
                if meeting.mine {
                    Button {
                        met = nil
                        Task { await social.clearMeeting() }
                    } label: { Label("Togli", systemImage: "xmark") }
                        .buttonStyle(SecondaryButtonStyle(color: Theme.bad))
                }
                Button { go(to: meeting.coordinate) } label: { Label("Portami lì", systemImage: "arrow.triangle.turn.up.right.diamond.fill") }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private func wayCard(_ way: OSMWay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if way.kind == .piste {
                    PisteBadge(difficulty: way.difficulty, ref: way.ref, size: 26)
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
            Button {
                draft = MeetingDraft(place: spot(on: way, start: false), label: way.label ?? Self.nameless(way.kind))
            } label: {
                Label("Troviamoci qui", systemImage: "person.2.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PressStyle())
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
                // The picture of a place to meet: the friend's, with no way drawn yet.
                if Demo.screen == "meet" { met = social.meetings.first } else { findRoute() }
            }
            return
        }
        do {
            // The ones downloaded are here with no signal; the others come from OpenStreetMap.
            show(try await Terrains.shared.terrain(lat: center.latitude, lon: center.longitude))
            met = meeting
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
        region = MKCoordinateRegion(center: center, span: span)
        moves += 1
    }

    /// A touch on the map: a place to meet, a hut, or the piste or the lift under the finger, if
    /// it is shown.
    private func touch(_ place: CLLocationCoordinate2D) {
        guard let terrain, route == nil else { return }
        func near(_ lat: Double, _ lon: Double) -> Double {
            Geo.distance(lat1: place.latitude, lon1: place.longitude, lat2: lat, lon2: lon)
        }
        met = meetings.filter { near($0.lat, $0.lon) < 110 }.min { near($0.lat, $0.lon) < near($1.lat, $1.lon) }
        hut = met != nil || !showHuts ? nil
            : terrain.huts.filter { near($0.lat, $0.lon) < 80 }.min { near($0.lat, $0.lon) < near($1.lat, $1.lon) }
        if met != nil || hut != nil {
            picked = nil
            pickedAt = nil
            return
        }
        let found = terrain.nearest(lat: place.latitude, lon: place.longitude, within: 90) { way in
            way.kind == .piste ? showPistes : showLifts
        }
        picked = found
        pickedAt = found == nil ? nil : place
    }

    /// The line touched becomes where the way starts, or where it ends.
    private func set(start: Bool) {
        guard let terrain, let picked, picked < terrain.ways.count else { return }
        let place = spot(on: terrain.ways[picked], start: start)
        if start { from = place } else { to = place }
        self.picked = nil
        findRoute()
    }

    /// The point of a line touched: a lift is taken at its bottom and left at its top; a piste
    /// where it was touched.
    private func spot(on way: OSMWay, start: Bool) -> CLLocationCoordinate2D {
        if way.kind == .lift {
            let i = start ? 0 : way.lats.count - 1
            return CLLocationCoordinate2D(latitude: way.lats[i], longitude: way.lons[i])
        }
        return pickedAt ?? CLLocationCoordinate2D(latitude: way.lats[0], longitude: way.lons[0])
    }

    /// The way to a place, from where you are when that is on the pistes; else from the piste
    /// or the lift touched next.
    private func go(to place: CLLocationCoordinate2D) {
        to = place
        hut = nil
        met = nil
        picked = nil
        if from == nil, let here, let graph,
           graph.route(fromLat: here.latitude, fromLon: here.longitude, toLat: place.latitude, toLon: place.longitude, level: level) != nil {
            from = here
        }
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
        hut = nil
        met = nil
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
