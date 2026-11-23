import Foundation

/// The day under way as the iPhone tells it to the Apple Watch. The numbers come already
/// written, in the units chosen on the iPhone. This file is in the app, which writes it, and in
/// the watch app, which shows it.
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

    static let idle = WatchState(state: "idle", phase: "idle", start: nil, speed: "0", speedUnit: "km/h", runs: 0,
                                 vertical: "–", distance: "–", maxSpeed: "–", altitude: "–")

    /// As it travels between the two: one entry of a dictionary.
    var packed: [String: Any] {
        guard let data = try? JSONEncoder().encode(self) else { return [:] }
        return [WatchLink.stateKey: data]
    }

    init(state: String, phase: String, start: Date?, speed: String, speedUnit: String, runs: Int, vertical: String,
         distance: String, maxSpeed: String, altitude: String) {
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
}
