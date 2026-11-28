import Foundation
import Observation

/// The day the Apple Watch is recording by itself, as it tells it a little at a time: here its
/// numbers and its line on the map while it goes on. Kept in a file, so that it is still here
/// when the app is opened again later. It goes away when the day itself arrives as a file at the
/// end (see `WatchBridge`).
@Observable final class WatchDay {
    static let shared: WatchDay = Demo.isOn ? Demo.watchDay() : WatchDay()

    enum State: String { case recording, paused, ended }

    /// nil: no day under way on the watch.
    private(set) var state: State?
    private(set) var start: Date?
    /// Beats a minute, the last ones told.
    private(set) var heart: Int?
    /// When the watch last said something.
    private(set) var updated: Date?
    private(set) var analysis = Segmenter.Result.empty
    private(set) var tracks: [MapTrack] = []
    private(set) var lastPoint: TrackPoint?
    @ObservationIgnored private(set) var points: [TrackPoint] = []
    /// The points recorded on the iPhone before the day went to the watch: shown with it.
    @ObservationIgnored private var before: [TrackPoint] = []

    private let file: URL?
    private static let metaKey = "watchDay"

    var active: Bool { state != nil }

    /// `directory` nil: nothing on disk (the demo, the tests).
    init(directory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first) {
        file = directory?.appendingPathComponent("watch-day.jsonl")
        load()
    }

    /// For the demo: a day under way on the watch.
    static func preview(_ points: [TrackPoint], heart: Int?) -> WatchDay {
        let day = WatchDay(directory: nil)
        day.points = points
        day.start = points.first?.t
        day.state = .recording
        day.heart = heart
        day.updated = points.last?.t
        day.refresh()
        return day
    }

    /// What the watch told (see `WatchRecorder.tell()`). `before`: the points of the iPhone, when
    /// the day began there and went on on the watch.
    func take(_ packet: [String: Any], before: [TrackPoint] = []) {
        guard packet[WatchLink.kindKey] as? String == WatchLink.liveKind else { return }
        self.before = before
        let begun = packet[WatchLink.startKey] as? Date
        let from = max(0, packet[WatchLink.fromKey] as? Int ?? 0)
        let new = WatchBridge.points(in: packet[WatchLink.pointsKey] as? Data ?? Data())
        var rewrite = false
        // Another day: the one before is gone (it arrived, or it was too short to keep).
        if let begun, begun != start {
            start = begun
            points = []
            rewrite = true
        }
        // Told again from an earlier point: what was here from there is replaced.
        if from < points.count {
            points.removeSubrange(from...)
            rewrite = true
        }
        let last = points.last?.t ?? .distantPast
        let fresh = new.filter { $0.t > last }
        points += fresh
        switch packet[WatchLink.stateNameKey] as? String {
        case "idle": state = .ended
        case "paused": state = .paused
        default: state = .recording
        }
        heart = packet[WatchLink.heartKey] as? Int
        updated = Date()
        // Ended with too little to keep: the watch sends no day, nothing is waited for.
        if state == .ended, Segmenter.clean(points).count < 10 {
            clear()
            return
        }
        if rewrite { write(points) } else { append(fresh) }
        saveMeta()
        refresh()
    }

    /// The day arrived, or there is none: nothing more to show.
    func clear() {
        state = nil
        start = nil
        heart = nil
        updated = nil
        points = []
        before = []
        lastPoint = nil
        analysis = .empty
        tracks = []
        if let file { try? FileManager.default.removeItem(at: file) }
        if file != nil { UserDefaults.standard.removeObject(forKey: Self.metaKey) }
    }

    /// The points of the iPhone from before, when the day went from the iPhone to the watch.
    func setBefore(_ points: [TrackPoint]) {
        guard active, points.count != before.count else { return }
        before = points
        refresh()
    }

    /// The speed now, when the watch said it a moment ago.
    var speed: Double? {
        guard state == .recording, let point = lastPoint, point.speed >= 0,
              Demo.isOn || Date().timeIntervalSince(point.t) < 40 else { return nil }
        return point.speed
    }

    private func refresh() {
        let all = before.isEmpty ? points : WatchBridge.join(before, points)
        let clean = Segmenter.clean(all)
        analysis = Segmenter.analyze(clean)
        tracks = MapTrack.build(points: clean, segments: analysis.segments)
        lastPoint = points.last ?? before.last
    }

    // MARK: On disk

    private func load() {
        guard let file, let meta = UserDefaults.standard.dictionary(forKey: Self.metaKey),
              let name = meta["state"] as? String, let state = State(rawValue: name),
              let updated = meta["updated"] as? Date else { return }
        // A day the watch never ended, or whose end never came: forgotten after a day and a night.
        guard Date().timeIntervalSince(updated) < 20 * 3600,
              let data = try? Data(contentsOf: file) else {
            clear()
            return
        }
        points = WatchBridge.points(in: data)
        self.state = state
        self.updated = updated
        start = meta["start"] as? Date
        heart = meta["heart"] as? Int
        refresh()
    }

    private func saveMeta() {
        guard file != nil, let state else { return }
        var meta: [String: Any] = ["state": state.rawValue, "updated": updated ?? Date()]
        if let start { meta["start"] = start }
        if let heart { meta["heart"] = heart }
        UserDefaults.standard.set(meta, forKey: Self.metaKey)
    }

    private func lines(_ points: [TrackPoint]) -> Data {
        let encoder = JSONEncoder()
        var data = Data()
        for point in points {
            guard let line = try? encoder.encode(point) else { continue }
            data.append(line)
            data.append(0x0A)
        }
        return data
    }

    private func write(_ points: [TrackPoint]) {
        guard let file else { return }
        try? lines(points).write(to: file, options: .atomic)
    }

    private func append(_ points: [TrackPoint]) {
        guard let file, !points.isEmpty else { return }
        guard let handle = try? FileHandle(forWritingTo: file) else {
            write(self.points)
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: lines(points))
    }
}
