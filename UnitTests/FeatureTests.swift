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

    func testFriendsLiveAsTheServerSendsThem() throws {
        struct Answer: Decodable { let friends: [LiveFriend] }
        let json = """
        {"friends":[{"id":"a","name":"Anna Rossi","lat":45.9336,"lon":7.6295,"alt":2500,"speed":12.5,"phase":"run","at":1800000000000},
                    {"id":"b","name":"luca","lat":45.94,"lon":7.63,"alt":2100,"speed":0,"phase":"altro","at":1800000030000}]}
        """
        let friends = try JSONDecoder().decode(Answer.self, from: Data(json.utf8)).friends
        XCTAssertEqual(friends.count, 2)
        XCTAssertEqual(friends[0].initials, "AR")
        XCTAssertEqual(friends[1].initials, "LU")
        XCTAssertEqual(friends[0].phaseLabel, "In pista")
        XCTAssertEqual(friends[1].phaseLabel, "Fermo", "anything unknown is standing")
        XCTAssertEqual(friends[0].date.timeIntervalSince1970, 1_800_000_000)
        XCTAssertEqual(friends[0].coordinate.latitude, 45.9336, accuracy: 0.00001)
    }

    func testAFriendCloseIsAnnouncedOnce() {
        let now = Date()
        func friend(_ id: String, metersNorth: Double, secondsAgo: Double = 10) -> LiveFriend {
            LiveFriend(id: id, name: id, lat: 46.0 + metersNorth / 111_320, lon: 7.0, alt: 2000, speed: 5, phase: "run",
                       at: (now.timeIntervalSince1970 - secondsAgo) * 1000)
        }
        XCTAssertEqual(Nearby.range(120), .close)
        XCTAssertEqual(Nearby.range(2500), .area)
        XCTAssertEqual(Nearby.range(40_000), .far)
        let friends = [friend("vicino", metersNorth: 150), friend("zona", metersNorth: 3000), friend("lontano", metersNorth: 50_000),
                       friend("vecchio", metersNorth: 100, secondsAgo: 600)]
        let first = Nearby.notices(lat: 46.0, lon: 7.0, friends: friends, now: now, told: [:])
        XCTAssertEqual(first.map(\.key), ["vicino:close", "zona:area"], "the far one and the stale one say nothing")
        XCTAssertEqual(first[0].meters, 150, accuracy: 2)
        // Told a moment ago: quiet. Twenty minutes later the close one is said again, the area one not yet.
        var told: [String: Date] = [:]
        for notice in first { told[notice.key] = now }
        XCTAssertTrue(Nearby.notices(lat: 46.0, lon: 7.0, friends: friends, now: now.addingTimeInterval(60), told: told).isEmpty)
        let later = now.addingTimeInterval(21 * 60)
        let again = friends.filter { $0.id != "vecchio" }.map { friend($0.id, metersNorth: ($0.lat - 46.0) * 111_320, secondsAgo: -21 * 60 + 10) }
        XCTAssertEqual(Nearby.notices(lat: 46.0, lon: 7.0, friends: again, now: later, told: told).map(\.key), ["vicino:close"])
        // A friend announced as close who moves away is not announced as "in the area" right after.
        let away = [friend("vicino", metersNorth: 2000)]
        XCTAssertTrue(Nearby.notices(lat: 46.0, lon: 7.0, friends: away, now: now.addingTimeInterval(60), told: told).isEmpty)
    }

    func testTheWayGoesDownThePistesAndUpTheLifts() throws {
        let terrain = Terrain.demo(lat: 45.93, lon: 7.63)
        let graph = RouteGraph(ways: terrain.ways)
        func way(_ name: String) throws -> OSMWay { try XCTUnwrap(terrain.ways.first { $0.name == name }) }
        let gondola = try way("Cabinovia Cima Bianca")
        // A lift starts at its bottom, a piste at its top.
        let village = (gondola.lats[0], gondola.lons[0])
        let top = (try way("Canalone").lats[0], try way("Canalone").lons[0])
        let west = (try way("Gran Bosco").lats[0], try way("Gran Bosco").lons[0])

        let up = try XCTUnwrap(graph.route(fromLat: village.0, fromLon: village.1, toLat: top.0, toLon: top.1))
        XCTAssertEqual(up.steps.map(\.label), ["Cabinovia Cima Bianca"])
        XCTAssertEqual(up.seconds, gondola.meters / RouteGraph.liftSpeed("gondola") + RouteGraph.boarding, accuracy: 8)
        XCTAssertEqual(up.meters, gondola.meters, accuracy: 5)
        XCTAssertGreaterThan(up.lats.count, 10, "the line of the lift is all there to draw")

        // From the top only red and black pistes leave: who wants the blue ones rides the gondola down.
        let easy = try XCTUnwrap(graph.route(fromLat: top.0, fromLon: top.1, toLat: village.0, toLon: village.1, level: .easy))
        XCTAssertEqual(easy.steps.map(\.label), ["Cabinovia Cima Bianca"])
        let medium = try XCTUnwrap(graph.route(fromLat: top.0, fromLon: top.1, toLat: village.0, toLon: village.1, level: .medium))
        XCTAssertFalse(medium.steps.contains { $0.difficulty == "advanced" })
        XCTAssertLessThanOrEqual(medium.seconds, easy.seconds + 0.5)
        let all = try XCTUnwrap(graph.route(fromLat: top.0, fromLon: top.1, toLat: village.0, toLon: village.1, level: .all))
        XCTAssertLessThanOrEqual(all.seconds, medium.seconds + 0.5)
        XCTAssertFalse(all.steps.isEmpty)

        // A chairlift does not carry down: from its top the way is the red piste, or none.
        let red = try XCTUnwrap(graph.route(fromLat: west.0, fromLon: west.1, toLat: village.0, toLon: village.1, level: .medium))
        XCTAssertEqual(red.steps.map(\.label), ["Gran Bosco"])
        XCTAssertEqual(red.steps.first?.difficulty, "intermediate")
        XCTAssertNil(graph.route(fromLat: west.0, fromLon: west.1, toLat: village.0, toLon: village.1, level: .easy))
        // And there is no skiing up a piste.
        let back = try XCTUnwrap(graph.route(fromLat: village.0, fromLon: village.1, toLat: west.0, toLon: west.1))
        XCTAssertEqual(back.steps.map(\.kind), [.lift])
        // Far from every line: nothing.
        XCTAssertNil(graph.route(fromLat: 44.0, fromLon: 7.63, toLat: village.0, toLon: village.1))

        XCTAssertTrue(RouteLevel.easy.allows("easy"))
        XCTAssertTrue(RouteLevel.easy.allows(nil))
        XCTAssertFalse(RouteLevel.easy.allows("intermediate"))
        XCTAssertFalse(RouteLevel.medium.allows("expert"))
        XCTAssertTrue(RouteLevel.all.allows("freeride"))
    }

    func testALineDrawnAgainstItsWayIsTurnedAround() throws {
        var ways = [
            try XCTUnwrap(OSMWay(kind: .piste, name: "Pista", ref: nil, difficulty: "easy", lats: [46.0, 46.01], lons: [7.0, 7.0])),
            try XCTUnwrap(OSMWay(kind: .lift, name: "Seggiovia", ref: nil, difficulty: nil, lats: [46.0, 46.01], lons: [7.1, 7.1], lift: "chair_lift")),
            try XCTUnwrap(OSMWay(kind: .lift, name: "Cabinovia", ref: nil, difficulty: nil, lats: [46.0, 46.01], lons: [7.2, 7.2], lift: "gondola")),
            try XCTUnwrap(OSMWay(kind: .piste, name: "Giusta", ref: nil, difficulty: "easy", lats: [46.0, 46.01], lons: [7.3, 7.3])),
        ]
        XCTAssertEqual(ways[0].meters, 1113, accuracy: 3)
        let altitudes = try Terrain.parseAltitudes(Data(#"{"elevation":[1500.0,2000,2000.0,1500,2000,1500,2100,1700]}"#.utf8))
        Terrain.apply(altitudes, to: &ways)
        XCTAssertEqual(ways[0].lats, [46.01, 46.0], "a piste starts at its top")
        XCTAssertEqual(ways[0].startAlt, 2000)
        XCTAssertEqual(ways[0].drop, 500)
        XCTAssertEqual(ways[1].lats, [46.01, 46.0], "a chairlift starts at its bottom")
        XCTAssertEqual(ways[1].endAlt, 2000)
        XCTAssertEqual(ways[2].lats, [46.0, 46.01], "a gondola goes both ways: left as drawn")
        XCTAssertEqual(ways[3].lats, [46.0, 46.01])
        // Fewer altitudes than ends: nothing is touched.
        var same = ways
        Terrain.apply([1, 2], to: &same)
        XCTAssertEqual(same[0].lats, ways[0].lats)
    }

    func testTheHutsByThePistes() throws {
        let piste = try XCTUnwrap(OSMWay(kind: .piste, name: "Pista", ref: nil, difficulty: "easy", lats: [46.0, 46.01], lons: [7.0, 7.0]))
        let json = """
        {"elements":[
          {"type":"way","id":1,"tags":{"piste:type":"downhill"},"geometry":[{"lat":46.0,"lon":7.0},{"lat":46.01,"lon":7.0}]},
          {"type":"node","id":2,"lat":46.005,"lon":7.0005,"tags":{"tourism":"alpine_hut","name":"Rifugio Alto"}},
          {"type":"way","id":3,"center":{"lat":46.002,"lon":7.0003},"tags":{"amenity":"restaurant","name":"Baita"}},
          {"type":"node","id":4,"lat":46.005,"lon":7.05,"tags":{"amenity":"bar","name":"Bar in paese"}},
          {"type":"node","id":5,"lat":46.006,"lon":7.0002,"tags":{"amenity":"cafe"}}
        ]}
        """
        let huts = Terrain.parseHuts(Data(json.utf8), near: [piste])
        XCTAssertEqual(huts.map(\.name), ["Rifugio Alto", "Baita"], "the one in the village and the one with no name are left out")
        XCTAssertEqual(huts[1].id, "way3")
        let map = try Pistes.parse(Data(json.utf8))
        XCTAssertEqual(map.ways.count, 1)
        XCTAssertEqual(map.ways[0].id, 1)
        let terrain = Terrain(ways: map.ways, huts: huts)
        XCTAssertEqual(terrain.nearest(lat: 46.005, lon: 7.0004, within: 90), 0)
        XCTAssertNil(terrain.nearest(lat: 46.005, lon: 7.01, within: 90))
        XCTAssertTrue(Terrain.query(lat: 46, lon: 7).contains("alpine_hut"))
    }

    func testTheBluetoothCodeTellsFriendsOnly() {
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let friends = [Friend(id: "a1", name: "Giulia"), Friend(id: "b2", name: "Luca")]
        let code = Proximity.code(id: "b2", day: day)
        XCTAssertEqual(code.count, 8)
        XCTAssertEqual(code, Proximity.code(id: "b2", day: day), "the same all day")
        XCTAssertNotEqual(code, Proximity.code(id: "b2", day: day.addingTimeInterval(3 * 86_400)), "another one each day")
        XCTAssertNotEqual(code, Proximity.code(id: "a1", day: day))
        XCTAssertEqual(Proximity.friend(for: code, among: friends, day: day)?.name, "Luca")
        // A phone whose clock is already in tomorrow is still recognized; a stranger is not.
        XCTAssertEqual(Proximity.friend(for: Proximity.code(id: "a1", day: day.addingTimeInterval(86_400)), among: friends, day: day)?.name, "Giulia")
        XCTAssertNil(Proximity.friend(for: Proximity.code(id: "zz", day: day), among: friends, day: day))
        XCTAssertNil(Proximity.friend(for: code, among: friends, day: day.addingTimeInterval(5 * 86_400)))
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
