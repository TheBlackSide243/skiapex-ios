import AVFoundation
import MapKit
import XCTest
@testable import SkiApex

/// What came with 0.10.0: the pistes of a ski area you have done, the trophies, the run under way
/// against your best, and the film of a day.
final class SnowTests: XCTestCase {
    private let morning = Date(timeIntervalSince1970: 1_795_000_000)

    private func note(_ name: String, difficulty: String? = "easy") -> RunNote {
        RunNote(n: name, r: nil, d: difficulty, s: 120, v: 15, h: 300, m: 1500, t: morning)
    }

    private func summary(_ place: String, lat: Double = 45.93, lon: Double = 7.63, daysLater: Double = 0, hoursLater: Double = 0,
                         vertical: Double = 0, runs: Int = 0, speed: Double = 0, top: Double = 0, distance: Double = 0,
                         _ notes: [RunNote]? = nil) -> DaySummary {
        var stats = DayStats()
        stats.vertical = vertical
        stats.runs = runs
        stats.maxSpeed = speed
        stats.topAlt = top
        stats.runDistance = distance
        let start = morning.addingTimeInterval(daysLater * 86_400 + hoursLater * 3600)
        return DaySummary(id: UUID(), start: start, end: start.addingTimeInterval(3 * 3600), place: place, stats: stats,
                          lat: lat, lon: lon, pistes: notes)
    }

    // MARK: The pistes done

    func testThePistesOfASkiAreaYouHaveDone() throws {
        func way(_ name: String?, _ difficulty: String?, ref: String? = nil, kind: OSMWay.Kind = .piste, north: Double = 0) throws -> OSMWay {
            try XCTUnwrap(OSMWay(kind: kind, name: name, ref: ref, difficulty: difficulty,
                                 lats: [45.930 + north, 45.935 + north], lons: [7.630, 7.632]))
        }
        let ways = [try way("Ventina", "easy"), try way("Ventina", "easy", north: 0.005), try way("Gran Bosco", "intermediate"),
                    try way("Canalone", "advanced"), try way(nil, "easy"), try way("Funivia", nil, kind: .lift)]
        // One run followed two pistes; the black one was skied somewhere far from here.
        let days = [summary("Cervinia", [note("Ventina · Gran Bosco")]),
                    summary("Livigno", lat: 46.53, lon: 10.13, [note("Canalone", difficulty: "advanced")]),
                    summary("A mano", nil)]
        let skied = Completion.skied(days, nearLat: 45.93, lon: 7.63)
        XCTAssertEqual(skied, ["ventina", "gran bosco"])

        let tally = Completion.tally(ways, skied: skied)
        XCTAssertEqual(tally.total, 3, "each name once; no lifts, no pistes without a name")
        XCTAssertEqual(tally.done, 2)
        XCTAssertEqual(tally.fraction, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertFalse(tally.complete)
        XCTAssertEqual(tally.missing.map(\.label), ["Canalone"])
        XCTAssertEqual(tally.pistes.map(\.label), ["Canalone", "Gran Bosco", "Ventina"], "the ones to ski first")
        let ventina = try XCTUnwrap(tally.pistes.first { $0.label == "Ventina" })
        XCTAssertEqual(ventina.meters, ways[0].meters + ways[1].meters, accuracy: 0.5, "its stretches together")
        XCTAssertEqual(tally.byDifficulty, [PisteTally.Grade(difficulty: "easy", done: 1, total: 1),
                                            PisteTally.Grade(difficulty: "intermediate", done: 1, total: 1),
                                            PisteTally.Grade(difficulty: "advanced", done: 0, total: 1)])

        XCTAssertTrue(Completion.tally(ways, skied: ["ventina", "gran bosco", "canalone"]).complete)
        XCTAssertEqual(Completion.tally(ways, skied: []).done, 0)
        XCTAssertEqual(Completion.tally([], skied: skied), PisteTally())
        XCTAssertEqual(Completion.key("  Gran Bosco "), "gran bosco")
    }

    // MARK: Trophies

    func testTrophiesAreEarnedOnTheDayThatReachesThem() throws {
        let first = summary("Cervinia", vertical: 5200, runs: 21, speed: 17, top: 3100, distance: 40_000,
                            [note("Canalone", difficulty: "advanced")])
        let again = summary("Cervinia", hoursLater: 4, vertical: 300, runs: 2, speed: 9, top: 2500, distance: 2000)
        let second = summary("Livigno", daysLater: 1, vertical: 4000, runs: 12, speed: 15, top: 2800, distance: 30_000)
        let third = summary("Bormio", daysLater: 2, vertical: 3000, runs: 9, speed: 14, top: 2900, distance: 25_000)
        let days = [third, first, again, second]
        let all = Trophies.all(days)
        XCTAssertEqual(all.count, Trophies.goals.count)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        func trophy(_ id: String) throws -> Trophy { try XCTUnwrap(all.first { $0.id == id }) }

        XCTAssertEqual(try trophy("days1").earned, first.start)
        XCTAssertEqual(try trophy("speed60").earned, first.start, "17 m/s is 61 km/h")
        XCTAssertNil(try trophy("speed80").earned)
        XCTAssertEqual(try trophy("speed80").progress, 61.2 / 80, accuracy: 0.001)
        XCTAssertEqual(try trophy("dayv5").earned, first.start)
        XCTAssertEqual(try trophy("runs20").earned, first.start)
        XCTAssertEqual(try trophy("alt3000").earned, first.start)
        XCTAssertEqual(try trophy("black1").earned, first.start)
        XCTAssertEqual(try trophy("everest").earned, second.start, "5200, 300 and 4000 pass 8849")
        XCTAssertEqual(try trophy("streak3").earned, third.start)
        XCTAssertEqual(try trophy("places3").earned, third.start)
        XCTAssertEqual(try trophy("days10").progress, 0.3, accuracy: 0.001, "two recordings of one day are one day")
        XCTAssertFalse(try trophy("days10").done)
        XCTAssertEqual(try trophy("km100").progress, 0.97, accuracy: 0.001)

        XCTAssertEqual(Set(Trophies.earned(on: first, among: days).map(\.id)), ["days1", "speed60", "dayv5", "runs20", "alt3000", "black1"])
        XCTAssertEqual(Trophies.earned(on: again, among: days), [])
        XCTAssertTrue(Trophies.all([]).allSatisfy { !$0.done && $0.progress == 0 })
        // A day between two others breaks nothing; a day missing breaks the days in a row.
        let later = summary("Bormio", daysLater: 5)
        XCTAssertNil(Trophies.all([first, second, later]).first { $0.id == "streak3" }?.earned)
    }

    // MARK: Against your best

    /// A run straight down to the south: a point every two seconds, twenty meters apart.
    private func lap(_ name: String, lon: Double = 7.63, count: Int = 60, step: Double = 2) -> GhostLap {
        let points = (0..<count).map { i in
            TrackPoint(t: morning.addingTimeInterval(Double(i) * step), lat: 45.94 - Double(i) * 20 / 111_320, lon: lon, alt: 2800 - Double(i) * 6,
                       speed: 10, hAcc: 5, sAcc: 1)
        }
        return GhostLap(id: name, name: name, seconds: Double(count - 1) * step, date: morning, points: points)
    }

    private func at(_ lap: GhostLap, _ index: Int, after seconds: Double, east: Double = 0) -> TrackPoint {
        var point = lap.points[index]
        point.t = morning.addingTimeInterval(86_400 + seconds)
        point.lon += east / (111_320 * cos(45.94 * .pi / 180))
        return point
    }

    func testTheRunUnderWayAgainstYourBest() throws {
        let best = lap("Ventina")
        // From the top to halfway in 55 seconds, where the best run took 60: five ahead.
        var standing = try XCTUnwrap(Ghost.standing(start: at(best, 0, after: 0), now: at(best, 30, after: 55), among: [best]))
        XCTAssertEqual(standing.delta, -5, accuracy: 0.001)
        XCTAssertTrue(standing.ahead)
        XCTAssertEqual(standing.name, "Ventina")
        XCTAssertEqual(standing.best, 118)
        XCTAssertEqual(standing.share, 60.0 / 118.0, accuracy: 0.001)
        // In 66: six behind. A few meters to the side change nothing.
        standing = try XCTUnwrap(Ghost.standing(start: at(best, 0, after: 0, east: 15), now: at(best, 30, after: 66, east: -12), among: [best]))
        XCTAssertEqual(standing.delta, 6, accuracy: 0.001)
        XCTAssertFalse(standing.ahead)
        // A run begun lower down is measured from there.
        standing = try XCTUnwrap(Ghost.standing(start: at(best, 10, after: 0), now: at(best, 40, after: 60.2), among: [best]))
        XCTAssertTrue(standing.even)
        // Off the piste, or begun somewhere else: nothing to say.
        XCTAssertNil(Ghost.standing(start: at(best, 0, after: 0), now: at(best, 30, after: 55, east: 400), among: [best]))
        XCTAssertNil(Ghost.standing(start: at(best, 0, after: 0, east: 400), now: at(best, 30, after: 55), among: [best]))
        XCTAssertNil(Ghost.standing(start: at(best, 0, after: 0), now: at(best, 30, after: 55), among: []))
        // Between two pistes side by side, the one the run began on.
        let other = lap("Gran Bosco", lon: 7.6306, step: 3)
        standing = try XCTUnwrap(Ghost.standing(start: at(other, 0, after: 0), now: at(other, 20, after: 50), among: [best, other]))
        XCTAssertEqual(standing.name, "Gran Bosco")
        XCTAssertEqual(standing.delta, -10, accuracy: 0.001)

        // One point every two seconds, with the first and the last.
        let dense = lap("Fitta", count: 10, step: 1).points
        let thin = Ghost.thin(dense)
        XCTAssertEqual(thin.map { Int($0.t.timeIntervalSince(morning)) }, [0, 2, 4, 6, 8, 9])
        XCTAssertEqual(Ghost.thin([]), [])
        XCTAssertTrue(Ghost.text(-3.24).hasSuffix(" s"))
        XCTAssertEqual(Ghost.text(75), Fmt.lap(75))
    }

    func testYourBestRunsAreReadFromTheDiary() throws {
        var day = SkiDay(points: SkiSim.day(laps: 3, seed: 41))
        for i in day.segments.indices where day.segments[i].kind == .run { day.segments[i].name = "Ventina" }
        let kept = day.summary
        let lat = try XCTUnwrap(kept.lat), lon = try XCTUnwrap(kept.lon)
        XCTAssertFalse((kept.pistes ?? []).isEmpty)
        var asked = 0
        let laps = Ghost.laps(nearLat: lat, lon: lon, days: [kept]) { id in
            asked += 1
            return id == day.id ? day : nil
        }
        XCTAssertEqual(asked, 1, "each day is read once")
        let lap = try XCTUnwrap(laps.first)
        XCTAssertEqual(laps.count, 1)
        XCTAssertEqual(lap.name, "Ventina")
        XCTAssertGreaterThan(lap.points.count, 5)
        let entry = try XCTUnwrap(PisteBook.entries([kept]).first)
        XCTAssertEqual(lap.seconds, entry.best?.seconds)
        // The best run against itself: neither ahead nor behind, all of it.
        let standing = try XCTUnwrap(Ghost.standing(start: lap.points[0], now: lap.points[lap.points.count - 1], among: laps))
        XCTAssertTrue(standing.even)
        XCTAssertEqual(standing.share, 1, accuracy: 0.001)
        // Nothing around a place far away, and nothing when the day is gone.
        XCTAssertTrue(Ghost.laps(nearLat: 46.5, lon: 10.1, days: [kept]) { _ in day }.isEmpty)
        XCTAssertTrue(Ghost.laps(nearLat: lat, lon: lon, days: [kept]) { _ in nil }.isEmpty)
    }

    // MARK: The film of a day

    func testTheFilmOfADay() async throws {
        XCTAssertEqual(DayFilm.frames, 264)
        XCTAssertEqual(DayFilm.progress(at: 0), 0)
        XCTAssertEqual(DayFilm.progress(at: 105), 0.5, accuracy: 0.001)
        XCTAssertEqual(DayFilm.progress(at: 210), 1)
        XCTAssertEqual(DayFilm.progress(at: 263), 1)
        XCTAssertLessThan(DayFilm.progress(at: 30), DayFilm.progress(at: 60))

        let day = SkiDay(points: SkiSim.day(laps: 2, seed: 42))
        let tracks = MapTrack.build(points: day.points, segments: day.segments, maxPoints: 160).filter { $0.kind != .idle }
        let box = CGRect(x: 70, y: 280, width: 580, height: 680)
        let lines = DayFilm.lines(tracks, place: DayFilm.fit(tracks, in: box))
        XCTAssertEqual(lines.count, tracks.count)
        XCTAssertTrue(lines.contains { $0.run })
        XCTAssertTrue(lines.flatMap(\.points).allSatisfy { box.insetBy(dx: -1, dy: -1).contains($0) }, "the whole track is on the frame")

        // Its last frame as a picture, for while the film is made.
        XCTAssertEqual(DayFilm.still(day)?.size, DayFilm.size)

        // The film itself, without the map and short: its length and its shape.
        XCTAssertEqual(DayFilm.frames(drawing: 1, holding: 0.2), 36)
        XCTAssertEqual(DayFilm.progress(at: 15, drawing: 1), 0.5, accuracy: 0.001)
        var told: [Double] = []
        let url = try await DayFilm.make(day, mapped: false, drawing: 1, holding: 0.2) { told.append($0) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(told.last, 1)
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 1.2, accuracy: 0.2)
        let videos = try await asset.loadTracks(withMediaType: .video)
        let video = try XCTUnwrap(videos.first)
        let size = try await video.load(.naturalSize)
        XCTAssertEqual(size, DayFilm.size)
        try? FileManager.default.removeItem(at: url)

        // A day written by hand has no track to draw.
        do {
            let manual = SkiDay(manual: morning, duration: 4 * 3600, place: "A mano", sport: .ski, runs: 9, vertical: 3000,
                                distance: 15_000, maxSpeed: 0)
            _ = try await DayFilm.make(manual, mapped: false)
            XCTFail("a film of nothing")
        } catch DayFilm.Failure.noTrack {
        }
    }
}
