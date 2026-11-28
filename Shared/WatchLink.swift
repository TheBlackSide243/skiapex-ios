import Foundation

/// The day under way as the watch shows it: told by the iPhone when the iPhone records, made by
/// the watch when the watch does. The numbers come already written, in the units chosen on the
/// iPhone. This file is in the app and in the watch app.
struct WatchState: Codable, Equatable {
    /// idle, recording or paused.
    var state: String
    /// run, lift or idle.
    var phase: String
    /// When the day began: the clock on the watch counts from here.
    var start: Date?
    /// The speed now, the number alone, and its unit.
    var speed: String
    var speedUnit: String
    var runs: Int
    var vertical: String
    var distance: String
    var maxSpeed: String
    var altitude: String
    /// Beats a minute, when the watch is the one recording.
    var heart: String?
    /// From the iPhone: seconds between two points of the GPS, as chosen in its Settings.
    var every: Double?

    static let idle = WatchState(state: "idle", phase: "idle", start: nil, speed: "0", speedUnit: "km/h", runs: 0,
                                 vertical: "–", distance: "–", maxSpeed: "–", altitude: "–")

    /// As it travels between the two: one entry of a dictionary.
    var packed: [String: Any] {
        guard let data = try? JSONEncoder().encode(self) else { return [:] }
        return [WatchLink.stateKey: data]
    }

    init(state: String, phase: String, start: Date?, speed: String, speedUnit: String, runs: Int, vertical: String,
         distance: String, maxSpeed: String, altitude: String, heart: String? = nil, every: Double? = nil) {
        self.state = state
        self.phase = phase
        self.start = start
        self.speed = speed
        self.speedUnit = speedUnit
        self.runs = runs
        self.vertical = vertical
        self.distance = distance
        self.maxSpeed = maxSpeed
        self.altitude = altitude
        self.heart = heart
        self.every = every
    }

    init?(packed: [String: Any]) {
        guard let data = packed[WatchLink.stateKey] as? Data,
              let state = try? JSONDecoder().decode(WatchState.self, from: data) else { return nil }
        self = state
    }
}

/// How often the GPS gives a point: every second for the most precise lines, less often for the
/// battery. Chosen on the iPhone; the watch follows it.
enum GPSRate: String, CaseIterable, Identifiable {
    case best, balanced, saver
    var id: String { rawValue }
    static let key = "gpsRate"

    /// Seconds between two points kept.
    var every: Double {
        switch self {
        case .best: 1
        case .balanced: 2
        case .saver: 5
        }
    }

    var label: String {
        switch self {
        case .best: "1 s"
        case .balanced: "2 s"
        case .saver: "5 s"
        }
    }

    static var current: GPSRate {
        GPSRate(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .best
    }

    /// The one closest to a number of seconds told by the iPhone.
    static func near(_ seconds: Double) -> GPSRate {
        allCases.min { abs($0.every - seconds) < abs($1.every - seconds) } ?? .best
    }

    /// A fix this long after the last point kept is kept too. A little early is fine: the GPS
    /// does not give its fixes on the dot.
    func keeps(after gap: TimeInterval) -> Bool { gap >= every - 0.3 }
}

/// What the watch asks the iPhone to do.
enum WatchCommand: String {
    case start, pause, resume, finish
}

enum WatchLink {
    static let stateKey = "state"
    static let commandKey = "command"
    /// In the answer to a command: a few words to show, when there is something to say.
    static let noteKey = "note"
    /// With the file of a day recorded on the watch: what it is, its id, and whether the watch
    /// saved its workout in Health already.
    static let kindKey = "kind"
    static let idKey = "id"
    static let healthKey = "health"
    /// From the iPhone: start recording on the watch, the day goes on there. With when it was
    /// said, so that an old order found later starts nothing.
    static let record = "record"
    static let atKey = "at"
    /// The day under way on the watch, told to the iPhone a little at a time: kind "live", when
    /// the day began, its state, the beats, and the points new since the last time with the index
    /// of the first of them.
    static let liveKind = "live"
    static let startKey = "start"
    static let stateNameKey = "stateName"
    static let heartKey = "heart"
    static let fromKey = "from"
    static let pointsKey = "points"
}
