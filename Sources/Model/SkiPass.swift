import Foundation

/// Who the pass is for: the age bands of the tariffs.
enum PassAge: String, Codable, CaseIterable, Identifiable {
    case adult = "a", senior = "s", teen = "t", junior = "j", baby = "b"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .adult: "Adulto"
        case .senior: "Senior"
        case .teen: "Giovane"
        case .junior: "Junior"
        case .baby: "Bambino"
        }
    }
}

/// The tariffs of SnowitPass, the pay per use ski pass of Snowit, as Snowit publishes them for a
/// season: read from its pages into `Resources/snowit.json` (the date is in `read`). Snowit has no
/// way for another app to read what it really charged, so what is made of these is an estimate.
struct SnowitBook: Decodable {
    /// A stretch of the season with its own prices.
    struct Period: Decodable, Hashable {
        let k: String
        let n: String
        /// From a day to a day, each as 20261226.
        let r: [[Int]]
        /// "or": also every Saturday, Sunday and holiday. "not": never on those. "only": only on
        /// those, inside the dates.
        let w: String?
        /// 1: the days no other period takes.
        let f: Int?
    }

    struct Rates: Decodable, Hashable {
        /// Hours and their price: [[3, 49], [4, 52]].
        var h: [[Double]]?
        /// The price of a morning, and the minute of the day it ends at.
        var am: [Double]?
        /// The price of an afternoon, and the minute of the day it begins at.
        var pm: [Double]?
        /// The price of one day, of two days in a row, of three…
        var d: [Double]?
        /// What is different on Saturdays, Sundays and holidays.
        var F: Holiday?

        struct Holiday: Decodable, Hashable {
            var h: [[Double]]?
            var am: [Double]?
            var pm: [Double]?
            var d: [Double]?
        }
    }

    struct Zone: Decodable, Identifiable, Hashable {
        let n: String
        let s: String
        /// Gold: days in a row, a day, parts of a day. Silver: a day and its parts. Bronze: a day.
        let t: String?
        /// Which tariff was taken, where a place has several.
        let v: String?
        let la: Double
        let lo: Double
        let se: [Period]?
        /// Period, then age band.
        let p: [String: [String: Rates]]?

        var id: String { s }
        var hasRates: Bool { !(p ?? [:]).isEmpty }
    }

    /// A sum spent after which skiing there is free, or discounted, until the season ends.
    struct Goal: Decodable, Identifiable, Hashable {
        let n: String
        /// "L" of a place, "R" of a region.
        let k: String
        let a: [String: Double]
        /// What is paid of a day once it is reached: 0 nothing, 0.2 a fifth.
        let x: Double
        let z: [String]

        var id: String { n }
        func target(_ age: PassAge) -> Double? { a[age.rawValue] ?? a["*"] ?? a["a"] }
    }

    let season: Int
    let read: String
    let activation: [String: Double]
    let holidays: [Int]
    let goals: [Goal]
    let zones: [Zone]

    func zone(_ slug: String?) -> Zone? {
        guard let slug else { return nil }
        return zones.first { $0.s == slug }
    }
}

/// A day as a ski pass sees it.
struct PassDay: Equatable {
    let id: UUID
    let start: Date
    /// The first and the last time through a gate: the first lift taken and the last. nil when
    /// not known, and then the day counts as a whole one.
    var first: Date?
    var last: Date?
    /// The Snowit place it was in, when it was in one.
    var zone: String?
}

/// What a day cost, or is reckoned to have cost.
struct PassCharge: Equatable {
    enum Tariff: Equatable {
        /// What you wrote you paid.
        case paid
        case day, hours(Int), morning, afternoon
        /// The second, third… day in a row.
        case days(Int)
        /// A spending goal was reached: free, or discounted.
        case reached, discounted
        /// Another recording of a day already counted.
        case same
        case unknown
    }

    var amount: Double?
    var tariff: Tariff
    var zone: String?

    var estimated: Bool { tariff != .paid && tariff != .same }
}

/// How far a spending goal of SnowitPass is.
struct PassGoalState: Identifiable, Equatable {
    let goal: SnowitBook.Goal
    let target: Double
    let spent: Double

    var id: String { goal.n }
    var reached: Bool { spent >= target }
    var left: Double { max(0, target - spent) }
    var fraction: Double { target > 0 ? min(1, spent / target) : 0 }
}

/// The days of a season with what each cost.
struct PassBill: Equatable {
    var charges: [UUID: PassCharge] = [:]
    var goals: [PassGoalState] = []
    var activation: Double = 0
    /// The days whose cost is not known.
    var unknown = 0

    /// What is known of the days, and the activation.
    var total: Double { charges.values.reduce(activation) { $0 + ($1.amount ?? 0) } }
    /// The days that count as days on a pass: two recordings of one day are one.
    var days: Int { charges.values.filter { $0.tariff != .same }.count }
}

enum Snowit {
    /// The tariffs that come with the app.
    static let book: SnowitBook? = {
        guard let url = Bundle(for: Library.self).url(forResource: "snowit", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SnowitBook.self, from: data)
    }()

    /// The places of SnowitPass are in Italy: days and hours are read there.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        return calendar
    }()

    /// A moment as 20261226.
    static func stamp(_ date: Date) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    /// The minute of the day of a moment.
    static func minute(_ date: Date) -> Double {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    /// The days from a fixed one, to tell two days in a row.
    static func ordinal(_ date: Date) -> Int {
        let start = calendar.startOfDay(for: date)
        return Int(((start.timeIntervalSinceReferenceDate + Double(calendar.timeZone.secondsFromGMT(for: start))) / 86_400).rounded())
    }

    /// A Saturday, a Sunday or a holiday.
    static func isFree(_ date: Date, in book: SnowitBook) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7 || book.holidays.contains(stamp(date))
    }

    /// The place of SnowitPass a point is in: the closest, within twelve kilometers.
    static func zone(lat: Double, lon: Double, in book: SnowitBook) -> SnowitBook.Zone? {
        let near = book.zones.map { ($0, Geo.distance(lat1: lat, lon1: lon, lat2: $0.la, lon2: $0.lo)) }.min { $0.1 < $1.1 }
        guard let near, near.1 <= 12_000 else { return nil }
        return near.0
    }

    /// The place of SnowitPass a name is of: for the days written by hand.
    static func zone(named name: String, in book: SnowitBook) -> SnowitBook.Zone? {
        let wanted = name.lowercased().trimmingCharacters(in: .whitespaces)
        guard wanted.count >= 4 else { return nil }
        return book.zones.first { $0.n.lowercased() == wanted }
            ?? book.zones.first { $0.n.lowercased().contains(wanted) || wanted.contains($0.n.lowercased()) }
    }

    /// The period a day falls in: the most particular one that takes it, then the one for the
    /// days nobody takes, then the closest in time.
    static func period(of zone: SnowitBook.Zone, on date: Date, in book: SnowitBook) -> SnowitBook.Period? {
        let day = stamp(date)
        let free = isFree(date, in: book)
        let periods = (zone.se ?? []).filter { zone.p?[$0.k] != nil }
        func line(_ stamp: Int) -> Int { (stamp / 10_000) * 372 + ((stamp / 100) % 100) * 31 + stamp % 100 }
        func inside(_ p: SnowitBook.Period) -> Bool { p.r.contains { $0.count == 2 && $0[0] <= day && day <= $0[1] } }
        func takes(_ p: SnowitBook.Period) -> Bool {
            switch p.w {
            case "or": inside(p) || free
            case "not": (p.r.isEmpty || inside(p)) && !free
            case "only": inside(p) && free
            default: p.r.isEmpty || inside(p)
            }
        }
        func length(_ p: SnowitBook.Period) -> Int { p.r.reduce(0) { $0 + ($1.count == 2 ? line($1[1]) - line($1[0]) + 1 : 0) } }
        if let exact = periods.filter({ $0.f != 1 && takes($0) }).min(by: { length($0) < length($1) }) { return exact }
        if let rest = periods.first(where: { $0.f == 1 && takes($0) }) { return rest }
        func gap(_ p: SnowitBook.Period) -> Int {
            p.r.map { $0.count == 2 ? min(abs(line($0[0]) - line(day)), abs(line($0[1]) - line(day))) : Int.max }.min() ?? Int.max
        }
        return periods.min { gap($0) < gap($1) }
    }

    /// The prices of a place on a day for an age band: the adult's where the band has none.
    static func rates(of zone: SnowitBook.Zone, on date: Date, age: PassAge, in book: SnowitBook) -> SnowitBook.Rates? {
        guard let stretch = period(of: zone, on: date, in: book), let table = zone.p?[stretch.k],
              var rates = table[age.rawValue] ?? table["a"] else { return nil }
        if let other = rates.F {
            if isFree(date, in: book) {
                rates.h = other.h ?? rates.h
                rates.am = other.am ?? rates.am
                rates.pm = other.pm ?? rates.pm
                rates.d = other.d ?? rates.d
            } else if rates.d == nil {
                rates.d = other.d
            }
        }
        return rates
    }

    /// The price of a whole day at the ticket office of SnowitPass: what a day pass is worth.
    static func dayPrice(of zone: SnowitBook.Zone, on date: Date, age: PassAge, in book: SnowitBook) -> Double? {
        rates(of: zone, on: date, age: age, in: book)?.d?.first
    }

    /// What SnowitPass is reckoned to charge for a day: the cheapest of the whole day, the hours
    /// from the first gate to the last, the morning, the afternoon and, where days in a row are
    /// counted, what one more day adds.
    static func estimate(_ day: PassDay, zone: SnowitBook.Zone, age: PassAge, streak: Int, in book: SnowitBook) -> PassCharge {
        guard let prices = rates(of: zone, on: day.start, age: age, in: book), let full = prices.d?.first else {
            return PassCharge(amount: nil, tariff: .unknown, zone: zone.s)
        }
        var best = full
        var tariff = PassCharge.Tariff.day
        if let first = day.first, let last = day.last, last >= first {
            let span = last.timeIntervalSince(first)
            if let band = (prices.h ?? []).first(where: { $0.count == 2 && $0[0] * 3600 >= span }), band[1] < best {
                best = band[1]
                tariff = .hours(Int(band[0]))
            }
            if let am = prices.am, am.count == 2, minute(last) <= am[1], am[0] < best {
                best = am[0]
                tariff = .morning
            }
            if let pm = prices.pm, pm.count == 2, minute(first) >= pm[1], pm[0] < best {
                best = pm[0]
                tariff = .afternoon
            }
        }
        if zone.t == "Gold", streak >= 2, let days = prices.d, days.count >= 2 {
            let n = min(streak, days.count)
            let more = days[n - 1] - days[n - 2]
            if more > 0, more < best {
                best = more
                tariff = .days(streak)
            }
        }
        return PassCharge(amount: best, tariff: tariff, zone: zone.s)
    }

    /// The days of a season with what each cost. `payPerUse`: as SnowitPass charges, with the
    /// parts of a day, the days in a row and the spending goals. Otherwise the price of a day
    /// pass each. What you wrote you paid always comes first.
    static func bill(_ days: [PassDay], age: PassAge, paid: [UUID: Double], payPerUse: Bool, activation: Bool,
                     in book: SnowitBook) -> PassBill {
        var bill = PassBill()
        var spent: [String: Double] = [:]
        var streaks: [String: (day: Int, count: Int)] = [:]
        var counted: Set<String> = []
        for day in days.sorted(by: { $0.start < $1.start }) {
            let zone = book.zone(day.zone)
            let key = "\(stamp(day.start))|\(zone?.s ?? "-")"
            if counted.contains(key), paid[day.id] == nil {
                bill.charges[day.id] = PassCharge(amount: 0, tariff: .same, zone: zone?.s)
                continue
            }
            counted.insert(key)
            var streak = 1
            if let zone {
                let today = ordinal(day.start)
                if let last = streaks[zone.s], today - last.day == 1 { streak = last.count + 1 }
                streaks[zone.s] = (today, streak)
            }
            let goals = payPerUse ? book.goals.filter { goal in zone.map { goal.z.contains($0.s) } ?? false } : []
            var charge: PassCharge
            if let real = paid[day.id] {
                charge = PassCharge(amount: max(0, real), tariff: .paid, zone: zone?.s)
            } else if let zone, payPerUse {
                charge = estimate(day, zone: zone, age: age, streak: streak, in: book)
                if let amount = charge.amount {
                    var factor = 1.0
                    var room = Double.infinity
                    for goal in goals {
                        guard let target = goal.target(age) else { continue }
                        let before = spent[goal.n] ?? 0
                        if before >= target {
                            factor = min(factor, goal.x)
                        } else if goal.x == 0 {
                            room = min(room, target - before)
                        }
                    }
                    if factor < 1 {
                        charge.amount = amount * factor
                        charge.tariff = factor == 0 ? .reached : .discounted
                    } else if amount > room {
                        charge.amount = room
                    }
                }
            } else if let zone, let price = dayPrice(of: zone, on: day.start, age: age, in: book) {
                charge = PassCharge(amount: price, tariff: .day, zone: zone.s)
            } else {
                charge = PassCharge(amount: nil, tariff: .unknown, zone: zone?.s)
            }
            if let amount = charge.amount {
                for goal in goals { spent[goal.n, default: 0] += amount }
            } else {
                bill.unknown += 1
            }
            bill.charges[day.id] = charge
        }
        if payPerUse {
            bill.goals = book.goals.compactMap { goal in
                guard let target = goal.target(age), let sum = spent[goal.n] else { return nil }
                return PassGoalState(goal: goal, target: target, spent: sum)
            }
            if activation { bill.activation = book.activation[age.rawValue] ?? 0 }
        }
        return bill
    }
}

/// How the ski pass of a season is paid, and what was written of it by hand.
struct PassPlan: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case off, season, daily, snowit

        var id: String { rawValue }
        var title: String {
            switch self {
            case .off: "Non lo segno"
            case .season: "Stagionale"
            case .daily: "Giornalieri"
            case .snowit: "SnowitPass"
            }
        }
    }

    var kind = Kind.off
    /// What the season pass cost.
    var seasonPrice: Double?
    var age = PassAge.adult
    /// Count what turning SnowitPass on costs.
    var activation = true
    /// What was really paid for a day, by the id of the day.
    var paid: [String: Double] = [:]
    /// The Snowit place chosen by hand for the days of a place, by the name of the place. "-": none.
    var zones: [String: String] = [:]
}

/// What skiing cost in a season.
struct PassSummary: Equatable {
    var bill = PassBill()
    /// All of it: the season pass, or the days and the activation.
    var total: Double = 0
    /// What the days would have cost with a day pass each, where the price is known.
    var list: Double = 0
    var listDays = 0
    var days = 0
    var runs = 0
    var vertical: Double = 0

    var perDay: Double? { days > 0 ? total / Double(days) : nil }
    var perRun: Double? { runs > 0 ? total / Double(runs) : nil }
    /// For every thousand meters down.
    var perKilometer: Double? { vertical >= 100 ? total / (vertical / 1000) : nil }
    /// With a season pass: how many more days like the ones so far until it has paid for itself.
    var daysToPayOff: Int? {
        guard listDays > 0, list < total else { return nil }
        return Int(((total - list) / (list / Double(listDays))).rounded(.up))
    }
}

enum Passes {
    private static let key = "passPlans"

    private static func all(_ defaults: UserDefaults) -> [String: PassPlan] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: PassPlan].self, from: data)) ?? [:]
    }

    static func plan(of season: Season, in defaults: UserDefaults = .standard) -> PassPlan {
        all(defaults)[String(season.year)] ?? PassPlan()
    }

    static func set(_ plan: PassPlan, for season: Season, in defaults: UserDefaults = .standard) {
        var kept = all(defaults)
        kept[String(season.year)] = plan
        defaults.set(try? JSONEncoder().encode(kept), forKey: key)
    }

    /// A day of the diary as a ski pass sees it: when the first and the last lift were taken,
    /// and in which place of SnowitPass it was.
    static func passDay(_ day: DaySummary, plan: PassPlan, book: SnowitBook?) -> PassDay {
        var first: Date?
        var last: Date?
        if let shape = day.shape {
            var time = day.start
            for leg in shape {
                if leg.k == 1 {
                    if first == nil { first = time }
                    last = time
                }
                time = time.addingTimeInterval(leg.s)
            }
        }
        var zone: String?
        if let book {
            if let chosen = day.title.flatMap({ plan.zones[$0] }) {
                zone = chosen == "-" ? nil : chosen
            } else if let lat = day.lat, let lon = day.lon {
                zone = Snowit.zone(lat: lat, lon: lon, in: book)?.s
            } else if let title = day.title {
                zone = Snowit.zone(named: title, in: book)?.s
            }
        }
        return PassDay(id: day.id, start: day.start, first: first, last: last, zone: zone)
    }

    /// What the days of a season cost, by how the pass is paid.
    static func summary(_ plan: PassPlan, days: [DaySummary], book: SnowitBook?) -> PassSummary {
        var out = PassSummary()
        guard plan.kind != .off else { return out }
        let passDays = days.map { passDay($0, plan: plan, book: book) }
        var paid: [UUID: Double] = [:]
        for (id, amount) in plan.paid {
            if let id = UUID(uuidString: id) { paid[id] = amount }
        }
        let empty = SnowitBook(season: 0, read: "", activation: [:], holidays: [], goals: [], zones: [])
        let tariffs = book ?? empty
        let list = Snowit.bill(passDays, age: plan.age, paid: [:], payPerUse: false, activation: false, in: tariffs)
        out.list = list.total
        out.listDays = list.days - list.unknown
        switch plan.kind {
        case .snowit:
            out.bill = Snowit.bill(passDays, age: plan.age, paid: paid, payPerUse: true, activation: plan.activation, in: tariffs)
            out.total = out.bill.total
        case .daily:
            out.bill = Snowit.bill(passDays, age: plan.age, paid: paid, payPerUse: false, activation: false, in: tariffs)
            out.total = out.bill.total
        case .season:
            out.bill = list
            out.total = plan.seasonPrice ?? 0
        case .off:
            break
        }
        // With a season pass every day counts. Otherwise only the days whose cost is known: a
        // day with no price would make the others look cheaper than they were.
        let counted = plan.kind == .season ? days : days.filter { out.bill.charges[$0.id]?.amount != nil }
        out.days = plan.kind == .season ? out.bill.days : out.bill.days - out.bill.unknown
        out.runs = counted.reduce(0) { $0 + $1.stats.runs }
        out.vertical = counted.reduce(0) { $0 + $1.stats.vertical }
        return out
    }

    /// For the screenshots.
    static let demo = PassPlan(kind: .snowit)
}
