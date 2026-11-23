import Foundation
import UIKit
import WatchConnectivity

/// The iPhone's side of the Apple Watch app. When the iPhone records, it tells the watch the
/// numbers of the day under way and does what its buttons ask (start, pause, resume, finish).
/// When the watch records by itself, the day arrives here as a file when it ends, and is kept
/// with the others.
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    private var last: WatchState?

    /// Called once, at launch.
    func start() {
        guard WCSession.isSupported(), !Demo.isOn else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// The day under way as the watch shows it.
    static func state(of recorder: Recorder) -> WatchState {
        let stats = recorder.analysis.stats
        let phase: String
        let state: String
        switch recorder.state {
        case .idle:
            return WatchState.idle
        case .paused:
            state = "paused"
            phase = "paused"
        case .recording:
            state = "recording"
            phase = recorder.analysis.current.rawValue
        }
        var speed = 0.0
        if recorder.state == .recording, let point = recorder.lastPoint, point.speed >= 0, Date().timeIntervalSince(point.t) < 15 {
            speed = point.speed
        }
        return WatchState(state: state, phase: phase, start: recorder.startDate, speed: Fmt.speedValue(speed), speedUnit: Fmt.speedUnit,
                          runs: stats.runs, vertical: Fmt.height(stats.vertical), distance: Fmt.distance(stats.runDistance),
                          maxSpeed: Fmt.speed(stats.maxSpeed), altitude: recorder.lastPoint.map { Fmt.height($0.alt) } ?? "–")
    }

    /// Tells the watch, if there is one with the app and something changed.
    func push(_ state: WatchState) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.delegate === self, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else {
            last = nil
            return
        }
        guard state != last else { return }
        last = state
        let packed = state.packed
        // At once when the watch app is on screen; and kept for when it opens.
        if session.isReachable { session.sendMessage(packed, replyHandler: nil, errorHandler: nil) }
        try? session.updateApplicationContext(packed)
    }

    private func pushNow() {
        DispatchQueue.main.async {
            self.last = nil
            self.push(Self.state(of: Shared.recorder))
        }
    }

    /// Does what a button of the watch asks. The words are for the watch to show, when it could
    /// not be done or there is something to say.
    @MainActor static func run(_ command: WatchCommand) -> String? {
        let recorder = Shared.recorder
        // The location starts only with the app in front, unless it is always allowed.
        let canBegin = UIApplication.shared.applicationState == .active || recorder.authorization == .authorizedAlways
        switch command {
        case .start, .resume:
            guard recorder.state != .recording else { return nil }
            guard recorder.canRecord else { return String(localized: "Apri Ski Apex sull'iPhone e consenti la posizione.") }
            guard canBegin else { return String(localized: "Apri Ski Apex sull'iPhone, poi riprova.") }
            if recorder.state == .paused { recorder.resume() } else { recorder.start() }
            return nil
        case .pause:
            recorder.pause()
            return nil
        case .finish:
            guard recorder.state != .idle else { return nil }
            do {
                guard let day = try Session.finish() else { return String(localized: "Troppo pochi punti GPS: niente da salvare.") }
                return String(localized: "Giornata salvata: \(day.stats.runs) discese, \(Fmt.height(day.stats.vertical)) di dislivello.")
            } catch {
                return String(localized: "Non riesco a salvare la giornata: apri Ski Apex sull'iPhone.")
            }
        }
    }

    /// Keeps a day recorded on the watch. False when there is nothing to keep: too few points,
    /// or a day that is here already (a file sent twice).
    @discardableResult static func keep(_ points: [TrackPoint], id: UUID, inHealth: Bool, in library: Library) -> Bool {
        guard Segmenter.clean(points).count >= 10, library.day(id) == nil else { return false }
        var day = SkiDay(id: id, points: points, sport: Sport.current)
        // Saved in Health by the watch, with the heart rate: not to be saved again from here.
        if inHealth { day.inHealth = true }
        do {
            try library.save(day)
            return true
        } catch {
            return false
        }
    }

    /// The points of a file written by the watch: one JSON a line.
    static func points(in data: Data) -> [TrackPoint] {
        let decoder = JSONDecoder()
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(TrackPoint.self, from: Data($0)) }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // The file is gone when this returns: read now.
        guard file.metadata?[WatchLink.kindKey] as? String == "day", let data = try? Data(contentsOf: file.fileURL) else { return }
        let points = Self.points(in: data)
        let id = (file.metadata?[WatchLink.idKey] as? String).flatMap { UUID(uuidString: $0) } ?? UUID()
        let inHealth = file.metadata?[WatchLink.healthKey] as? Bool ?? false
        DispatchQueue.main.async {
            guard Self.keep(points, id: id, inHealth: inHealth, in: Shared.library), let start = points.first?.t else { return }
            // The friends' leaderboard hears about the new day.
            Task { await Shared.social.refresh(season: Season(start), days: Shared.library.days) }
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        pushNow()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Another watch was paired: with the new one.
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable { pushNow() }
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        pushNow()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let name = message[WatchLink.commandKey] as? String, let command = WatchCommand(rawValue: name) else {
            replyHandler([:])
            return
        }
        Task { @MainActor in
            let note = Self.run(command)
            let state = Self.state(of: Shared.recorder)
            var answer = state.packed
            if let note { answer[WatchLink.noteKey] = note }
            replyHandler(answer)
            self.last = state
            try? session.updateApplicationContext(state.packed)
        }
    }
}
