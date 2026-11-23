import MapKit
import SwiftUI
import UIKit

/// A place where you skied, on the map behind everything.
struct PlacePin: Identifiable, Equatable {
    let id: String
    let name: String
    let lat: Double
    let lon: Double
    let days: Int

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }

    /// One pin for each place: the days less than about five kilometers apart share one.
    static func of(_ days: [DaySummary]) -> [PlacePin] {
        var cells: [String: PlacePin] = [:]
        // Oldest first, so that the name and the place of the newest day stay.
        for day in days.reversed() {
            guard let coordinate = day.coordinate else { continue }
            let key = "\((coordinate.latitude * 20).rounded()),\((coordinate.longitude * 20).rounded())"
            cells[key] = PlacePin(id: key, name: day.title ?? cells[key]?.name ?? "", lat: coordinate.latitude, lon: coordinate.longitude,
                                  days: (cells[key]?.days ?? 0) + 1)
        }
        return cells.values.sorted { $0.id < $1.id }
    }

    /// All the pins with room around them: never closer than a region, so that one place alone
    /// still shows where in the Alps it is. With no pin, the Alps.
    static func region(_ pins: [PlacePin]) -> MKCoordinateRegion {
        SnowMap.fit(pins.map(\.coordinate), room: 1.7, least: MKCoordinateSpan(latitudeDelta: 1.4, longitudeDelta: 2.2))
            ?? MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 46.3, longitude: 9.6),
                                  span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 7))
    }
}

/// A line to draw on the map as it is: a run in the colors of its speed, a way found, a piste touched.
struct MapLine {
    let coordinates: [CLLocationCoordinate2D]
    let color: UIColor
    let width: CGFloat
    var dash: [NSNumber]?
}

/// A point on the map with a symbol: a hut, where a way starts, where it ends.
struct MapMark: Equatable {
    let id: String
    let lat: Double
    let lon: Double
    let title: String
    let symbol: String
    let color: UIColor
}

/// A pin: a place with its days, a friend skiing now, or a point with a symbol.
final class PinAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let glyph: String?
    let symbol: String?
    let color: UIColor

    init(coordinate: CLLocationCoordinate2D, title: String, glyph: String? = nil, symbol: String? = nil, color: UIColor) {
        self.coordinate = coordinate
        self.title = title
        self.glyph = glyph
        self.symbol = symbol
        self.color = color
    }
}

/// The dot that goes along the track when a day is played again.
final class MovingDot: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D

    init(_ coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
}

/// A line on the map with the way it is drawn.
final class StyledLine: MKPolyline {
    var color: UIColor = .white
    var width: CGFloat = 3
    var dash: [NSNumber]?
}

/// The map of the app: Apple's names over the map drawn by `Relief` (the mountain in winter up
/// close, the mountains at night from far away), with the pistes in their colors, the lifts, the
/// places skied, the friends and the line of the day.
struct SnowMap: UIViewRepresentable {
    var pins: [PlacePin] = []
    var friends: [LiveFriend] = []
    var marks: [MapMark] = []
    var tracks: [MapTrack] = []
    /// The lines of the day fainter, under something else drawn over them.
    var dimmed = false
    var terrain: Terrain?
    var lines: [MapLine] = []
    /// A word that changes when `lines` do: they are not compared one by one.
    var linesKey = ""
    /// The dot of a day played again.
    var dot: CLLocationCoordinate2D?
    /// Where to look, and a word that changes when the map should go there again.
    var region: MKCoordinateRegion
    var regionKey: String
    /// When set, the map looks from here at every change: for a day played again.
    var camera: MKMapCamera?
    /// Counts the taps on "where am I".
    var recenter = 0
    /// How much of the bottom is covered by something else, in points.
    var bottomInset: CGFloat = 0
    /// The blue dot of where you are.
    var showsUser = true
    /// Told when the map stops: its center and how many degrees of latitude it shows.
    var onMove: ((CLLocationCoordinate2D, Double) -> Void)?
    /// Told where the map was touched.
    var onTap: ((CLLocationCoordinate2D) -> Void)?

    /// Some points with room around them, never closer than a least span. nil with no point.
    static func fit(_ points: [CLLocationCoordinate2D], room: Double = 1.35,
                    least: MKCoordinateSpan = MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)) -> MKCoordinateRegion? {
        let lats = points.map(\.latitude), lons = points.map(\.longitude)
        guard let south = lats.min(), let north = lats.max(), let west = lons.min(), let east = lons.max() else { return nil }
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: (south + north) / 2, longitude: (west + east) / 2),
                                  span: MKCoordinateSpan(latitudeDelta: max(least.latitudeDelta, (north - south) * room),
                                                         longitudeDelta: max(least.longitudeDelta, (east - west) * room)))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        let style = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        style.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = style
        map.delegate = context.coordinator
        map.showsUserLocation = showsUser
        map.showsCompass = false
        map.overrideUserInterfaceStyle = .dark
        map.addOverlay(ReliefOverlay(), level: .aboveRoads)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.cancelsTouchesInView = false
        map.addGestureRecognizer(tap)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.apply(self, to: map)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var pinsKey = ""
        private var linesKey = ""
        private var regionKey: String?
        private var recenter = 0
        private var dot: MovingDot?
        private var onMove: ((CLLocationCoordinate2D, Double) -> Void)?
        private var onTap: ((CLLocationCoordinate2D) -> Void)?

        func apply(_ view: SnowMap, to map: MKMapView) {
            onMove = view.onMove
            onTap = view.onTap
            if map.layoutMargins.bottom != view.bottomInset {
                map.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: view.bottomInset, right: 0)
            }

            let pins = view.pins.map { "\($0.id):\($0.days)" }.joined(separator: ",")
                + "|" + view.friends.map { "\($0.id):\($0.lat):\($0.lon)" }.joined(separator: ",")
                + "|" + view.marks.map { "\($0.id):\($0.lat):\($0.lon)" }.joined(separator: ",")
            if pins != pinsKey {
                pinsKey = pins
                map.removeAnnotations(map.annotations.filter { $0 is PinAnnotation })
                map.addAnnotations(Self.annotations(view))
            }

            let lines = "\(view.terrain?.ways.count ?? 0)|\(view.tracks.count)|\(view.tracks.reduce(0) { $0 + $1.coordinates.count })|\(view.dimmed)|\(view.lines.count)|\(view.linesKey)"
            if lines != linesKey {
                linesKey = lines
                map.removeOverlays(map.overlays.filter { $0 is StyledLine })
                map.addOverlays(Self.lines(terrain: view.terrain, tracks: view.tracks, dimmed: view.dimmed, more: view.lines), level: .aboveLabels)
            }

            if let place = view.dot {
                if let dot {
                    dot.coordinate = place
                } else {
                    let new = MovingDot(place)
                    dot = new
                    map.addAnnotation(new)
                }
            } else if let old = dot {
                map.removeAnnotation(old)
                dot = nil
            }

            if regionKey != view.regionKey {
                let first = regionKey == nil
                regionKey = view.regionKey
                map.setRegion(view.region, animated: !first)
            }
            if let camera = view.camera { map.setCamera(camera, animated: false) }
            if recenter != view.recenter {
                recenter = view.recenter
                map.setUserTrackingMode(.follow, animated: true)
            }
        }

        static func annotations(_ view: SnowMap) -> [PinAnnotation] {
            let places = view.pins.map {
                PinAnnotation(coordinate: $0.coordinate, title: $0.name, glyph: $0.days > 0 ? "\($0.days)" : nil,
                              symbol: $0.days > 0 ? nil : "mountain.2.fill", color: UIColor(Theme.accent))
            }
            let friends = view.friends.map {
                PinAnnotation(coordinate: $0.coordinate, title: $0.name, glyph: String($0.name.prefix(2)).uppercased(),
                              color: UIColor(FriendMarker.color($0.phase)))
            }
            let marks = view.marks.map {
                PinAnnotation(coordinate: CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon), title: $0.title, symbol: $0.symbol, color: $0.color)
            }
            return places + friends + marks
        }

        /// The pistes under, thin and in their colors; the lifts dark; over them the day, and
        /// over the day what a screen draws of its own.
        static func lines(terrain: Terrain?, tracks: [MapTrack], dimmed: Bool = false, more: [MapLine] = []) -> [StyledLine] {
            var out: [StyledLine] = []
            func add(_ points: [CLLocationCoordinate2D], _ color: UIColor, _ width: CGFloat, _ dash: [NSNumber]? = nil) {
                guard points.count > 1 else { return }
                var coordinates = points
                let line = StyledLine(coordinates: &coordinates, count: coordinates.count)
                line.color = color
                line.width = width
                line.dash = dash
                out.append(line)
            }
            for way in terrain?.ways ?? [] {
                let points = zip(way.lats, way.lons).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) }
                if way.kind == .piste {
                    add(points, UIColor(Theme.difficultyColor(way.difficulty) ?? Color(hex: 0x4f9dff)), 2.5)
                } else {
                    add(points, UIColor(red: 0.14, green: 0.16, blue: 0.23, alpha: 1), 1.6)
                }
            }
            let ink = UIColor(Theme.track)
            let fade: CGFloat = dimmed ? 0.3 : 1
            for track in tracks {
                switch track.kind {
                case .run: add(track.coordinates, ink.withAlphaComponent(fade), dimmed ? 3.5 : 5)
                case .lift: add(track.coordinates, ink.withAlphaComponent(0.55 * fade), 2.5, [6, 6])
                case .idle: add(track.coordinates, ink.withAlphaComponent(0.4 * fade), 2)
                }
            }
            for line in more { add(line.coordinates, line.color, line.width, line.dash) }
            return out
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MKMapView, let onTap else { return }
            onTap(map.convert(gesture.location(in: map), toCoordinateFrom: map))
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay { return MKTileOverlayRenderer(tileOverlay: tiles) }
            guard let line = overlay as? StyledLine else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = line.color
            renderer.lineWidth = line.width
            renderer.lineCap = .round
            renderer.lineJoin = .round
            renderer.lineDashPattern = line.dash
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MovingDot {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "dot") ?? MKAnnotationView(annotation: annotation, reuseIdentifier: "dot")
                view.annotation = annotation
                view.image = Self.dotImage
                view.displayPriority = .required
                return view
            }
            guard let pin = annotation as? PinAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "pin") as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: pin, reuseIdentifier: "pin")
            view.annotation = pin
            view.glyphText = pin.glyph
            view.glyphImage = pin.symbol.flatMap { UIImage(systemName: $0) }
            view.markerTintColor = pin.color
            view.glyphTintColor = .white
            view.displayPriority = .required
            view.titleVisibility = .adaptive
            return view
        }

        /// A white dot with a ring in the color of the day.
        private static let dotImage: UIImage = {
            let size = CGSize(width: 22, height: 22)
            return UIGraphicsImageRenderer(size: size).image { context in
                let box = CGRect(origin: .zero, size: size).insetBy(dx: 3.5, dy: 3.5)
                UIColor.white.setFill()
                context.cgContext.fillEllipse(in: box)
                UIColor(Theme.track).setStroke()
                context.cgContext.setLineWidth(5)
                context.cgContext.strokeEllipse(in: box)
            }
        }()

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // From the zoom of a valley in the map is snow, and its words are dark.
            let zoom = Self.zoom(span: mapView.region.span.longitudeDelta, width: mapView.bounds.width)
            let style: UIUserInterfaceStyle = zoom >= Double(Relief.snowFrom) - 0.5 ? .light : .dark
            if mapView.overrideUserInterfaceStyle != style { mapView.overrideUserInterfaceStyle = style }
            onMove?(mapView.region.center, mapView.region.span.latitudeDelta)
        }

        /// The zoom of the squares of the map that a view this wide showing this many degrees is at.
        static func zoom(span: Double, width: CGFloat) -> Double {
            guard span > 0, width > 0 else { return 0 }
            return log2(360 * Double(width) / 256 / span)
        }
    }
}

/// A piece of the map inside a screen: the line of a day, a run in the colors of its speed, the
/// friends skiing now, or a ski area with its pin; with the pistes around when they are known or
/// the internet is allowed.
struct PlaceMap: View {
    var tracks: [MapTrack] = []
    var dimmed = false
    var lines: [MapLine] = []
    var friends: [LiveFriend] = []
    /// A place to show with a pin when there is nothing else.
    var place: PlacePin?
    @State private var terrain: Terrain?

    var body: some View {
        let region = Self.region(tracks: tracks, lines: lines, friends: friends, place: place)
        SnowMap(pins: place.map { [$0] } ?? [], friends: friends, tracks: tracks, dimmed: dimmed, terrain: terrain, lines: lines,
                linesKey: "\(lines.first?.coordinates.count ?? 0)", region: region,
                regionKey: "\(tracks.count)|\(lines.count)|\(friends.count)|\(place?.id ?? "")", showsUser: false)
            .clipShape(Theme.round)
            .task(id: "\(region.center.latitude),\(region.center.longitude)") {
                let lat = region.center.latitude, lon = region.center.longitude
                if let kept = Terrains.shared.known(lat: lat, lon: lon) {
                    terrain = kept
                } else if UserDefaults.standard.object(forKey: Prefs.online) as? Bool ?? true {
                    terrain = try? await Terrains.shared.terrain(lat: lat, lon: lon)
                }
            }
    }

    /// What a screen draws of its own with room around it, or else all of the day, or the
    /// friends; a ski area alone, about nine kilometers of it.
    static func region(tracks: [MapTrack], lines: [MapLine] = [], friends: [LiveFriend] = [], place: PlacePin?) -> MKCoordinateRegion {
        if let fit = SnowMap.fit(lines.flatMap(\.coordinates), room: 1.4, least: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)) { return fit }
        if let fit = SnowMap.fit(tracks.flatMap(\.coordinates)) { return fit }
        if let fit = SnowMap.fit(friends.map(\.coordinate), room: 1.8, least: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.04)) { return fit }
        let center = place?.coordinate ?? CLLocationCoordinate2D(latitude: 46.3, longitude: 9.6)
        return MKCoordinateRegion(center: center, latitudinalMeters: 9000, longitudinalMeters: 9000)
    }
}

/// The map behind the sheet: the day under way while it is recorded or about to be, the places
/// skied on the other screens, the friends who share where they are.
struct Backdrop: View {
    let tab: Int
    /// How much of the height the sheet covers.
    let covered: CGFloat
    let recenter: Int
    @Environment(Library.self) private var library
    @Environment(Recorder.self) private var recorder
    @Environment(Social.self) private var social
    @State private var terrain: Terrain?
    @State private var asked: CLLocationCoordinate2D?

    var body: some View {
        let pins = PlacePin.of(library.days)
        let live = tab == 0
        GeometryReader { box in
            SnowMap(pins: live ? [] : pins,
                    friends: live || tab == 3 ? social.live : [],
                    tracks: live ? recorder.tracks : [],
                    terrain: terrain,
                    region: region(pins: pins, live: live),
                    regionKey: live ? "live\(recorder.lastPoint == nil ? 0 : 1)" : "places\(pins.count)",
                    recenter: recenter,
                    bottomInset: box.size.height * covered,
                    onMove: { center, span in moved(to: center, span: span) })
        }
        .accessibilityLabel(Text("Mappa"))
    }

    private func region(pins: [PlacePin], live: Bool) -> MKCoordinateRegion {
        if live, let point = recorder.lastPoint {
            return MKCoordinateRegion(center: point.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035))
        }
        return PlacePin.region(pins)
    }

    /// Close enough to see pistes, and somewhere new: the ones around, downloaded or from
    /// OpenStreetMap when the internet is allowed.
    private func moved(to center: CLLocationCoordinate2D, span: Double) {
        guard span < 0.12 else { return }
        if let asked, Geo.distance(lat1: asked.latitude, lon1: asked.longitude, lat2: center.latitude, lon2: center.longitude) < 3000 { return }
        asked = center
        Task { @MainActor in
            if let kept = Terrains.shared.known(lat: center.latitude, lon: center.longitude) {
                terrain = kept
            } else if UserDefaults.standard.object(forKey: Prefs.online) as? Bool ?? true,
                      let loaded = try? await Terrains.shared.terrain(lat: center.latitude, lon: center.longitude) {
                terrain = loaded
            }
        }
    }
}

/// Whether the buttons on the right edge of the sheet are hidden: a screen that is all map, with
/// its own panel at the bottom, hides them while it is shown.
@Observable final class Chrome {
    static let shared = Chrome()
    private(set) var hidden = 0

    func hide() { hidden += 1 }
    func show() { hidden = max(0, hidden - 1) }
}

extension View {
    /// For a screen that is all map: no buttons of the sheet over it.
    func hidesRail() -> some View {
        onAppear { Chrome.shared.hide() }.onDisappear { Chrome.shared.show() }
    }
}
