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
        let lats = pins.map(\.lat), lons = pins.map(\.lon)
        guard let south = lats.min(), let north = lats.max(), let west = lons.min(), let east = lons.max() else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 46.3, longitude: 9.6),
                                      span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 7))
        }
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: (south + north) / 2, longitude: (west + east) / 2),
                                  span: MKCoordinateSpan(latitudeDelta: max(1.4, (north - south) * 1.7), longitudeDelta: max(2.2, (east - west) * 1.7)))
    }
}

/// A pin: a place with its days, or a friend skiing now.
final class PinAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let glyph: String
    let friend: Bool

    init(coordinate: CLLocationCoordinate2D, title: String, glyph: String, friend: Bool) {
        self.coordinate = coordinate
        self.title = title
        self.glyph = glyph
        self.friend = friend
    }
}

/// A line on the map with the way it is drawn.
final class StyledLine: MKPolyline {
    var color: UIColor = .white
    var width: CGFloat = 3
    var dash: [NSNumber]?
}

/// The map behind everything: Apple's from far away, and from the zoom of a valley in the winter
/// map drawn by `Relief`, with the pistes in their colors, the lifts, the places skied, the
/// friends and the line of the day.
struct SnowMap: UIViewRepresentable {
    var pins: [PlacePin] = []
    var friends: [LiveFriend] = []
    var tracks: [MapTrack] = []
    var terrain: Terrain?
    /// Where to look, and a word that changes when the map should go there again.
    var region: MKCoordinateRegion
    var regionKey: String
    /// Counts the taps on "where am I".
    var recenter = 0
    /// How much of the bottom the sheet covers, in points.
    var bottomInset: CGFloat = 0
    /// Told when the map stops: its center and how many degrees of latitude it shows.
    var onMove: ((CLLocationCoordinate2D, Double) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        let style = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        style.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = style
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = false
        map.isPitchEnabled = false
        map.overrideUserInterfaceStyle = .dark
        map.addOverlay(ReliefOverlay(), level: .aboveRoads)
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
        private var onMove: ((CLLocationCoordinate2D, Double) -> Void)?

        func apply(_ view: SnowMap, to map: MKMapView) {
            onMove = view.onMove
            if map.layoutMargins.bottom != view.bottomInset {
                map.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: view.bottomInset, right: 0)
            }

            let pins = view.pins.map { "\($0.id):\($0.days)" }.joined(separator: ",")
                + "|" + view.friends.map { "\($0.id):\($0.lat):\($0.lon)" }.joined(separator: ",")
            if pins != pinsKey {
                pinsKey = pins
                map.removeAnnotations(map.annotations.filter { $0 is PinAnnotation })
                map.addAnnotations(view.pins.map { PinAnnotation(coordinate: $0.coordinate, title: $0.name, glyph: "\($0.days)", friend: false) })
                map.addAnnotations(view.friends.map {
                    PinAnnotation(coordinate: $0.coordinate, title: $0.name, glyph: String($0.name.prefix(2)).uppercased(), friend: true)
                })
            }

            let lines = "\(view.terrain?.ways.count ?? 0)|\(view.tracks.count)|\(view.tracks.reduce(0) { $0 + $1.coordinates.count })"
            if lines != linesKey {
                linesKey = lines
                map.removeOverlays(map.overlays.filter { $0 is StyledLine })
                map.addOverlays(Self.lines(terrain: view.terrain, tracks: view.tracks), level: .aboveLabels)
            }

            if regionKey != view.regionKey {
                let first = regionKey == nil
                regionKey = view.regionKey
                map.setRegion(view.region, animated: !first)
            }
            if recenter != view.recenter {
                recenter = view.recenter
                map.setUserTrackingMode(.follow, animated: true)
            }
        }

        /// The pistes under, thin and in their colors; the lifts dark; over them the day.
        static func lines(terrain: Terrain?, tracks: [MapTrack]) -> [StyledLine] {
            var out: [StyledLine] = []
            for way in terrain?.ways ?? [] {
                var coordinates = zip(way.lats, way.lons).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) }
                let line = StyledLine(coordinates: &coordinates, count: coordinates.count)
                if way.kind == .piste {
                    line.color = UIColor(Theme.difficultyColor(way.difficulty) ?? Color(hex: 0x4f9dff))
                    line.width = 2.5
                } else {
                    line.color = UIColor(red: 0.14, green: 0.16, blue: 0.23, alpha: 1)
                    line.width = 1.6
                }
                out.append(line)
            }
            for track in tracks {
                var coordinates = track.coordinates
                let line = StyledLine(coordinates: &coordinates, count: coordinates.count)
                switch track.kind {
                case .run:
                    line.color = UIColor(Theme.track)
                    line.width = 5
                case .lift:
                    line.color = UIColor(Theme.track).withAlphaComponent(0.55)
                    line.width = 2.5
                    line.dash = [6, 6]
                case .idle:
                    line.color = UIColor(Theme.track).withAlphaComponent(0.4)
                    line.width = 2
                }
                out.append(line)
            }
            return out
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
            guard let pin = annotation as? PinAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "pin") as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: pin, reuseIdentifier: "pin")
            view.annotation = pin
            view.glyphText = pin.glyph
            view.markerTintColor = UIColor(pin.friend ? Theme.good : Theme.accent)
            view.glyphTintColor = .white
            view.displayPriority = .required
            view.titleVisibility = .adaptive
            return view
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // From the zoom of a valley in the map is snow, and its words are dark.
            let zoom = Self.zoom(span: mapView.region.span.longitudeDelta, width: mapView.bounds.width)
            let style: UIUserInterfaceStyle = zoom >= 10 ? .light : .dark
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
