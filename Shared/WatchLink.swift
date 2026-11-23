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

    static let idle = WatchState(state: "idle", phase: "idle", start: nil, speed: "0", speedUnit: "km/h", runs: 0,
                                 vertical: "–", distance: "–", maxSpeed: "–", altitude: "–")

    /// As it travels between the two: one entry of a dictionary.
    var packed: [String: Any] {
        guard let data = try? JSONEncoder().encode(self) else { return [:] }
        return [WatchLink.stateKey: data]
    }

    init(state: String, phase: String, start: Date?, speed: String, speedUnit: String, runs: Int, vertical: String,
         distance: String, maxSpeed: String, altitude: String, heart: String? = nil) {
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
    }

    init?(packed: [String: Any]) {
        guard let data = packed[WatchLink.stateKey] as? Data,
              let state = try? JSONDecoder().decode(WatchState.self, from: data) else { return nil }
        self = state
    }
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
}
