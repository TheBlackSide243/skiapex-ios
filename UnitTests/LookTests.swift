import MapKit
import UIKit
import XCTest
@testable import SkiApex

/// What came with 0.6.0: the numbers with their units small, the winter map, the places behind.
final class LookTests: XCTestCase {
    func testAValueInItsPieces() {
        typealias Piece = FigureText.Piece
        XCTAssertEqual(FigureText.pieces("5074 m"), [Piece(text: "5074", number: true), Piece(text: "M", number: false)])
        XCTAssertEqual(FigureText.pieces("1 h 54 min"), [Piece(text: "1", number: true), Piece(text: "H", number: false),
                                                         Piece(text: "54", number: true), Piece(text: "MIN", number: false)])
        XCTAssertEqual(FigureText.pieces("72 km/h"), [Piece(text: "72", number: true), Piece(text: "KM/H", number: false)])
        XCTAssertEqual(FigureText.pieces("−8°"), [Piece(text: "−8°", number: true)])
        // A number alone, and words alone: whole, as they are.
        XCTAssertEqual(FigureText.pieces("7"), [Piece(text: "7", number: true)])
        XCTAssertEqual(FigureText.pieces("Farinosa"), [Piece(text: "Farinosa", number: true)])
        XCTAssertEqual(FigureText.pieces("–"), [Piece(text: "–", number: true)])
        XCTAssertEqual(String(FigureText.styled("18,5 km", big: .title, small: .caption).characters), "18,5 KM")
    }

    /// A slope facing north-west is in the light, one facing south-east in the shade; flat snow
    /// is in between, and all of it stays a picture of the size it came in.
    func testTheSnowIsLitFromTheNorthWest() {
        let side = 16
        func square(_ height: (Int, Int) -> Float) -> Relief.Heights {
            var values = [Float](repeating: 0, count: side * side)
            for j in 0..<side { for i in 0..<side { values[j * side + i] = height(i, j) } }
            return Relief.Heights(values: values, side: side)
        }
        func brightness(_ heights: Relief.Heights) -> Int {
            let colors = Relief.shade(heights, metersPerPixel: 10)
            XCTAssertEqual(colors.count, side * side * 4)
            let a = (side / 2 * side + side / 2) * 4
            XCTAssertEqual(colors[a + 3], 255)
            return Int(colors[a]) + Int(colors[a + 1]) + Int(colors[a + 2])
        }
        // High above the firs, away from the lines every fifty meters.
        let lit = brightness(square { i, j in 3010 + Float(i + j) * 2 })
        let flat = brightness(square { _, _ in 3020 })
        let shaded = brightness(square { i, j in 3074 - Float(i + j) * 2 })
        XCTAssertGreaterThan(lit, flat)
        XCTAssertGreaterThan(flat, shaded)
        XCTAssertNotNil(Relief.png(Relief.shade(square { _, _ in 3020 }, metersPerPixel: 10), side: side))
        XCTAssertNil(Relief.heights(png: Data([1, 2, 3])))
    }

    /// Twice the points a side keeps a slope a slope; from far away the sea is the darkest.
    func testTheSquaresOfTheMap() {
        let side = 8
        var values = [Float](repeating: 0, count: side * side)
        for j in 0..<side { for i in 0..<side { values[j * side + i] = 1000 + Float(i) * 10 } }
        let fine = Relief.doubled(Relief.Heights(values: values, side: side))
        XCTAssertEqual(fine.side, 16)
        XCTAssertEqual(fine.values[8 * 16 + 7], 1032.5, accuracy: 0.01)
        XCTAssertEqual(fine.values[8 * 16 + 8], 1037.5, accuracy: 0.01)
        XCTAssertEqual(fine.values[0], 1000, accuracy: 0.01)
        let land = Relief.night(Relief.Heights(values: values, side: side), metersPerPixel: 400)
        let sea = Relief.night(Relief.Heights(values: [Float](repeating: 0, count: side * side), side: side), metersPerPixel: 400)
        XCTAssertGreaterThan(Int(land[2]), Int(sea[2]))
        XCTAssertEqual(sea[3], 255)
    }

    /// A picture of heights read back: 2000 m is red 135, green 208 in a terrarium square.
    func testHeightsFromAPicture() throws {
        let side = 4
        var bytes = [UInt8](repeating: 255, count: side * side * 4)
        for i in 0..<(side * side) { bytes[i * 4] = 135; bytes[i * 4 + 1] = 208; bytes[i * 4 + 2] = 0 }
        let png = try XCTUnwrap(Relief.png(bytes, side: side))
        let heights = try XCTUnwrap(Relief.heights(png: png))
        XCTAssertEqual(heights.side, side)
        XCTAssertEqual(heights.values[5], 2000, accuracy: 1)
        // A square of the map at the latitude of the Alps: about ten meters a point at zoom 14.
        XCTAssertEqual(Relief.metersPerPixel(z: 14, y: 5833, side: 256), 6.65, accuracy: 0.2)
    }

    /// The day over the pistes, and over the day what a screen draws of its own; a line of one
    /// point is not a line.
    func testTheLinesOfTheMap() {
        func track(_ kind: SegmentKind, _ n: Int) -> MapTrack {
            MapTrack(id: n, kind: kind, number: n, coordinates: (0..<4).map { CLLocationCoordinate2D(latitude: 45.9 + Double($0) * 0.001, longitude: 7.6) })
        }
        let more = [MapLine(coordinates: [CLLocationCoordinate2D(latitude: 45.9, longitude: 7.6), CLLocationCoordinate2D(latitude: 45.91, longitude: 7.61)],
                            color: .red, width: 6),
                    MapLine(coordinates: [CLLocationCoordinate2D(latitude: 45.9, longitude: 7.6)], color: .red, width: 6)]
        let lines = SnowMap.Coordinator.lines(terrain: nil, tracks: [track(.run, 1), track(.lift, 2)], more: more)
        // A run is two lines: its white edge, and over it the run.
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[0].width, 8.5)
        XCTAssertEqual(lines[1].width, 5)
        XCTAssertNil(lines[1].dash)
        XCTAssertEqual(lines[2].dash, [6, 6])
        XCTAssertEqual(lines[3].color, .red)
        XCTAssertEqual(lines[3].pointCount, 2)
        let faint = SnowMap.Coordinator.lines(terrain: nil, tracks: [track(.run, 1)], dimmed: true)
        XCTAssertEqual(faint[1].width, 3.5)
        // A run on a piste that is known takes its color.
        var red = track(.run, 3)
        red.difficulty = "intermediate"
        let colored = SnowMap.Coordinator.lines(terrain: nil, tracks: [red, track(.run, 4)])
        XCTAssertNotEqual(colored[1].color, colored[3].color)
        // Some points with room around them, and none.
        let fit = SnowMap.fit([CLLocationCoordinate2D(latitude: 45, longitude: 7), CLLocationCoordinate2D(latitude: 46, longitude: 9)], room: 2)
        XCTAssertEqual(fit?.center.longitude ?? 0, 8, accuracy: 0.001)
        XCTAssertEqual(fit?.span.latitudeDelta ?? 0, 2, accuracy: 0.001)
        XCTAssertNil(SnowMap.fit([]))
    }

    /// The column of buttons takes its width from a screen, less the band the screen already
    /// leaves free on its right edge.
    func testTheRightEdgeOfTheSheet() {
        XCTAssertEqual(Rail.reserved(band: 0), Rail.width)
        XCTAssertEqual(Rail.reserved(band: 20), Rail.width - 20)
        XCTAssertEqual(Rail.reserved(band: 73), 0)
    }

    /// Nine icons: each drawing, and the first of them in the other colors. Each has a name of
    /// its own, from which it is found again, and a small picture; the one the app comes with has
    /// no name.
    func testTheIconsToChooseFrom() {
        XCTAssertNil(IconArt.close.iconName(.night))
        XCTAssertEqual(IconArt.close.iconName(.aurora), "AppIcon-Aurora")
        XCTAssertEqual(IconArt.classic.iconName(.night), "AppIcon-Classica")
        XCTAssertEqual(IconArt.snow.iconName(.night), "AppIcon-SullaNeve")
        XCTAssertEqual(IconArt.close.preview(.night), "IconPreview-night")
        XCTAssertEqual(IconArt.mirror.preview(.night), "IconPreview-mirror-night")
        XCTAssertEqual(IconArt.label(.close, .night), "Primo piano")
        XCTAssertEqual(IconArt.label(.close, .forest), "Bosco")
        XCTAssertEqual(IconArt.label(.snow, .night), "Sulla neve")
        var names = Set<String>()
        for choice in IconArt.choices {
            let name = choice.art.iconName(choice.look)
            XCTAssertTrue(names.insert(name ?? "").inserted)
            let back = IconArt.parse(name)
            XCTAssertEqual(back.art, choice.art)
            XCTAssertEqual(back.look, choice.look)
            XCTAssertNotNil(UIImage(named: choice.art.preview(choice.look)), choice.art.preview(choice.look))
        }
        XCTAssertEqual(names.count, 9)
        XCTAssertEqual(IconArt.parse("AppIcon-Other").art, .close)
    }

    /// The ups and downs of a day, for its profile: as many as its stretches, each with where it
    /// began and ended; none for a day with no track.
    func testTheProfileOfADay() {
        let day = SkiDay(points: SkiSim.day(laps: 3, start: Date(timeIntervalSince1970: 1_800_000_000), seed: 3))
        let legs = Leg.of(day) ?? []
        XCTAssertEqual(legs.count, day.segments.count)
        XCTAssertEqual(legs.filter { $0.k == 0 }.count, day.runs.count)
        for leg in legs where leg.k == 0 { XCTAssertGreaterThan(leg.a, leg.b) }
        for leg in legs where leg.k == 1 { XCTAssertLessThan(leg.a, leg.b) }
        XCTAssertEqual(day.summary.shape, legs)
        let range = DayProfile.range(legs)
        XCTAssertNotNil(range)
        XCTAssertGreaterThan(range?.high ?? 0, range?.low ?? 0)
        XCTAssertNil(Leg.of(SkiDay(manual: Date(), duration: 3600, place: "A mano", sport: .ski, runs: 3, vertical: 900, distance: 5000, maxSpeed: 0)))
        // A ski area put on the map: all its lines in view, and the sheet asked to stand lower once.
        let place = PlacePin(id: "t", name: "Prova", lat: 45.9, lon: 7.6, days: 0)
        let before = Stage.shared.asks
        Stage.shared.show(place, terrain: nil)
        Stage.shared.show(place, terrain: Terrain.demo(lat: 45.9, lon: 7.6))
        XCTAssertEqual(Stage.shared.asks, before + 1)
        let region = Stage.region(of: place, terrain: Stage.shared.terrain)
        XCTAssertEqual(region.center.latitude, 45.9, accuracy: 0.05)
        Stage.shared.leave("other")
        XCTAssertNotNil(Stage.shared.place)
        Stage.shared.leave("t")
        XCTAssertNil(Stage.shared.place)
    }

    func testThePlacesBehindTheSheet() {
        func day(_ place: String, _ lat: Double?, _ lon: Double?, daysAgo: Double) -> DaySummary {
            DaySummary(id: UUID(), start: Date(timeIntervalSinceNow: -daysAgo * 86_400), end: Date(), place: place, stats: DayStats(),
                       sport: .ski, resort: nil, lat: lat, lon: lon, manual: nil)
        }
        // Newest first, as the library keeps them; two days a kilometer apart share a pin.
        let pins = PlacePin.of([day("Cervinia", 45.934, 7.63, daysAgo: 1), day("Livigno", 46.54, 10.14, daysAgo: 2),
                                day("Breuil", 45.94, 7.64, daysAgo: 3), day("A mano", nil, nil, daysAgo: 4)])
        XCTAssertEqual(pins.count, 2)
        XCTAssertEqual(pins.first { $0.days == 2 }?.name, "Cervinia")
        let region = PlacePin.region(pins)
        XCTAssertEqual(region.center.longitude, (7.63 + 10.14) / 2, accuracy: 0.01)
        XCTAssertGreaterThan(region.span.longitudeDelta, 2.5)
        // No place yet: the Alps.
        XCTAssertEqual(PlacePin.region([]).center.latitude, 46.3, accuracy: 0.01)
        // The winter map begins at the zoom of a valley.
        XCTAssertEqual(SnowMap.Coordinator.zoom(span: 360, width: 256), 0, accuracy: 0.001)
        XCTAssertGreaterThan(SnowMap.Coordinator.zoom(span: 0.05, width: 390), 10)
        XCTAssertLessThan(SnowMap.Coordinator.zoom(span: 5, width: 390), 10)
    }
}
