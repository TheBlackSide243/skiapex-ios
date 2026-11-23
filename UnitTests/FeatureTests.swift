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

    func testBackupBringsTheDaysBack() throws {
        let here = Library(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let first = SkiDay(points: SkiSim.day(laps: 2, seed: 31), place: "Uno")
        let start = Date(timeIntervalSinceNow: -30 * 86_400)
        try here.save(first)
        try here.save(SkiDay(points: SkiSim.day(laps: 1, start: start, seed: 32), place: "Due"))
        let zip = try here.exportBackup()

        let there = Library(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        XCTAssertEqual(try there.restore(from: zip), 2)
        XCTAssertEqual(try there.restore(from: zip), 0, "the days already there are left alone")
        XCTAssertEqual(there.days.count, 2)
        XCTAssertEqual(there.day(first.id)?.stats.runs, 2)
        XCTAssertEqual(there.day(first.id)?.points.count, first.points.count)
        XCTAssertThrowsError(try there.restore(from: GPX.file(first)), "a GPX is not a backup")
    }

    func testLiveActivityWordsFollowTheUnits() {
        var state = SkiActivityAttributes.ContentState(phase: "run", runs: 3, vertical: 1000, maxSpeed: 20, metric: true)
        XCTAssertEqual(state.verticalText, "1000 m")
        XCTAssertEqual(state.maxSpeedText, "72 km/h")
        XCTAssertEqual(state.symbol, "figure.skiing.downhill")
        state.metric = false
        XCTAssertEqual(state.verticalText, "3281 ft")
        XCTAssertEqual(state.maxSpeedText, "45 mph")
    }

    func testSkiAreasOutOfTheAnswers() throws {
        let features: [[String: Any]] = [
            ["properties": ["name": "Livigno", "state": "Lombardia", "country": "Italia", "osm_type": "W", "osm_id": 42] as [String: Any],
             "geometry": ["coordinates": [10.1357, 46.5386]]],
            ["properties": ["name": "Livigno", "osm_type": "W", "osm_id": 42] as [String: Any], "geometry": ["coordinates": [10.1357, 46.5386]]],
            ["properties": ["state": "Nowhere"], "geometry": ["coordinates": [1.0, 2.0]]],
        ]
        let found = try Resorts.parsePhoton(JSONSerialization.data(withJSONObject: ["features": features]))
        XCTAssertEqual(found.count, 1, "the same place once, and nothing without a name")
        XCTAssertEqual(found.first?.region, "Lombardia, Italia")
        XCTAssertEqual(found.first?.lat ?? 0, 46.5386, accuracy: 0.0001)

        let elements: [[String: Any]] = [
            ["type": "relation", "id": 7, "tags": ["site": "piste", "name": "Lontana"], "center": ["lat": 46.9, "lon": 7.6]],
            ["type": "way", "id": 8, "tags": ["landuse": "winter_sports", "name": "Vicina"], "center": ["lat": 45.94, "lon": 7.63]],
            ["type": "way", "id": 9, "tags": ["landuse": "winter_sports", "name": "Vicina"], "center": ["lat": 45.95, "lon": 7.64]],
            ["type": "node", "id": 10, "tags": ["landuse": "winter_sports"], "lat": 45.9, "lon": 7.6],
        ]
        let near = try Resorts.parseOverpass(JSONSerialization.data(withJSONObject: ["elements": elements]), lat: 45.93, lon: 7.63)
        XCTAssertEqual(near.map(\.name), ["Vicina", "Lontana"])
        XCTAssertEqual(near.first?.id, "W8")
    }

    func testForecastDayByDay() throws {
        // Two days at a resort one hour ahead of GMT.
        let midnight = 1_800_000_000.0 - 3600
        let daily: [String: Any] = [
            "time": [midnight, midnight + 86_400], "snowfall_sum": [12.5, NSNull()] as [Any], "temperature_2m_min": [-8.0, -3.0],
            "temperature_2m_max": [-1.0, 2.0], "wind_speed_10m_max": [20.0, 55.0], "weather_code": [73, 3]]
        let answer: [String: Any] = ["utc_offset_seconds": 3600, "daily": daily]
        let data = try JSONSerialization.data(withJSONObject: answer)
        let days = try Resorts.parseForecast(data)
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].date.timeIntervalSince1970, 1_800_000_000, "read in GMT, it is the date at the resort")
        XCTAssertEqual(days[0].snow, 12.5)
        XCTAssertEqual(days[0].symbol, "cloud.snow")
        XCTAssertFalse(days[0].windy)
        XCTAssertEqual(days[1].snow, 0, "no number is no snow")
        XCTAssertTrue(days[1].windy)
    }

    func testManualDaysTripsAndFavoritesAreKept() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = Library(directory: dir)
        let manual = SkiDay(manual: Date(timeIntervalSinceNow: -86_400), duration: 4 * 3600, place: "A mano", sport: .snowboard,
                            runs: 9, vertical: 3000, distance: 15_000, maxSpeed: 0)
        try library.save(manual)
        try library.save(SkiDay(points: SkiSim.day(laps: 1, seed: 41), place: "Con traccia"))
        let resort = Resort(id: "W1", name: "Prova", region: nil, lat: 45.9336, lon: 7.6295)
        library.toggleFavorite(resort)
        library.saveTrip(Trip(name: "Passato", start: Date(timeIntervalSinceNow: -10 * 86_400), end: Date(timeIntervalSinceNow: -8 * 86_400)))
        library.saveTrip(Trip(name: "Futuro", start: Date(timeIntervalSinceNow: 5 * 86_400), end: Date(timeIntervalSinceNow: 7 * 86_400), resort: resort))

        let again = Library(directory: dir)
        XCTAssertEqual(again.days.count, 2)
        let written = try XCTUnwrap(again.days.first { $0.manual == true })
        XCTAssertEqual(written.stats.runs, 9)
        XCTAssertNil(written.coordinate, "no track, no pin")
        XCTAssertNotNil(again.days.first { $0.manual != true }?.coordinate)
        XCTAssertEqual(again.day(manual.id)?.sport, .snowboard)
        XCTAssertTrue(again.isFavorite(resort))
        XCTAssertEqual(again.upcomingTrips.map(\.name), ["Futuro"])
        XCTAssertEqual(again.trips.count, 2)
        XCTAssertEqual(again.days(near: resort).count, 1, "the made-up day is at this very place")
        again.toggleFavorite(resort)
        again.deleteTrip(again.trips[0].id)
        XCTAssertFalse(Library(directory: dir).isFavorite(resort))
        XCTAssertEqual(Library(directory: dir).trips.count, 1)
        XCTAssertEqual(ManualDayView.number("12,5"), 12.5)
        XCTAssertEqual(ManualDayView.number(""), 0)
        XCTAssertNil(ManualDayView.number("tanti"))
    }

    func testLeaderboardPlacesAndWhatIsShared() throws {
        func row(_ name: String, days: Int, vertical: Double, me: Bool = false) -> BoardRow {
            BoardRow(id: name, name: name, me: me, days: days, vertical: vertical, runs: days * 10, distance: vertical * 4, time: 0, maxSpeed: 15)
        }
        let rows = [row("Luca", days: 6, vertical: 9000), row("Marco", days: 9, vertical: 5000, me: true), row("Anna", days: 6, vertical: 12_000)]
        XCTAssertEqual(BoardMetric.days.ranked(rows).map(\.row.name), ["Marco", "Anna", "Luca"])
        XCTAssertEqual(BoardMetric.days.ranked(rows).map(\.place), [1, 2, 2], "the same number, the same place")
        XCTAssertEqual(BoardMetric.vertical.ranked(rows).map(\.row.name), ["Anna", "Luca", "Marco"])
        XCTAssertEqual(BoardMetric.maxSpeed.ranked(rows).map(\.place), [1, 1, 1])

        // Of a day only when and its numbers are sent: not where.
        let day = SkiDay(points: SkiSim.day(laps: 2, seed: 51), place: "Posto segreto")
        let sent = Social.shared(day.summary)
        XCTAssertEqual(Set(sent.keys), ["date", "vertical", "runs", "distance", "time", "maxSpeed"])
        XCTAssertEqual(sent["runs"] as? Int, 2)
        XCTAssertEqual((sent["date"] as? String)?.count, 10)
        XCTAssertFalse(String(data: try JSONSerialization.data(withJSONObject: sent), encoding: .utf8)?.contains("segreto") ?? true)
    }

    func testDaysSavedByTheFirstVersionStillOpen() throws {
        let day = SkiDay(points: SkiSim.day(laps: 1, seed: 17), place: "Vecchia")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(day)) as? [String: Any])
        for key in ["sport", "resort", "weather", "mapped", "inHealth", "heartAvg", "heartMax", "manual"] { json[key] = nil }
        json["segments"] = (json["segments"] as? [[String: Any]])?.map { segment in
            segment.filter { $0.key != "name" && $0.key != "difficulty" }
        }
        let old = try JSONDecoder().decode(SkiDay.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.stats.runs, 1)
        XCTAssertNil(old.sport)
        XCTAssertEqual(old.title, "Vecchia")
    }
}
