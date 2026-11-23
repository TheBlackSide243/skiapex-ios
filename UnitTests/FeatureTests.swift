import XCTest
@testable import SkiApex

/// What came with 0.2.0: names from OpenStreetMap, weather, GPX import, the speed along a run.
final class FeatureTests: XCTestCase {
    /// An answer of Overpass made of the day itself: its first run as a piste, the line of its
    /// first lift as a chairlift, a ski area around them.
    private func overpass(for day: SkiDay) throws -> Data {
        func geometry(_ segment: Segment, every step: Int) -> [[String: Double]] {
            stride(from: segment.start, through: segment.end, by: step).map { ["lat": day.points[$0].lat, "lon": day.points[$0].lon] }
        }
        let run = try XCTUnwrap(day.runs.first)
        let lift = try XCTUnwrap(day.segments.first { $0.kind == .lift })
        let top = try XCTUnwrap(day.points.max { $0.alt < $1.alt })
        let elements: [[String: Any]] = [
            ["type": "way", "id": 1, "tags": ["piste:type": "downhill", "name": "Pista Prova", "piste:difficulty": "intermediate"],
             "geometry": geometry(run, every: 10)],
            ["type": "way", "id": 2, "tags": ["aerialway": "chair_lift", "name": "Seggiovia Prova"],
             "geometry": geometry(lift, every: 30)],
            ["type": "way", "id": 3, "tags": ["aerialway": "station"], "geometry": geometry(lift, every: 30)],
            ["type": "relation", "id": 4, "tags": ["site": "piste", "name": "Comprensorio Prova"],
             "center": ["lat": top.lat, "lon": top.lon]],
            ["type": "relation", "id": 5, "tags": ["landuse": "winter_sports", "name": "Lontano"],
             "center": ["lat": top.lat + 1, "lon": top.lon]],
        ]
        return try JSONSerialization.data(withJSONObject: ["elements": elements])
    }

    func testRunsAndLiftsTakeTheirNames() throws {
        var day = SkiDay(points: SkiSim.day(laps: 4, seed: 21))
        let map = try Pistes.parse(overpass(for: day))
        XCTAssertEqual(map.ways.count, 2, "the station is not a lift")
        Pistes.apply(map, to: &day)
        XCTAssertEqual(day.runs.first?.name, "Pista Prova")
        XCTAssertEqual(day.runs.first?.difficulty, "intermediate")
        for lift in day.segments where lift.kind == .lift {
            XCTAssertEqual(lift.name, "Seggiovia Prova")
        }
        XCTAssertEqual(day.resort, "Comprensorio Prova")
        // Nothing nearby: no names, and the ones there are taken off.
        Pistes.apply(ResortMap(), to: &day)
        XCTAssertNil(day.runs.first?.name)
        XCTAssertNotNil(Pistes.query(for: day.points))
    }

    func testDistanceToALine() throws {
        // A line 1 km long going north.
        let way = try XCTUnwrap(OSMWay(kind: .piste, name: nil, ref: "12", difficulty: nil,
                                       lats: [46.0, 46.0 + 1000 / 111_320.0], lons: [7.0, 7.0]))
        let east = 100 / (111_320.0 * cos(46.0 * .pi / 180))
        XCTAssertEqual(way.distance(lat: 46.004, lon: 7.0 + east), 100, accuracy: 1)
        XCTAssertEqual(way.distance(lat: 46.0 - 50 / 111_320.0, lon: 7.0), 50, accuracy: 1)
        XCTAssertTrue(way.mayBeNear(lat: 46.004, lon: 7.0 + east, meters: 120))
        XCTAssertFalse(way.mayBeNear(lat: 46.004, lon: 7.0 + east * 3, meters: 120))
        XCTAssertNotNil(way.label)
    }

    func testGpxComesBackAsTheSameDay() {
        let day = SkiDay(points: SkiSim.day(laps: 3, seed: 14))
        let points = GPXImport.points(from: Data(GPX.document(day).utf8))
        XCTAssertEqual(points.count, day.points.count)
        let again = SkiDay(points: points)
        XCTAssertEqual(again.stats.runs, day.stats.runs)
        XCTAssertEqual(again.stats.lifts, day.stats.lifts)
        XCTAssertEqual(again.stats.vertical, day.stats.vertical, accuracy: day.stats.vertical * 0.05)
        XCTAssertEqual(again.stats.maxSpeed, day.stats.maxSpeed, accuracy: day.stats.maxSpeed * 0.3)
        XCTAssertTrue(GPXImport.points(from: Data("not a gpx".utf8)).isEmpty)
    }

    func testImportRefusesTheSameFileTwice() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = Library(directory: dir)
        let file = try GPX.file(SkiDay(points: SkiSim.day(laps: 2, seed: 15)))
        let id = try library.importGPX(file)
        XCTAssertEqual(library.day(id)?.stats.runs, 2)
        XCTAssertThrowsError(try library.importGPX(file))
        XCTAssertEqual(library.days.count, 1)
        library.setSport(id, to: .snowboard)
        XCTAssertEqual(Library(directory: dir).days.first?.sport, .snowboard)
    }

    func testWeatherOfTheHoursOnTheSnow() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000) // on the hour
        let end = start.addingTimeInterval(5 * 3600)
        // From 30 hours before the start to 3 after the end: colder at night, snow before dawn.
        var times: [Double] = [], temps: [Any] = [], snow: [Any] = [], wind: [Any] = [], codes: [Any] = []
        for h in -30...8 {
            times.append(start.timeIntervalSince1970 + Double(h) * 3600)
            temps.append(h >= 0 && h <= 5 ? -5.0 + Double(h) : -15.0)
            snow.append(h >= -6 && h < 0 ? 2.0 : 0.0)
            wind.append(h == 3 ? 40.0 : 10.0)
            if h == 6 { codes.append(NSNull()) } else { codes.append(h >= 0 && h <= 4 ? 71 : 0) }
        }
        let data = try JSONSerialization.data(withJSONObject: ["hourly": [
            "time": times, "temperature_2m": temps, "snowfall": snow, "wind_speed_10m": wind, "weather_code": codes]])
        let weather = try Weather.parse(data, start: start, end: end)
        XCTAssertEqual(weather.tempMin, -15, "the hour before the start counts")
        XCTAssertEqual(weather.tempMax, 0)
        XCTAssertEqual(weather.snowfall, 12, accuracy: 0.01)
        XCTAssertEqual(weather.windMax, 40)
        XCTAssertEqual(weather.code, 71)
        XCTAssertEqual(weather.symbol, "cloud.snow")
        XCTAssertThrowsError(try Weather.parse(Data("{}".utf8), start: start, end: end))
    }

    func testSpeedAlongARunHasNoHoles() throws {
        let day = SkiDay(points: SkiSim.day(laps: 1, seed: 16))
        let run = try XCTUnwrap(day.runs.first)
        let chunks = SpeedChunk.make(day.points[run.start...run.end], top: run.maxSpeed)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.coordinates.count > 1 && (0..<Theme.speedColors.count).contains($0.bucket) })
        // Each piece starts where the one before ends.
        for (a, b) in zip(chunks, chunks.dropFirst()) {
            XCTAssertEqual(a.coordinates.last?.latitude, b.coordinates.first?.latitude)
        }
    }

    func testDaysSavedByTheFirstVersionStillOpen() throws {
        let day = SkiDay(points: SkiSim.day(laps: 1, seed: 17), place: "Vecchia")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(day)) as? [String: Any])
        for key in ["sport", "resort", "weather", "mapped"] { json[key] = nil }
        json["segments"] = (json["segments"] as? [[String: Any]])?.map { segment in
            segment.filter { $0.key != "name" && $0.key != "difficulty" }
        }
        let old = try JSONDecoder().decode(SkiDay.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.stats.runs, 1)
        XCTAssertNil(old.sport)
        XCTAssertEqual(old.title, "Vecchia")
    }
}
