import Foundation

/// What you set out to do in a season: days on the snow, meters down, meters skied. Any of the
/// three, or none.
struct SeasonGoals: Codable, Equatable {
    var days: Int?
    /// Meters down.
    var vertical: Double?
    /// Meters skied.
    var distance: Double?

    var isEmpty: Bool { days == nil && vertical == nil && distance == nil }
}

/// One goal, with how far along it is.
struct GoalProgress: Identifiable, Equatable {
    enum Kind: String, CaseIterable { case days, vertical, distance }

    let kind: Kind
    let target: Double
    let done: Double

    var id: String { kind.rawValue }
    var fraction: Double { target > 0 ? min(1, max(0, done / target)) : 0 }
    var reached: Bool { target > 0 && done >= target }
    var left: Double { max(0, target - done) }
}

/// The goals of each season, kept on the iPhone.
enum Goals {
    private static let key = "seasonGoals"

    private static func all(_ defaults: UserDefaults) -> [String: SeasonGoals] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: SeasonGoals].self, from: data)) ?? [:]
    }

    static func of(_ season: Season, in defaults: UserDefaults = .standard) -> SeasonGoals {
        all(defaults)[String(season.year)] ?? SeasonGoals()
    }

    static func set(_ goals: SeasonGoals, for season: Season, in defaults: UserDefaults = .standard) {
        var kept = all(defaults)
        kept[String(season.year)] = goals.isEmpty ? nil : goals
        defaults.set(try? JSONEncoder().encode(kept), forKey: key)
    }

    /// How far along each goal set is, with the days of that season.
    static func progress(_ goals: SeasonGoals, days: [DaySummary]) -> [GoalProgress] {
        var out: [GoalProgress] = []
        if let target = goals.days, target > 0 {
            out.append(GoalProgress(kind: .days, target: Double(target), done: Double(days.count)))
        }
        if let target = goals.vertical, target > 0 {
            out.append(GoalProgress(kind: .vertical, target: target, done: days.reduce(0) { $0 + $1.stats.vertical }))
        }
        if let target = goals.distance, target > 0 {
            out.append(GoalProgress(kind: .distance, target: target, done: days.reduce(0) { $0 + $1.stats.runDistance }))
        }
        return out
    }

    /// When the lifts usually stop: the middle of April of the year the season ends in.
    static func end(of season: Season, calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: season.year + 1, month: 4, day: 15)) ?? Date()
    }

    /// How much a week it takes to get there by the end of the season. nil when it is reached,
    /// and when the season is over.
    static func weekly(_ goal: GoalProgress, season: Season, now: Date = Date(), calendar: Calendar = .current) -> Double? {
        guard !goal.reached else { return nil }
        let left = end(of: season, calendar: calendar).timeIntervalSince(now)
        guard left > 0 else { return nil }
        return goal.left / max(1, left / (7 * 86_400))
    }

    /// For the screenshots.
    static let demo = SeasonGoals(days: 12, vertical: 60_000, distance: 300_000)
}
