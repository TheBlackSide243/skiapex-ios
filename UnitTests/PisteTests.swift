import SwiftUI
import XCTest
@testable import SkiApex

/// What came with 0.8.0: the book of the pistes, the challenge on them, the places to meet, the
/// copy in iCloud, the pictures to share and the numbers of the widgets.
final class PisteTests: XCTestCase {
    private let morning = Date(timeIntervalSince1970: 1_795_000_000)

    private func note(_ name: String, seconds: Double, drop: Double, speed: Double = 15, after: Double = 0, difficulty: String? = "easy",
                      ref: String? = nil) -> RunNote {
        RunNote(n: name, r: ref, d: difficulty, s: seconds, v: speed, h: drop, m: drop * 5, t: morning.addingTimeInterval(after))
    }

    private func summary(_ place: String, lat: Double, lon: Double, daysLater: Double = 0, _ notes: [RunNote]?) -> DaySummary {
        let start = morning.addingTimeInterval(daysLater * 86_400)
        let shifted = notes?.map { one -> RunNote in
            var moved = one
            moved.t = one.t.addingTimeInterval(daysLater * 86_400)
            return moved
        }
        return DaySummary(id: UUID(), start: start, end: start.addingTimeInterval(6 * 3600), place: place, stats: DayStats(),
                          lat: lat, lon: lon, pistes: shifted)
    }

    /// Every piste with its times: the best one is of a run down the whole of it, a piste of the
    /// same name somewhere else is another piste, and the ones skied most come first.
    func testTheBookOfThePistes() throws {
        let cervinia = summary("Cervinia", lat: 45.9336, lon: 7.6295, [
            note("Ventina", seconds: 400, drop: 900, after: 0, difficulty: "intermediate", ref: "7"),
            note("Ventina", seconds: 90, drop: 300, speed: 22, after: 3600, difficulty: "intermediate"),
            note("Gran Bosco", seconds: 200, drop: 400, after: 7200),
        ])
        // The day after, a few kilometers away in the same ski area: the same Ventina, faster.
        let again = summary("Valtournenche", lat: 45.90, lon: 7.66, daysLater: 1, [
            note("Ventina", seconds: 350, drop: 880, after: 100, difficulty: "intermediate"),
        ])
        let livigno = summary("Livigno", lat: 46.5386, lon: 10.1357, daysLater: 2, [
            note("Ventina", seconds: 60, drop: 200, after: 0, difficulty: "advanced"),
        ])
        let byHand = summary("Madesimo", lat: 46.43, lon: 9.35, daysLater: 3, nil)
        let entries = PisteBook.entries([livigno, again, byHand, cervinia])
        // The one skied most first; then, of the two skied once, the last one skied.
        XCTAssertEqual(entries.map(\.name), ["Ventina", "Ventina", "Gran Bosco"])
        let ventina = try XCTUnwrap(entries.first)
        XCTAssertEqual(ventina.count, 3)
        XCTAssertEqual(ventina.place, "Cervinia")
        XCTAssertEqual(ventina.ref, "7")
        XCTAssertEqual(ventina.fullDrop, 900)
        // The short one began halfway: not a time to beat, though its speed counts.
        XCTAssertEqual(ventina.whole.map(\.seconds), [400, 350])
        XCTAssertEqual(ventina.best?.seconds, 350)
        XCTAssertEqual(ventina.best?.day, again.id)
        XCTAssertEqual(ventina.topSpeed, 22)
        XCTAssertEqual(ventina.vertical, 2080)
        XCTAssertEqual(ventina.laps.map(\.seconds), [400, 90, 350], "from the first time to the last")
        XCTAssertEqual(entries[1].difficulty, "advanced")
        XCTAssertEqual(entries[1].place, "Livigno")
        XCTAssertNotEqual(entries[0].id, entries[1].id)

        // Around a ski area, only its own.
        XCTAssertEqual(PisteBook.entries([livigno, again, cervinia], nearLat: 45.93, lon: 7.63).map(\.name), ["Ventina", "Gran Bosco"])
        XCTAssertEqual(PisteBook.entries([livigno, again, cervinia], nearLat: 46.54, lon: 10.14).map(\.count), [1])
        // The piste of a run of a day.
        XCTAssertEqual(PisteBook.entry(named: "Ventina", of: livigno, in: entries)?.id, entries[1].id)
        XCTAssertNil(PisteBook.entry(named: nil, of: cervinia, in: entries))
        XCTAssertNil(PisteBook.entry(named: "Ventina", of: byHand.with(lat: nil), in: entries))

        XCTAssertEqual(Fmt.lap(161), "2:41")
        XCTAssertEqual(Fmt.lap(59.6), "1:00")
        XCTAssertEqual(Fmt.lap(3727), "1:02:07")
    }

    /// A day writes its runs piste by piste in the list: the ones with a name, long enough.
    func testADayWritesItsRunsPisteByPiste() throws {
        var day = SkiDay(points: SkiSim.day(laps: 4, start: morning, seed: 3), place: "Cervinia")
        XCTAssertEqual(day.summary.pistes, [], "a track, and no piste known yet")
        let runs = day.segments.indices.filter { day.segments[$0].kind == .run }
        XCTAssertGreaterThanOrEqual(runs.count, 3)
        for (n, i) in runs.enumerated() {
            day.segments[i].name = n == 0 ? nil : "Gran Bosco"
            day.segments[i].difficulty = "intermediate"
            day.segments[i].ref = "7"
        }
        let notes = try XCTUnwrap(day.summary.pistes)
        XCTAssertEqual(notes.count, runs.count - 1)
        XCTAssertEqual(notes.first?.n, "Gran Bosco")
        XCTAssertEqual(notes.first?.r, "7")
        XCTAssertEqual(notes.first?.s ?? 0, day.segments[runs[1]].duration, accuracy: 0.01)
        XCTAssertEqual(notes.first?.h ?? 0, day.segments[runs[1]].drop, accuracy: 0.01)
        // Written by hand: no track, no pistes.
        let byHand = SkiDay(manual: morning, duration: 3600, place: "Madesimo", sport: .ski, runs: 5, vertical: 2000, distance: 9000, maxSpeed: 0)
        XCTAssertNil(byHand.summary.pistes)
        // And kept in the list of a library, across a launch.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("skiapex-pistes-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Library(directory: dir).save(day)
        let later = Library(directory: dir)
        XCTAssertEqual(later.days.first?.pistes?.count, runs.count - 1)
        XCTAssertEqual(PisteBook.entries(later.days).first?.count, runs.count - 1)
    }

    /// What goes to the server of a piste: its name, where to the kilometer, the best time.
    func testWhatIsSentOfAPiste() throws {
        let day = summary("Cervinia", lat: 45.93361, lon: 7.62954, [
            note("Ventina", seconds: 400, drop: 900, speed: 21), note("Ventina", seconds: 380, drop: 890, after: 3600),
        ])
        let entry = try XCTUnwrap(PisteBook.entries([day]).first)
        let sent = try XCTUnwrap(PisteBook.shared(entry))
        XCTAssertEqual(sent["name"] as? String, "Ventina")
        XCTAssertEqual(sent["lat"] as? Double ?? 0, 45.93, accuracy: 0.0001)
        XCTAssertEqual(sent["lon"] as? Double ?? 0, 7.63, accuracy: 0.0001)
        XCTAssertEqual(sent["best"] as? Double, 380)
        XCTAssertEqual(sent["speed"] as? Double, 21)
        XCTAssertEqual(sent["runs"] as? Int, 2)
        XCTAssertEqual(sent["difficulty"] as? String, "easy")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(sent))

        let rows = try JSONDecoder().decode([PisteRow].self, from: Data("""
        [{"id":"a","name":"Alex","photo":0,"me":false,"best":290,"speed":19,"runs":1,"date":"2026-11-20"},
         {"id":"b","name":"Alessio","photo":1795000000000,"me":true,"best":312.4,"speed":21.5,"runs":3,"date":"2026-11-21"}]
        """.utf8))
        XCTAssertEqual(rows.map(\.name), ["Alex", "Alessio"])
        XCTAssertEqual(rows[1].best, 312.4)
        XCTAssertTrue(rows[1].me)
    }

    /// A place to meet as the server sends it, and the hour chosen as the next time it comes.
    func testAPlaceToMeet() throws {
        let when = morning.addingTimeInterval(1800)
        let json = """
        {"meetings":[{"id":"a","name":"Giulia","photo":0,"mine":false,"lat":45.9412,"lon":7.6388,"label":"Rifugio Teodulo",
          "when":\(Int(when.timeIntervalSince1970 * 1000)),"until":\(Int(when.timeIntervalSince1970 * 1000) + 3600000),"at":1795000000000},
         {"id":"me","name":"Marco","photo":0,"mine":true,"lat":45.93,"lon":7.63,"label":"","when":null,"until":1795040000000,"at":1794990000000}]}
        """
        struct Answer: Decodable { let meetings: [Meeting] }
        let meetings = try JSONDecoder().decode(Answer.self, from: Data(json.utf8)).meetings
        XCTAssertEqual(meetings.count, 2)
        XCTAssertEqual(meetings[0].time, when)
        XCTAssertTrue(meetings[0].title.hasPrefix("Rifugio Teodulo · "))
        XCTAssertTrue(meetings[0].mark.title.hasPrefix("Giulia: Rifugio Teodulo"))
        XCTAssertEqual(meetings[0].mark.id, "meeta")
        XCTAssertNil(meetings[1].time)
        XCTAssertFalse(meetings[1].title.isEmpty, "a place with no name is still called something")
        XCTAssertFalse(meetings[1].title.contains("·"))

        // Half an hour from now, on the five minutes.
        let now = Date(timeIntervalSinceReferenceDate: 800_000_123)
        let soon = MeetingEditor.soon(from: now)
        XCTAssertEqual(soon.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 300), 0)
        XCTAssertGreaterThanOrEqual(soon.timeIntervalSince(now), 1800)
        XCTAssertLessThan(soon.timeIntervalSince(now), 2100)
        // An hour already past is tomorrow's; one a few minutes ago is still today's.
        XCTAssertEqual(MeetingEditor.next(now.addingTimeInterval(-7200), after: now), now.addingTimeInterval(86_400 - 7200))
        XCTAssertEqual(MeetingEditor.next(now.addingTimeInterval(-120), after: now), now.addingTimeInterval(-120))
        XCTAssertEqual(MeetingEditor.next(now.addingTimeInterval(900), after: now), now.addingTimeInterval(900))
    }

    /// A place to meet is answered: what you said to a friend's, what the friends said to yours,
    /// and what is new is said once.
    func testAPlaceToMeetIsAnswered() throws {
        let json = """
        [{"id":"a","name":"Giulia","photo":0,"mine":false,"lat":45.94,"lon":7.63,"label":"Baita del Sole","when":null,
          "until":1795040000000,"at":1795000000000,"answer":null},
         {"id":"me","name":"Marco","photo":0,"mine":true,"lat":45.93,"lon":7.63,"label":"Rifugio Teodulo","when":null,
          "until":1795040000000,"at":1794990000000,
          "answers":[{"id":"a","name":"Giulia","photo":0,"answer":"yes"},{"id":"b","name":"Luca","photo":0,"answer":"no"},
                     {"id":"c","name":"Sara","photo":0,"answer":null}]}]
        """
        var meetings = try JSONDecoder().decode([Meeting].self, from: Data(json.utf8))
        XCTAssertTrue(meetings[0].asks)
        XCTAssertNil(meetings[0].answers)
        XCTAssertFalse(meetings[1].asks, "your own asks nothing of you")
        XCTAssertEqual(meetings[1].answers?.map(\.answer), ["yes", "no", nil])
        let count = meetings[1].count
        XCTAssertEqual([count.yes, count.no, count.waiting], [1, 1, 1])
        XCTAssertEqual(MeetingAnswers.words("yes"), "Ci sarà")
        XCTAssertEqual(MeetingAnswers.words(nil), "Non ha ancora risposto")
        XCTAssertNotEqual(MeetingAnswers.symbol("yes"), MeetingAnswers.symbol("no"))

        // A friend asks, and two friends answered yours: three things to say, each once.
        let first = MeetingNews.notices(meetings, told: [])
        XCTAssertEqual(first.count, 3)
        XCTAssertEqual(first[0].key, "ask:a:1795000000000")
        XCTAssertTrue(first[0].title.contains("Giulia"))
        XCTAssertTrue(first[0].body.contains("Baita del Sole"))
        XCTAssertEqual(Set(first.dropFirst().map(\.key)), ["answer:a:1794990000000:yes", "answer:b:1794990000000:no"])
        XCTAssertTrue(first.dropFirst().allSatisfy { $0.body.contains("Rifugio Teodulo") })
        XCTAssertEqual(MeetingNews.notices(meetings, told: Set(first.map(\.key))), [])

        // Once you answered, the friend's asks no more; a friend who changes their mind is news,
        // and so is the same friend asking again with a new place.
        meetings[0].answer = "yes"
        XCTAssertFalse(meetings[0].asks)
        meetings[1].answers?[1].answer = "yes"
        let later = MeetingNews.notices(meetings, told: Set(first.map(\.key)))
        XCTAssertEqual(later.map(\.key), ["answer:b:1794990000000:yes"])
        meetings[0].answer = nil
        meetings[0].at += 60_000
        XCTAssertEqual(MeetingNews.notices(meetings, told: Set(first.map(\.key) + later.map(\.key))).map(\.key), ["ask:a:1795000060000"])
    }

    /// The copy in iCloud, with two folders: what is in one goes to the other, the newest of a
    /// day wins, and a day deleted on purpose goes from both and does not come back.
    func testTwoFoldersBroughtLevel() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("skiapex-cloud-\(UUID().uuidString)", isDirectory: true)
        let local = root.appendingPathComponent("qui", isDirectory: true), cloud = root.appendingPathComponent("icloud", isDirectory: true)
        try fm.createDirectory(at: local, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func file(_ dir: URL, _ id: UUID) -> URL { dir.appendingPathComponent("\(id.uuidString).json") }
        func put(_ text: String, _ dir: URL, _ id: UUID, at date: Date) throws {
            try Data(text.utf8).write(to: file(dir, id))
            try fm.setAttributes([.modificationDate: date], ofItemAtPath: file(dir, id).path)
        }
        func read(_ dir: URL, _ id: UUID) -> String? { (try? Data(contentsOf: file(dir, id))).map { String(decoding: $0, as: UTF8.self) } }
        func level() throws -> CloudCopy.Outcome { try CloudCopy.level(local: local, cloud: cloud) { _ in true } }
        let a = UUID(), b = UUID(), c = UUID()
        let then = Date(timeIntervalSinceNow: -3600)

        // Two days here, and the list of the days, which is not a day: up go the two.
        try put("a1", local, a, at: then)
        try put("b1", local, b, at: then)
        try Data("[]".utf8).write(to: local.appendingPathComponent("indice.json"))
        var out = try level()
        XCTAssertEqual(out.up, 2)
        XCTAssertEqual(out.inCloud, 2)
        XCTAssertFalse(out.changedHere)
        XCTAssertEqual(read(cloud, a), "a1")
        XCTAssertFalse(fm.fileExists(atPath: cloud.appendingPathComponent("indice.json").path))
        // Nothing new: nothing moves.
        XCTAssertEqual(try level(), CloudCopy.Outcome(inCloud: 2))

        // A day saved on another iPhone comes down; one changed there after comes down too; one
        // changed here after goes up.
        try put("c1", cloud, c, at: then)
        try put("a2", cloud, a, at: then.addingTimeInterval(600))
        try put("b2", local, b, at: then.addingTimeInterval(900))
        out = try level()
        XCTAssertEqual(out.down, 2)
        XCTAssertEqual(out.up, 1)
        XCTAssertTrue(out.changedHere)
        XCTAssertEqual(read(local, c), "c1")
        XCTAssertEqual(read(local, a), "a2")
        XCTAssertEqual(read(cloud, b), "b2")
        XCTAssertEqual(try level(), CloudCopy.Outcome(inCloud: 3))

        // The same day with another date and the same words: left alone.
        try fm.setAttributes([.modificationDate: then.addingTimeInterval(5000)], ofItemAtPath: file(cloud, c).path)
        XCTAssertEqual(try level(), CloudCopy.Outcome(inCloud: 3))

        // Deleted here on purpose: gone from iCloud too, and remembered in both folders.
        try fm.removeItem(at: file(local, a))
        CloudCopy.bury(a, in: local)
        out = try level()
        XCTAssertEqual(out.removedThere, 1)
        XCTAssertEqual(out.inCloud, 2)
        XCTAssertNil(read(cloud, a))
        XCTAssertNotNil(CloudCopy.deleted(in: cloud)[a.uuidString])
        // Deleted on the other iPhone: gone from here, and the list is to be read again.
        try fm.removeItem(at: file(cloud, b))
        CloudCopy.bury(b, in: cloud, at: Date())
        out = try level()
        XCTAssertEqual(out.removedHere, 1)
        XCTAssertTrue(out.changedHere)
        XCTAssertNil(read(local, b))
        // Saved again after it was deleted (brought back from a zip): it stays, and goes up.
        try put("a3", local, a, at: Date(timeIntervalSinceNow: 60))
        out = try level()
        XCTAssertEqual(out.up, 1)
        XCTAssertEqual(read(cloud, a), "a3")
        XCTAssertNil(CloudCopy.deleted(in: local)[a.uuidString])

        // A file of iCloud not here yet is waited for, not read: the new day, and the one whose
        // date is not the same on the two sides.
        try put("d1", cloud, UUID(), at: then)
        out = try CloudCopy.level(local: local, cloud: cloud) { _ in false }
        XCTAssertEqual(out.down, 0)
        XCTAssertEqual(out.waiting, 2)

        XCTAssertNil(CloudCopy.dayID(local.appendingPathComponent("indice.json")))
        XCTAssertEqual(CloudCopy.dayID(file(local, a)), a.uuidString)
    }

    /// A library deletes a day and remembers it; told that its files changed, it reads them again.
    func testALibraryRemembersWhatItDeleted() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("skiapex-buried-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let library = Library(directory: dir)
        let day = SkiDay(points: SkiSim.day(laps: 2, start: morning, seed: 9), place: "Cervinia")
        try library.save(day)
        // A day arrives in the folder from elsewhere.
        var other = SkiDay(points: SkiSim.day(laps: 2, start: morning.addingTimeInterval(86_400), seed: 10), place: "Livigno")
        other.resort = "Livigno"
        try JSONEncoder().encode(other).write(to: library.folder.appendingPathComponent("\(other.id.uuidString).json"))
        XCTAssertEqual(library.days.count, 1)
        let before = library.saves
        library.reload()
        XCTAssertEqual(Set(library.days.map(\.id)), [day.id, other.id])
        XCTAssertGreaterThan(library.saves, before)
        library.delete(day.id)
        XCTAssertNotNil(CloudCopy.deleted(in: library.folder)[day.id.uuidString])
        XCTAssertNil(CloudCopy.deleted(in: library.folder)[other.id.uuidString])
    }

    /// The pistes of a day on its picture, the ones skied most first; and the two shapes of it.
    func testThePictureOfADay() throws {
        var day = SkiDay(points: SkiSim.day(laps: 5, start: morning, seed: 4), place: "Cervinia")
        let runs = day.segments.indices.filter { day.segments[$0].kind == .run }
        XCTAssertGreaterThanOrEqual(runs.count, 4)
        for (n, i) in runs.enumerated() {
            day.segments[i].name = n == 0 ? "Canalone" : n == 1 ? nil : "Gran Bosco"
            day.segments[i].difficulty = n == 0 ? "advanced" : "intermediate"
            day.segments[i].ref = n == 0 ? "5" : nil
        }
        let pistes = ShareCard.pistes(of: day)
        XCTAssertEqual(pistes.map(\.name), ["Gran Bosco", "Canalone"])
        XCTAssertEqual(pistes.first?.times, runs.count - 2)
        XCTAssertEqual(pistes.last?.ref, "5")
        XCTAssertEqual(pistes.last?.difficulty, "advanced")
        XCTAssertEqual(CardFormat.post.size.width, CardFormat.story.size.width)
        XCTAssertEqual(CardFormat.story.size.height / CardFormat.story.size.width, 16.0 / 9.0, accuracy: 0.01)
    }

    /// The numbers of the widgets and of the watch: the unit small, in capitals.
    func testTheNumbersOfTheWidgets() {
        func words(_ value: String) -> String { String(UnitText.styled(value, big: .title, small: .caption).characters) }
        XCTAssertEqual(words("1240 m"), "1240 M")
        XCTAssertEqual(words("72 km/h"), "72 KM/H")
        XCTAssertEqual(words("12 cm"), "12 CM")
        XCTAssertEqual(words("–"), "–")
        XCTAssertEqual(words("7"), "7")
        XCTAssertEqual(words("-8°"), "-8°")
    }
}

private extension DaySummary {
    /// The same day somewhere else, or nowhere.
    func with(lat: Double?) -> DaySummary {
        var copy = self
        copy.lat = lat
        return copy
    }
}
