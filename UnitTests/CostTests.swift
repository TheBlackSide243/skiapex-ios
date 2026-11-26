import XCTest
@testable import SkiApex

/// What came with 0.9.0: the goals of a season, what skiing cost with a season pass, day passes
/// or SnowitPass, and the notifications sent by the server.
final class CostTests: XCTestCase {
    /// A moment at the resorts: midday unless said.
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        Snowit.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func summary(_ start: Date, place: String? = "Livigno", lat: Double? = 46.53, lon: Double? = 10.13,
                         shape: [Leg]? = nil) -> DaySummary {
        var stats = DayStats()
        stats.runs = 10
        stats.vertical = 5000
        stats.runDistance = 30_000
        return DaySummary(id: UUID(), start: start, end: start.addingTimeInterval(6 * 3600), place: place, stats: stats,
                          sport: .ski, resort: nil, lat: lat, lon: lon, manual: nil, shape: shape)
    }

    private func pass(_ year: Int, _ month: Int, _ day: Int, from: (Int, Int)? = nil, to: (Int, Int)? = nil,
                      zone: String? = "livigno") -> PassDay {
        PassDay(id: UUID(), start: date(year, month, day, from?.0 ?? 9, from?.1 ?? 0),
                first: from.map { date(year, month, day, $0.0, $0.1) }, last: to.map { date(year, month, day, $0.0, $0.1) }, zone: zone)
    }

    // MARK: Goals

    func testTheGoalsOfASeason() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "goals-\(UUID().uuidString)"))
        let season = Season(date(2026, 12, 20))
        XCTAssertTrue(Goals.of(season, in: defaults).isEmpty)
        Goals.set(SeasonGoals(days: 10, vertical: 20_000), for: season, in: defaults)
        XCTAssertEqual(Goals.of(season, in: defaults), SeasonGoals(days: 10, vertical: 20_000))
        XCTAssertTrue(Goals.of(Season(date(2025, 12, 20)), in: defaults).isEmpty, "each season has its own")

        let days = (0..<4).map { summary(date(2026, 12, 20 + $0)) }
        let progress = Goals.progress(Goals.of(season, in: defaults), days: days)
        XCTAssertEqual(progress.map(\.kind), [.days, .vertical])
        XCTAssertEqual(progress[0].done, 4)
        XCTAssertEqual(progress[0].left, 6)
        XCTAssertEqual(progress[0].fraction, 0.4, accuracy: 0.001)
        XCTAssertFalse(progress[0].reached)
        XCTAssertTrue(progress[1].reached, "twenty thousand of twenty thousand")
        XCTAssertEqual(progress[1].fraction, 1)

        // Six days to go and ten weeks to the middle of April: a little more than one every two weeks.
        let end = Goals.end(of: season)
        let pace = try XCTUnwrap(Goals.weekly(progress[0], season: season, now: end.addingTimeInterval(-70 * 86_400)))
        XCTAssertEqual(pace, 0.6, accuracy: 0.001)
        XCTAssertNil(Goals.weekly(progress[1], season: season, now: end.addingTimeInterval(-70 * 86_400)), "reached")
        XCTAssertNil(Goals.weekly(progress[0], season: season, now: end.addingTimeInterval(86_400)), "the season is over")
        XCTAssertNotNil(progress[0].note(season: season, now: end.addingTimeInterval(-70 * 86_400)))
        XCTAssertNil(progress[1].note(season: season))

        Goals.set(SeasonGoals(), for: season, in: defaults)
        XCTAssertTrue(Goals.of(season, in: defaults).isEmpty)
        XCTAssertTrue(Goals.progress(SeasonGoals(), days: days).isEmpty)
    }

    // MARK: The tariffs of SnowitPass

    func testTheTariffsThatComeWithTheApp() throws {
        let book = try XCTUnwrap(Snowit.book)
        XCTAssertEqual(book.season, 2026)
        XCTAssertEqual(book.zones.count, 46)
        XCTAssertEqual(Set(book.zones.map(\.s)).count, 46)
        XCTAssertEqual(book.zones.filter(\.hasRates).count, 30)
        for goal in book.goals {
            XCTAssertTrue(goal.z.allSatisfy { book.zone($0) != nil }, goal.n)
            XCTAssertNotNil(goal.target(.adult), goal.n)
        }
        XCTAssertEqual(Snowit.tariffs(for: Season(date(2026, 12, 20)))?.season, 2026)
        XCTAssertNil(Snowit.tariffs(for: Season(date(2025, 12, 20))), "not those of another winter")

        // Where a day was.
        let livigno = try XCTUnwrap(Snowit.zone(lat: 46.52, lon: 10.12, in: book))
        XCTAssertEqual(livigno.s, "livigno")
        XCTAssertNil(Snowit.zone(lat: 47.26, lon: 11.39, in: book), "Innsbruck is no place of SnowitPass")
        XCTAssertEqual(Snowit.zone(named: "livigno", in: book)?.s, "livigno")
        XCTAssertNil(Snowit.zone(named: "Zermatt", in: book))

        // The stretch of the season a day falls in, by its dates.
        XCTAssertEqual(Snowit.period(of: livigno, on: date(2026, 12, 28), in: book)?.k, "alta")
        XCTAssertEqual(Snowit.period(of: livigno, on: date(2027, 1, 12), in: book)?.k, "bassa")
        XCTAssertEqual(Snowit.period(of: livigno, on: date(2026, 12, 5), in: book)?.k, "promo")
        XCTAssertEqual(Snowit.dayPrice(of: livigno, on: date(2026, 12, 28), age: .adult, in: book), 74.5)
        XCTAssertEqual(Snowit.dayPrice(of: livigno, on: date(2026, 12, 28), age: .senior, in: book), 63)
        XCTAssertEqual(Snowit.dayPrice(of: livigno, on: date(2027, 1, 12), age: .adult, in: book), 66)

        // And by the day of the week: at Aprica every Saturday and Sunday is high season.
        let aprica = try XCTUnwrap(book.zone("aprica"))
        XCTAssertEqual(Snowit.period(of: aprica, on: date(2027, 1, 12), in: book)?.k, "bassa", "a Tuesday of January")
        XCTAssertEqual(Snowit.period(of: aprica, on: date(2027, 1, 16), in: book)?.k, "alta", "the Saturday after")
        XCTAssertTrue(Snowit.isFree(date(2026, 12, 8), in: book), "a holiday on a Tuesday")
        // The band of an age that a place has no prices for pays as an adult.
        XCTAssertEqual(Snowit.dayPrice(of: aprica, on: date(2027, 1, 12), age: .teen, in: book), 53)
    }

    func testWhatADayOnSnowitPassCosts() throws {
        let book = try XCTUnwrap(Snowit.book)
        let livigno = try XCTUnwrap(book.zone("livigno"))
        let aprica = try XCTUnwrap(book.zone("aprica"))
        func cost(_ day: PassDay, _ zone: SnowitBook.Zone, streak: Int = 1) -> PassCharge {
            Snowit.estimate(day, zone: zone, age: .adult, streak: streak, in: book)
        }

        // Livigno, high season: a day 74.50, a morning or an afternoon 59.
        XCTAssertEqual(cost(pass(2026, 12, 28, from: (9, 0), to: (15, 30)), livigno), PassCharge(amount: 74.5, tariff: .day, zone: "livigno"))
        XCTAssertEqual(cost(pass(2026, 12, 28, from: (8, 45), to: (12, 40)), livigno), PassCharge(amount: 59, tariff: .morning, zone: "livigno"))
        XCTAssertEqual(cost(pass(2026, 12, 28, from: (12, 45), to: (16, 0)), livigno), PassCharge(amount: 59, tariff: .afternoon, zone: "livigno"))
        XCTAssertEqual(cost(pass(2026, 12, 28), livigno).tariff, .day, "with no times, a whole day")
        // The second day in a row adds what two days cost over one, the third what three over two.
        XCTAssertEqual(cost(pass(2026, 12, 29, from: (9, 0), to: (15, 30)), livigno, streak: 2), PassCharge(amount: 69, tariff: .days(2), zone: "livigno"))
        XCTAssertEqual(cost(pass(2026, 12, 30, from: (9, 0), to: (15, 30)), livigno, streak: 3).amount, 68.5)
        XCTAssertEqual(cost(pass(2026, 12, 29, from: (8, 45), to: (12, 40)), livigno, streak: 2).tariff, .morning, "a morning is cheaper still")

        // Aprica, a Tuesday of low season: by the hours from the first lift to the last.
        XCTAssertEqual(cost(pass(2027, 1, 12, from: (9, 0), to: (11, 30)), aprica), PassCharge(amount: 42, tariff: .hours(3), zone: "aprica"))
        XCTAssertEqual(cost(pass(2027, 1, 12, from: (9, 0), to: (10, 50)), aprica).amount, 38)
        XCTAssertEqual(cost(pass(2027, 1, 12, from: (9, 0), to: (13, 10)), aprica), PassCharge(amount: 53, tariff: .day, zone: "aprica"))

        // Cervinia counts a day and its parts, never days in a row.
        let cervinia = try XCTUnwrap(book.zone("cervinia"))
        XCTAssertEqual(cost(pass(2027, 1, 13, from: (9, 0), to: (15, 30), zone: "cervinia"), cervinia, streak: 2).tariff, .day)
        // A place whose prices Snowit does not publish: not known.
        let carona = try XCTUnwrap(book.zone("carona"))
        XCTAssertNil(cost(pass(2027, 1, 13, zone: "carona"), carona).amount)
    }

    func testASeasonOnSnowitPassWithItsSpendingGoals() throws {
        let book = try XCTUnwrap(Snowit.book)
        // Fifteen days at Livigno, every other day of February: 74.50 each until the 980 of the goal.
        var days = (0..<15).map { pass(2027, 1, 30 + 2 * $0, from: (9, 0), to: (15, 30)) }
        var bill = Snowit.bill(days, age: .adult, paid: [:], payPerUse: true, activation: true, in: book)
        XCTAssertEqual(bill.charges[days[0].id]?.amount, 74.5)
        XCTAssertEqual(bill.charges[days[12].id]?.amount, 74.5)
        XCTAssertEqual(bill.charges[days[13].id]?.amount ?? 0, 11.5, accuracy: 0.001, "only what was left to the goal")
        XCTAssertEqual(bill.charges[days[14].id], PassCharge(amount: 0, tariff: .reached, zone: "livigno"))
        XCTAssertEqual(bill.activation, 15)
        XCTAssertEqual(bill.total, 995, accuracy: 0.001)
        XCTAssertEqual(bill.days, 15)
        XCTAssertEqual(bill.unknown, 0)
        let goals = Dictionary(uniqueKeysWithValues: bill.goals.map { ($0.goal.n, $0) })
        XCTAssertEqual(goals["Livigno"]?.reached, true)
        XCTAssertEqual(goals["Alta Valtellina"]?.left ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(goals["Lombardia"]?.spent ?? 0, 980, accuracy: 0.001)
        XCTAssertNil(goals["Pontedilegno-Tonale"], "never skied there")
        let reached = try XCTUnwrap(goals["Livigno"])
        XCTAssertTrue(PassView.benefit(reached, book: book).contains("Livigno"))

        // A day at Bormio after that: it still costs, it is another goal's.
        let bormio = pass(2027, 3, 3, from: (9, 0), to: (15, 30), zone: "bormio")
        days.append(bormio)
        bill = Snowit.bill(days, age: .adult, paid: [:], payPerUse: true, activation: false, in: book)
        XCTAssertEqual(bill.charges[bormio.id], PassCharge(amount: 63, tariff: .day, zone: "bormio"))
        XCTAssertEqual(bill.activation, 0)

        // What you wrote you paid comes first, and counts toward the goals.
        bill = Snowit.bill(days, age: .adult, paid: [days[0].id: 50], payPerUse: true, activation: false, in: book)
        XCTAssertEqual(bill.charges[days[0].id], PassCharge(amount: 50, tariff: .paid, zone: "livigno"))
        XCTAssertFalse(bill.charges[days[0].id]?.estimated ?? true)
        XCTAssertEqual(bill.charges[days[13].id]?.amount ?? 0, 36, accuracy: 0.001)

        // Two recordings of one day in one place are one day on the pass.
        let again = pass(2027, 1, 30, from: (14, 0), to: (16, 0))
        bill = Snowit.bill([days[0], again], age: .adult, paid: [:], payPerUse: true, activation: false, in: book)
        XCTAssertEqual(bill.charges[again.id]?.tariff, .same)
        XCTAssertEqual(bill.days, 1)
        XCTAssertEqual(bill.total, 74.5)

        // With day passes: the price of a day each, no goals. A day who knows where: not known.
        let lost = pass(2027, 2, 1, zone: nil)
        bill = Snowit.bill([days[0], days[1], lost], age: .adult, paid: [:], payPerUse: false, activation: true, in: book)
        XCTAssertEqual(bill.total, 149)
        XCTAssertTrue(bill.goals.isEmpty)
        XCTAssertEqual(bill.unknown, 1)
    }

    // MARK: What skiing cost

    func testWhatSkiingCostInASeason() throws {
        let book = try XCTUnwrap(Snowit.book)
        // Four days at Livigno in high season, not in a row: 74.50 each at the ticket office.
        let days = (0..<4).map { summary(date(2027, 2, 1 + 2 * $0, 9)) }

        XCTAssertEqual(Passes.summary(PassPlan(), days: days, book: book), PassSummary(), "not kept")

        var plan = PassPlan(kind: .season, seasonPrice: 800)
        var cost = Passes.summary(plan, days: days, book: book)
        XCTAssertEqual(cost.total, 800)
        XCTAssertEqual(cost.list, 298)
        XCTAssertEqual(cost.perDay, 200)
        XCTAssertEqual(cost.perRun, 20)
        XCTAssertEqual(cost.perKilometer, 40)
        XCTAssertEqual(cost.daysToPayOff, 7)
        plan.seasonPrice = 250
        XCTAssertNil(Passes.summary(plan, days: days, book: book).daysToPayOff, "it paid for itself")

        // Day passes: what was written, and the price of the day where nothing was.
        plan = PassPlan(kind: .daily, paid: [days[0].id.uuidString: 60])
        cost = Passes.summary(plan, days: days, book: book)
        XCTAssertEqual(cost.total, 60 + 3 * 74.5)
        XCTAssertEqual(cost.bill.charges[days[0].id]?.tariff, .paid)
        XCTAssertEqual(cost.bill.charges[days[1].id]?.note.isEmpty, false)
        // Told that those days were at no place of SnowitPass: nothing is known of them.
        plan.zones["Livigno"] = "-"
        cost = Passes.summary(plan, days: days, book: book)
        XCTAssertEqual(cost.total, 60)
        XCTAssertEqual(cost.bill.unknown, 3)
        XCTAssertEqual(cost.perDay, 60, "the days with no price are not counted")
        XCTAssertEqual(cost.perRun, 6)
        // Without the tariffs of that winter: only what was written.
        XCTAssertEqual(Passes.summary(PassPlan(kind: .snowit, activation: false), days: days, book: nil).total, 0)

        // SnowitPass, from the days as the diary keeps them: a lift at nine, the last at half past eleven.
        let lifts = [Leg(k: 1, s: 600, a: 1800, b: 2400, d: nil), Leg(k: 0, s: 8400, a: 2400, b: 1800, d: "easy"),
                     Leg(k: 1, s: 600, a: 1800, b: 2400, d: nil), Leg(k: 0, s: 900, a: 2400, b: 1800, d: "easy")]
        let morning = summary(date(2027, 2, 1, 9), shape: lifts)
        let seen = Passes.passDay(morning, plan: PassPlan(), book: book)
        XCTAssertEqual(seen.zone, "livigno")
        XCTAssertEqual(seen.first, morning.start)
        XCTAssertEqual(seen.last, morning.start.addingTimeInterval(9000))
        cost = Passes.summary(PassPlan(kind: .snowit), days: [morning], book: book)
        XCTAssertEqual(cost.bill.charges[morning.id], PassCharge(amount: 59, tariff: .morning, zone: "livigno"))
        XCTAssertEqual(cost.total, 74)
        // A day written by hand, with no place on the map: by its name.
        XCTAssertEqual(Passes.passDay(summary(date(2027, 2, 1), place: "Bormio", lat: nil, lon: nil), plan: PassPlan(), book: book).zone, "bormio")

        // Kept season by season.
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "pass-\(UUID().uuidString)"))
        let season = Season(date(2027, 2, 1))
        XCTAssertEqual(Passes.plan(of: season, in: defaults), PassPlan())
        Passes.set(plan, for: season, in: defaults)
        XCTAssertEqual(Passes.plan(of: season, in: defaults), plan)
        XCTAssertEqual(Passes.plan(of: Season(date(2025, 12, 20)), in: defaults), PassPlan())
    }

    /// The price of a day written by hand for a place stands for the tariffs there: where Snowit
    /// publishes none, and where they changed. What was written for one day still comes first.
    func testAPriceWrittenByHandForAPlace() throws {
        let book = try XCTUnwrap(Snowit.book)
        // Carona: a place of SnowitPass with no prices published.
        let carona = (0..<2).map { summary(date(2027, 2, 1 + 2 * $0, 9), place: "Carona", lat: 46.02, lon: 9.78) }
        var plan = PassPlan(kind: .snowit, activation: false)
        var cost = Passes.summary(plan, days: carona, book: book)
        XCTAssertEqual(cost.bill.unknown, 2)
        XCTAssertEqual(cost.total, 0)
        plan.prices = ["Carona": 32]
        cost = Passes.summary(plan, days: carona, book: book)
        XCTAssertEqual(cost.bill.charges[carona[0].id], PassCharge(amount: 32, tariff: .yours, zone: "carona"))
        XCTAssertEqual(cost.bill.charges[carona[0].id]?.note, PassCharge.Tariff.yours.label, "yours, not an estimate")
        XCTAssertEqual(cost.bill.unknown, 0)
        XCTAssertEqual(cost.total, 64)
        XCTAssertEqual(cost.perDay, 32)
        // It still counts toward the spending goal of its region.
        XCTAssertEqual(cost.bill.goals.first { $0.goal.n == "Lombardia" }?.spent, 64)

        // Livigno: prices are published, and yours takes their place. What was paid for a day comes first.
        let livigno = (0..<3).map { summary(date(2027, 2, 1 + 2 * $0, 9)) }
        plan = PassPlan(kind: .snowit, activation: false, prices: ["Livigno": 80], paid: [livigno[2].id.uuidString: 50])
        cost = Passes.summary(plan, days: livigno, book: book)
        XCTAssertEqual(cost.bill.charges[livigno[0].id]?.amount, 80)
        XCTAssertEqual(cost.bill.charges[livigno[2].id]?.tariff, .paid)
        XCTAssertEqual(cost.total, 210)
        // The same with day passes, and for what a season pass is compared with.
        plan.kind = .daily
        XCTAssertEqual(Passes.summary(plan, days: livigno, book: book).total, 210)
        plan = PassPlan(kind: .season, seasonPrice: 800, prices: ["Livigno": 80])
        XCTAssertEqual(Passes.summary(plan, days: livigno, book: book).list, 240)
        // A place Snowit does not know at all, in a winter with no tariffs: yours is all there is.
        let abroad = [summary(date(2027, 2, 1, 9), place: "Zermatt", lat: 46.02, lon: 7.75)]
        cost = Passes.summary(PassPlan(kind: .daily, prices: ["Zermatt": 95]), days: abroad, book: nil)
        XCTAssertEqual(cost.total, 95)
        XCTAssertEqual(cost.bill.unknown, 0)
        // A spending goal reached makes a day free, also at a price of yours.
        let many = (0..<14).map { summary(date(2027, 1, 30 + 2 * $0, 9)) }
        plan = PassPlan(kind: .snowit, activation: false, prices: ["Livigno": 100])
        cost = Passes.summary(plan, days: many, book: book)
        XCTAssertEqual(cost.total, 980, accuracy: 0.001)
        XCTAssertEqual(cost.bill.charges[many[13].id]?.tariff, .reached)

        // The activation: the price of the list, or what was really paid for it.
        plan = PassPlan(kind: .snowit)
        XCTAssertEqual(Passes.summary(plan, days: [], book: book).total, 15)
        plan.activationPrice = 1
        XCTAssertEqual(Passes.summary(plan, days: [], book: book).total, 1)
        plan.activation = false
        XCTAssertEqual(Passes.summary(plan, days: [], book: book).total, 0)

        // What was kept before there were prices of yours is still read.
        let old = Data(#"{"kind":"snowit","age":"a","activation":true,"paid":{},"zones":{"Livigno":"livigno"}}"#.utf8)
        let read = try JSONDecoder().decode(PassPlan.self, from: old)
        XCTAssertEqual(read.kind, .snowit)
        XCTAssertNil(read.prices)
        XCTAssertNil(read.activationPrice)
    }

    func testSumsAreReadAndWritten() {
        XCTAssertEqual(MoneyField.parse("74,50"), 74.5)
        XCTAssertEqual(MoneyField.parse(" 74.5 "), 74.5)
        XCTAssertEqual(MoneyField.parse("980"), 980)
        XCTAssertNil(MoneyField.parse("settanta"))
        XCTAssertNil(MoneyField.parse("-3"))
        XCTAssertNil(MoneyField.parse(""))
        XCTAssertEqual(MoneyField.plain(980), "980")
        XCTAssertTrue(MoneyField.plain(74.5).hasPrefix("74"))
        XCTAssertTrue(Fmt.money(74.5).contains("74") && Fmt.money(74.5).contains("50"))
        XCTAssertFalse(Fmt.money(412).contains("00"), "no cents on a round sum")
        XCTAssertTrue(Fmt.money(412).contains("€"))
        XCTAssertEqual(PassCharge(amount: 59, tariff: .paid, zone: nil).note, PassCharge.Tariff.paid.label)
        XCTAssertNotEqual(PassCharge(amount: 59, tariff: .morning, zone: nil).note, PassCharge.Tariff.morning.label, "an estimate says so")
    }

    // MARK: Notifications sent by the server

    func testWhatTheServerSaidIsNotSaidAgain() throws {
        XCTAssertEqual(Push.text(Data([0x0a, 0xff, 0x01])), "0aff01")

        let json = """
        [{"id":"a","name":"Giulia","photo":0,"mine":false,"lat":45.94,"lon":7.63,"label":"Baita del Sole","when":null,
          "until":1795040000000,"at":1795000000000,"answer":null,"pushed":true},
         {"id":"me","name":"Marco","photo":0,"mine":true,"lat":45.93,"lon":7.63,"label":"Rifugio Teodulo","when":null,
          "until":1795040000000,"at":1794990000000,
          "answers":[{"id":"a","name":"Giulia","photo":0,"answer":"yes","pushed":true},{"id":"b","name":"Luca","photo":0,"answer":"no","pushed":false}]}]
        """
        let meetings = try JSONDecoder().decode([Meeting].self, from: Data(json.utf8))
        let notices = MeetingNews.notices(meetings, told: [])
        XCTAssertEqual(notices.count, 3, "all three are remembered")
        XCTAssertEqual(notices.filter(\.silent).map(\.key).sorted(), ["answer:a:1794990000000:yes", "ask:a:1795000000000"])
        XCTAssertEqual(notices.filter { !$0.silent }.map(\.key), ["answer:b:1794990000000:no"], "only what no notification was sent for")
    }
}
