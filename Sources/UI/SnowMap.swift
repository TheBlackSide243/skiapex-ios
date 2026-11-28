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
    /// A place skied: drawn as the lens of the goggles of the icon, not as a pin.
    let lens: Bool

    init(coordinate: CLLocationCoordinate2D, title: String, glyph: String? = nil, symbol: String? = nil, color: UIColor, lens: Bool = false) {
        self.coordinate = coordinate
        self.title = title
        self.glyph = glyph
        self.symbol = symbol
        self.color = color
        self.lens = lens
    }
}

/// A place skied on the map: the lens of the goggles of the icon, with the number of days in it
/// and the name of the place under it.
final class LensPinView: MKAnnotationView {
    private let name = UILabel()
    static let size = CGSize(width: 52, height: 34)

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(origin: .zero, size: Self.size)
        displayPriority = .required
        name.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        name.textColor = .white
        name.textAlignment = .center
        name.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        name.layer.cornerRadius = 8
        name.layer.masksToBounds = true
        addSubview(name)
    }

    required init?(coder: NSCoder) { nil }

    func show(_ pin: PinAnnotation) {
        image = Self.picture(text: pin.glyph ?? "", color: pin.color)
        name.text = pin.title
        name.isHidden = (pin.title ?? "").isEmpty
        let fit = name.sizeThatFits(CGSize(width: 160, height: 20))
        name.frame = CGRect(x: (Self.size.width - fit.width - 12) / 2, y: Self.size.height + 2, width: fit.width + 12, height: 17)
    }

    /// The outline of the lens of the icon, in a box.
    static func outline(in box: CGRect) -> UIBezierPath {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: box.minX + (x - 150) / 724 * box.width, y: box.minY + (y - 300) / 424 * box.height)
        }
        let path = UIBezierPath()
        path.move(to: p(150, 430))
        path.addCurve(to: p(330, 300), controlPoint1: p(150, 330), controlPoint2: p(220, 300))
        path.addLine(to: p(694, 300))
        path.addCurve(to: p(874, 430), controlPoint1: p(804, 300), controlPoint2: p(874, 330))
        path.addLine(to: p(874, 560))
        path.addCurve(to: p(700, 724), controlPoint1: p(874, 664), controlPoint2: p(800, 724))
        path.addCurve(to: p(512, 664), controlPoint1: p(620, 724), controlPoint2: p(580, 664))
        path.addCurve(to: p(324, 724), controlPoint1: p(444, 664), controlPoint2: p(404, 724))
        path.addCurve(to: p(150, 560), controlPoint1: p(224, 724), controlPoint2: p(150, 664))
        path.close()
        return path
    }

    private static var drawn: [String: UIImage] = [:]

    static func picture(text: String, color: UIColor) -> UIImage {
        let key = text + "|" + color.description
        if let kept = drawn[key] { return kept }
        let made = UIGraphicsImageRenderer(size: size).image { context in
            let lens = outline(in: CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4))
            let cg = context.cgContext
            cg.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 3, color: UIColor.black.withAlphaComponent(0.45).cgColor)
            UIColor(red: 0.04, green: 0.09, blue: 0.15, alpha: 1).setStroke()
            lens.lineWidth = 5
            lens.lineJoinStyle = .round
            lens.stroke()
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            color.setFill()
            lens.fill()
            // The light on the glass.
            cg.saveGState()
            lens.addClip()
            UIColor.white.withAlphaComponent(0.3).setFill()
            let shine = UIBezierPath()
            shine.move(to: CGPoint(x: 8, y: 0))
            shine.addLine(to: CGPoint(x: 20, y: 0))
            shine.addLine(to: CGPoint(x: 10, y: size.height))
            shine.addLine(to: CGPoint(x: -2, y: size.height))
            shine.close()
            shine.fill()
            cg.restoreGState()
            UIColor.white.withAlphaComponent(0.55).setStroke()
            lens.lineWidth = 1
            lens.stroke()
            let words = NSAttributedString(string: text, attributes: [
                .font: UIFont.systemFont(ofSize: 14, weight: .heavy),
                .foregroundColor: UIColor(red: 0.02, green: 0.13, blue: 0.18, alpha: 1),
            ])
            let box = words.size()
            words.draw(at: CGPoint(x: (size.width - box.width) / 2, y: (size.height - box.height) / 2 - 2.5))
        }
        drawn[key] = made
        return made
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
    /// When set, the map keeps this point in the middle, from close: for a day played again.
    var center: CLLocationCoordinate2D?
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
        map.isPitchEnabled = false
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
        /// The lines are on the map in three layers, each changed by itself: the pistes under,
        /// the day over them, what a screen draws of its own on top. The day changes every few
        /// seconds while it is recorded: the pistes stay as they are, and nothing goes blank.
        private var groundKey: String?
        private var dayKey: String?
        private var extraKey: String?
        private var ground: [StyledLine] = []
        private var day: [StyledLine] = []
        private var extra: [StyledLine] = []
        private var regionKey: String?
        private var recenter = 0
        private var dot: MovingDot?
        private var followed: CLLocationCoordinate2D?
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

            let groundNow = Self.key(view.terrain)
            if groundNow != groundKey {
                groundKey = groundNow
                let new = Self.lines(terrain: view.terrain, tracks: [])
                Self.replace(ground, with: new, below: day.first ?? extra.first, on: map)
                ground = new
            }
            let dayNow = "\(view.tracks.count)|\(view.tracks.reduce(0) { $0 + $1.coordinates.count })|\(view.tracks.map { $0.difficulty ?? "" }.joined())|\(view.dimmed)"
            if dayNow != dayKey {
                dayKey = dayNow
                let new = Self.lines(terrain: nil, tracks: view.tracks, dimmed: view.dimmed)
                Self.replace(day, with: new, below: extra.first, on: map)
                day = new
            }
            let extraNow = "\(view.lines.count)|\(view.linesKey)"
            if extraNow != extraKey {
                extraKey = extraNow
                let new = Self.lines(terrain: nil, tracks: [], more: view.lines)
                Self.replace(extra, with: new, below: nil, on: map)
                extra = new
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
            if let center = view.center, center.latitude != followed?.latitude || center.longitude != followed?.longitude {
                followed = center
                map.setRegion(MKCoordinateRegion(center: center, latitudinalMeters: 1500, longitudinalMeters: 1500), animated: false)
            } else if view.center == nil {
                followed = nil
            }
            if recenter != view.recenter {
                recenter = view.recenter
                map.setUserTrackingMode(.follow, animated: true)
            }
        }

        /// What tells one set of pistes from another.
        static func key(_ terrain: Terrain?) -> String {
            guard let terrain else { return "" }
            let first = terrain.ways.first, last = terrain.ways.last
            return "\(terrain.ways.count)|\(first?.lats.first ?? 0),\(first?.lons.first ?? 0)|\(last?.lats.last ?? 0),\(last?.lons.last ?? 0)"
        }

        /// The new lines of a layer go on first and the old ones come off after: in between the map
        /// is never without them.
        static func replace(_ old: [StyledLine], with new: [StyledLine], below: MKOverlay?, on map: MKMapView) {
            if let below {
                for line in new { map.insertOverlay(line, below: below) }
            } else if !new.isEmpty {
                map.addOverlays(new, level: .aboveLabels)
            }
            if !old.isEmpty { map.removeOverlays(old) }
        }

        static func annotations(_ view: SnowMap) -> [PinAnnotation] {
            let places = view.pins.map {
                PinAnnotation(coordinate: $0.coordinate, title: $0.name, glyph: $0.days > 0 ? "\($0.days)" : "▲",
                              color: UIColor(Theme.accent), lens: true)
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

        /// The pistes under, thin and in their colors; the lifts dark; over them the day, each run
        /// in the color of its piste (or in the color of the day, when the piste is not known)
        /// with a white edge; and over the day what a screen draws of its own.
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
                    add(points, UIColor(Theme.difficultyColor(way.difficulty) ?? Color(hex: 0x4f9dff)), 3)
                } else {
                    add(points, UIColor(red: 0.14, green: 0.16, blue: 0.23, alpha: 1), 2)
                }
            }
            let ink = UIColor(Theme.track)
            let fade: CGFloat = dimmed ? 0.3 : 1
            for track in tracks {
                switch track.kind {
                case .run:
                    let width: CGFloat = dimmed ? 3.5 : 5
                    let color = track.difficulty.flatMap { Theme.difficultyColor($0) }.map { UIColor($0) } ?? ink
                    add(track.coordinates, UIColor.white.withAlphaComponent(0.92 * fade), width + 3.5)
                    add(track.coordinates, color.withAlphaComponent(fade), width)
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
            if pin.lens {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "lens") as? LensPinView
                    ?? LensPinView(annotation: pin, reuseIdentifier: "lens")
                view.annotation = pin
                view.show(pin)
                return view
            }
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
            // From the zoom of a valley in the map is snow, and its words are dark. With a little
            // room either side: on the edge, the map would be drawn again and again from scratch.
            let zoom = Self.zoom(span: mapView.region.span.longitudeDelta, width: mapView.bounds.width)
            let edge = Double(Relief.snowFrom) - 0.5
            let style: UIUserInterfaceStyle = zoom >= edge + 0.3 ? .light : zoom < edge - 0.3 ? .dark : mapView.overrideUserInterfaceStyle
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
        // The day the watch records by itself, when the iPhone is not recording one of its own.
        let watch = WatchDay.shared
        let fromWatch = live && watch.active && (recorder.handed || recorder.state == .idle)
        let here = fromWatch ? watch.lastPoint : recorder.lastPoint
        // A ski area a screen asked to show: alone, with all its pistes and lifts.
        let shown = live ? nil : Stage.shared.place
        let shownTerrain = Stage.shared.terrain
        GeometryReader { box in
            SnowMap(pins: live ? [] : (shown.map { [$0] } ?? pins),
                    friends: live || tab == 3 ? social.live : [],
                    // The places to meet, while a day is recorded or about to be: from far away,
                    // among the places skied, they would only be in the way.
                    marks: live ? social.meetings.map(\.mark) : [],
                    tracks: live ? (fromWatch ? watch.tracks : recorder.tracks) : [],
                    terrain: shown == nil ? terrain : (shownTerrain ?? terrain),
                    region: shown.map { Stage.region(of: $0, terrain: shownTerrain) } ?? region(pins: pins, live: live, here: here),
                    regionKey: shown.map { "stage\($0.id)|\(shownTerrain?.ways.count ?? 0)" }
                        ?? (live ? "live\(here == nil ? 0 : 1)\(fromWatch ? "w" : "")" : "places\(pins.count)"),
                    recenter: recenter,
                    bottomInset: box.size.height * covered,
                    onMove: { center, span in moved(to: center, span: span) })
        }
        .accessibilityLabel(Text("Mappa"))
    }

    private func region(pins: [PlacePin], live: Bool, here: TrackPoint?) -> MKCoordinateRegion {
        if live, let point = here {
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

/// What a screen asks the map behind the sheet to show: a ski area, with all its pistes and lifts,
/// while its page is open.
@Observable final class Stage {
    static let shared = Stage()
    private(set) var place: PlacePin?
    private(set) var terrain: Terrain?
    /// Counts the times a ski area was put on the map: the sheet then stands lower, to show it.
    private(set) var asks = 0

    func show(_ place: PlacePin, terrain: Terrain?) {
        if self.place?.id != place.id { asks += 1 }
        self.place = place
        self.terrain = terrain
    }

    func leave(_ id: String) {
        guard place?.id == id else { return }
        place = nil
        terrain = nil
    }

    /// All the pistes and the lifts of a ski area with a little room around them; before they
    /// are known, about nine kilometers around it.
    static func region(of place: PlacePin, terrain: Terrain?) -> MKCoordinateRegion {
        let all = (terrain?.ways ?? []).flatMap { way in zip(way.lats, way.lons).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) } }
        return SnowMap.fit(all, room: 1.2, least: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
            ?? MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 9000, longitudinalMeters: 9000)
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
