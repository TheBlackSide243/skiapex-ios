import MapKit
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
