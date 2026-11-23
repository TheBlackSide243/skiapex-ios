import XCTest
@testable import Carve

final class SegmenterTests: XCTestCase {
    func testMadeUpDayHasEveryRunAndLift() {
        for laps in [1, 4, 8] {
            let points = SkiSim.day(laps: laps, seed: UInt64(laps))
            let day = SkiDay(points: points)
            XCTAssertEqual(day.stats.runs, laps, "runs with \(laps) laps")
            XCTAssertEqual(day.stats.lifts, laps, "lifts with \(laps) laps")
            // 730 m a lap; the edges of each run are a little blurred by the smoothing.
            XCTAssertEqual(day.stats.vertical, Double(laps) * 730, accuracy: Double(laps) * 730 * 0.12)
            XCTAssertGreaterThan(day.stats.maxSpeed, 10)
            XCTAssertLessThan(day.stats.maxSpeed, 25)
        }
    }

    func testStopHalfWayStaysInsideTheRun() {
        // Every run stops for 30 s half way.
        let day = SkiDay(points: SkiSim.day(laps: 3, seed: 3, stopEvery: 1))
        XCTAssertEqual(day.stats.runs, 3)
    }

    func testRunsAndLiftsTakeTurns() {
        let day = SkiDay(points: SkiSim.day(laps: 5, seed: 9))
        let kinds = day.segments.map(\.kind).filter { $0 != .idle }
        XCTAssertEqual(kinds, Array(repeating: [SegmentKind.lift, .run], count: 5).flatMap { $0 })
        for seg in day.segments where seg.kind == .run {
            XCTAssertGreaterThan(seg.drop, 600)
            XCTAssertGreaterThan(seg.slope, 5)
        }
    }

    func testStandingStillIsNotSkiing() {
        let start = Date()
        var points: [TrackPoint] = []
        var rng = SkiSim.Random(state: 1)
        for i in 0..<1200 {
            points.append(TrackPoint(t: start.addingTimeInterval(Double(i)), lat: 46 + rng.gauss() * 0.00003, lon: 7 + rng.gauss() * 0.00003,
                                     alt: 2000 + rng.gauss() * 3, speed: abs(rng.gauss()) * 0.4, hAcc: 8, sAcc: 1))
        }
        let day = SkiDay(points: points)
        XCTAssertEqual(day.stats.runs, 0)
        XCTAssertEqual(day.stats.lifts, 0)
    }

    func testGpsJumpIsDropped() {
        var points = SkiSim.day(laps: 1, seed: 4)
        points[500].lat += 0.05 // 5 km away for one second
        let clean = Segmenter.clean(points)
        XCTAssertEqual(clean.count, points.count - 1)
    }

    func testLibraryKeepsDays() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = Library(directory: dir)
        let day = SkiDay(points: SkiSim.day(laps: 2, seed: 2), place: "Prova")
        try library.save(day)
        let again = Library(directory: dir)
        XCTAssertEqual(again.days.count, 1)
        XCTAssertEqual(again.day(day.id)?.stats.runs, day.stats.runs)
        again.rename(day.id, to: "Altrove")
        XCTAssertEqual(Library(directory: dir).days.first?.place, "Altrove")
        again.delete(day.id)
        XCTAssertTrue(Library(directory: dir).days.isEmpty)
    }

    func testJournalComesBack() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let journal = Journal(directory: dir)
        journal.begin()
        let points = Array(SkiSim.day(laps: 1, seed: 6).prefix(50))
        points.forEach(journal.append)
        XCTAssertEqual(Journal(directory: dir).load()?.count, 50)
        journal.finish()
        XCTAssertNil(Journal(directory: dir).load())
    }

    func testGpxHasEveryPoint() {
        let day = SkiDay(points: SkiSim.day(laps: 1, seed: 8))
        let gpx = GPX.document(day)
        XCTAssertEqual(gpx.components(separatedBy: "<trkpt").count - 1, day.points.count)
        XCTAssertTrue(gpx.hasSuffix("</gpx>\n"))
    }

    func testSeasonRunsFromJulyToJune() {
        var c = DateComponents()
        c.year = 2027; c.month = 2; c.day = 10
        let feb = Calendar.current.date(from: c)!
        c.year = 2026; c.month = 12
        let dec = Calendar.current.date(from: c)!
        XCTAssertEqual(Season(feb), Season(dec))
        XCTAssertEqual(Season(dec).label, "2026/27")
    }
}
