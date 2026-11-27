import Foundation

/// Something reached with the days of the diary: a number of days, a speed, a height… Earned on
/// the day that reached it, and until then with how far along it is.
struct Trophy: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    /// From 0 to 1.
    let progress: Double
    /// The day that earned it.
    let earned: Date?

    var done: Bool { earned != nil }
}

enum Trophies {
    /// What a trophy counts.
    enum Measure {
        // Added up day after day.
        case days, vertical, distance, places, blacks, streak
        // The most in one day.
        case dayVertical, dayRuns, speed, altitude
    }

    struct Goal {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        let measure: Measure
        let target: Double
    }

    /// Every trophy there is, in the order they are shown.
    static let goals: [Goal] = [
        Goal(id: "days1", title: "Prima giornata", detail: "La prima giornata sulla neve nel diario", symbol: "snowflake", measure: .days, target: 1),
        Goal(id: "days10", title: "Dieci giornate", detail: "10 giornate sulla neve", symbol: "calendar", measure: .days, target: 10),
        Goal(id: "days25", title: "Venticinque giornate", detail: "25 giornate sulla neve", symbol: "calendar", measure: .days, target: 25),
        Goal(id: "days50", title: "Cinquanta giornate", detail: "50 giornate sulla neve", symbol: "calendar.badge.checkmark", measure: .days, target: 50),
        Goal(id: "days100", title: "Cento giornate", detail: "100 giornate sulla neve", symbol: "crown.fill", measure: .days, target: 100),
        Goal(id: "streak3", title: "Tre di fila", detail: "3 giorni di sci uno dopo l'altro", symbol: "flame", measure: .streak, target: 3),
        Goal(id: "streak7", title: "Settimana bianca", detail: "7 giorni di sci uno dopo l'altro", symbol: "flame.fill", measure: .streak, target: 7),
        Goal(id: "speed60", title: "60 all'ora", detail: "60 km/h di velocità massima", symbol: "speedometer", measure: .speed, target: 60),
        Goal(id: "speed80", title: "80 all'ora", detail: "80 km/h di velocità massima", symbol: "speedometer", measure: .speed, target: 80),
        Goal(id: "speed100", title: "Cento all'ora", detail: "100 km/h di velocità massima", symbol: "bolt.fill", measure: .speed, target: 100),
        Goal(id: "dayv5", title: "Cinquemila in un giorno", detail: "5.000 m di dislivello in una giornata", symbol: "arrow.down.right", measure: .dayVertical, target: 5000),
        Goal(id: "dayv10", title: "Diecimila in un giorno", detail: "10.000 m di dislivello in una giornata", symbol: "arrow.down.right.circle.fill", measure: .dayVertical, target: 10_000),
        Goal(id: "runs20", title: "Venti discese", detail: "20 discese in una giornata", symbol: "figure.skiing.downhill", measure: .dayRuns, target: 20),
        Goal(id: "runs30", title: "Trenta discese", detail: "30 discese in una giornata", symbol: "figure.skiing.downhill", measure: .dayRuns, target: 30),
        Goal(id: "everest", title: "Un Everest", detail: "8.849 m di dislivello in tutto", symbol: "mountain.2", measure: .vertical, target: 8849),
        Goal(id: "everest10", title: "Dieci Everest", detail: "88.490 m di dislivello in tutto", symbol: "mountain.2.fill", measure: .vertical, target: 88_490),
        Goal(id: "v250", title: "Un quarto di milione", detail: "250.000 m di dislivello in tutto", symbol: "mountain.2.fill", measure: .vertical, target: 250_000),
        Goal(id: "km100", title: "Cento chilometri", detail: "100 km sciati in tutto", symbol: "point.topleft.down.to.point.bottomright.curvepath", measure: .distance, target: 100_000),
        Goal(id: "km500", title: "Cinquecento chilometri", detail: "500 km sciati in tutto", symbol: "point.topleft.down.to.point.bottomright.curvepath", measure: .distance, target: 500_000),
        Goal(id: "km1000", title: "Mille chilometri", detail: "1.000 km sciati in tutto", symbol: "road.lanes", measure: .distance, target: 1_000_000),
        Goal(id: "alt3000", title: "Sopra i tremila", detail: "Una giornata oltre i 3.000 m di quota", symbol: "cloud", measure: .altitude, target: 3000),
        Goal(id: "alt3500", title: "Aria sottile", detail: "Una giornata oltre i 3.500 m di quota", symbol: "cloud.fill", measure: .altitude, target: 3500),
        Goal(id: "places3", title: "Tre posti", detail: "Hai sciato in 3 posti diversi", symbol: "map", measure: .places, target: 3),
        Goal(id: "places10", title: "Giramondo", detail: "Hai sciato in 10 posti diversi", symbol: "globe.europe.africa", measure: .places, target: 10),
        Goal(id: "black1", title: "Prima nera", detail: "La prima pista nera", symbol: "diamond.fill", measure: .blacks, target: 1),
        Goal(id: "black10", title: "Dieci nere", detail: "10 piste nere diverse", symbol: "diamond.fill", measure: .blacks, target: 10),
    ]

    /// The pistes the signs paint black.
    static let black: Set<String> = ["advanced", "expert", "freeride"]

    /// Every trophy with how far along it is, from the days of the diary.
    static func all(_ days: [DaySummary], calendar: Calendar = .current) -> [Trophy] {
        let ordered = days.sorted { $0.start < $1.start }
        // What each measure is worth after each day.
        var count = 0.0, vertical = 0.0, distance = 0.0, streak = 0.0, best = 0.0
        var dayVertical = 0.0, dayRuns = 0.0, speed = 0.0, altitude = 0.0
        var places: Set<String> = [], blacks: Set<String> = []
        var last: Date?
        var counted: Set<Date> = []
        var steps: [(date: Date, values: [Double])] = []
        for day in ordered {
            let morning = calendar.startOfDay(for: day.start)
            // Two recordings of one day are one day on the snow.
            if !counted.contains(morning) {
                counted.insert(morning)
                count += 1
                if let last, let gap = calendar.dateComponents([.day], from: last, to: morning).day, gap == 1 {
                    streak += 1
                } else {
                    streak = 1
                }
                best = max(best, streak)
                last = morning
            }
            vertical += day.stats.vertical
            distance += day.stats.runDistance
            dayVertical = max(dayVertical, day.stats.vertical)
            dayRuns = max(dayRuns, Double(day.stats.runs))
            speed = max(speed, day.stats.maxSpeed * 3.6)
            altitude = max(altitude, day.stats.topAlt)
            if let title = day.title, !title.isEmpty { places.insert(title.lowercased()) }
            for note in day.pistes ?? [] where black.contains(note.d ?? "") {
                blacks.insert("\(note.n.lowercased())|\(day.title?.lowercased() ?? "")")
            }
            steps.append((day.start, [count, vertical, distance, Double(places.count), Double(blacks.count), best,
                                      dayVertical, dayRuns, speed, altitude]))
        }
        func column(_ measure: Measure) -> Int {
            switch measure {
            case .days: 0
            case .vertical: 1
            case .distance: 2
            case .places: 3
            case .blacks: 4
            case .streak: 5
            case .dayVertical: 6
            case .dayRuns: 7
            case .speed: 8
            case .altitude: 9
            }
        }
        return goals.map { goal in
            let at = column(goal.measure)
            let earned = steps.first { $0.values[at] >= goal.target }?.date
            let now = steps.last?.values[at] ?? 0
            return Trophy(id: goal.id, title: goal.title, detail: goal.detail, symbol: goal.symbol,
                          progress: goal.target > 0 ? min(1, max(0, now / goal.target)) : 0, earned: earned)
        }
    }

    /// The trophies a day earned.
    static func earned(on day: DaySummary, among days: [DaySummary]) -> [Trophy] {
        all(days).filter { $0.earned == day.start }
    }
}
