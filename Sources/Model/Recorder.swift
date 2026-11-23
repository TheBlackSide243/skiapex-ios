import CoreLocation
import CoreMotion
import Foundation
import Observation

/// Records the day: the GPS about once a second, even with the screen off and the iPhone in a
/// pocket, and the barometer for the altitude. Every point is also written to a file as it comes,
/// so that a day is not lost if the app is closed or iOS ends it: it is found again at the next
/// launch, paused.
@Observable final class Recorder: NSObject, CLLocationManagerDelegate {
    enum State { case idle, recording, paused }

    private(set) var state: State = .idle
    private(set) var startDate: Date?
    /// The numbers so far, worked out again every few seconds while the app is on screen.
    private(set) var analysis = Segmenter.Result.empty
    /// The lines for the map, made with the numbers.
    private(set) var tracks: [MapTrack] = []
    private(set) var lastPoint: TrackPoint?
    /// The last fix, also one too imprecise to keep: for the accuracy shown on screen.
    private(set) var lastFix: CLLocation?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var pointCount = 0
    /// The recording was found at launch, left from before.
    private(set) var recovered = false
    let hasBarometer = CMAltimeter.isRelativeAltitudeAvailable()

    /// The numbers are worked out only when someone can see them: see `setActive(_:)`.
    @ObservationIgnored private var appIsActive = true

    @ObservationIgnored private(set) var points: [TrackPoint] = []
    private let manager = CLLocationManager()
    private let altimeter = CMAltimeter()
    private let journal: Journal?
    /// The barometer's change of altitude since it was started.
    @ObservationIgnored private var baro: Double?
    /// GPS altitude minus barometer: the barometer is precise from one moment to the next, the
    /// GPS right on average. This follows the GPS slowly.
    @ObservationIgnored private var offset: Double?
    @ObservationIgnored private var gpsAlt: Double?
    @ObservationIgnored private var lastRefresh = Date.distantPast
    @ObservationIgnored private var startWhenAllowed = false
    @ObservationIgnored private var background: CLBackgroundActivitySession?

    /// `journal` nil: nothing on disk (the demo, the tests).
    init(journal: Journal? = Journal()) {
        self.journal = journal
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
        if let saved = journal?.load(), !saved.isEmpty {
            points = saved
            startDate = saved.first?.t
            lastPoint = saved.last
            pointCount = saved.count
            state = .paused
            recovered = true
            journal?.reopen()
            refresh()
        }
    }

    /// For the demo: a day under way, without sensors.
    static func preview(_ points: [TrackPoint]) -> Recorder {
        let r = Recorder(journal: nil)
        r.points = points
        r.startDate = points.first?.t
        r.lastPoint = points.last
        r.pointCount = points.count
        r.state = .recording
        r.refresh()
        return r
    }

    var canRecord: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var denied: Bool { authorization == .denied || authorization == .restricted }

    /// Where the iPhone last was, when the location is allowed: for the ski areas nearby.
    var here: CLLocation? { canRecord ? manager.location : nil }

    // MARK: What the buttons do

    func start() {
        guard state == .idle else { return }
        guard canRecord else {
            startWhenAllowed = true
            manager.requestWhenInUseAuthorization()
            return
        }
        points = []
        pointCount = 0
        lastPoint = nil
        analysis = .empty
        tracks = []
        startDate = Date()
        recovered = false
        journal?.begin()
        resume()
    }

    func resume() {
        guard state != .recording else { return }
        state = .recording
        recovered = false
        background = CLBackgroundActivitySession()
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        startBarometer()
        refresh()
    }

    func pause() {
        guard state == .recording else { return }
        state = .paused
        stopSensors()
        refresh()
    }

    /// Ends the day and gives its points. The file stays until `forget()`, so that nothing is
    /// lost if the day cannot be saved.
    func stop() -> [TrackPoint] {
        stopSensors()
        state = .idle
        let all = points
        refresh()
        return all
    }

    /// Back to paused after a `stop()` whose day could not be saved: the points are all there.
    func hold() {
        guard state == .idle, !points.isEmpty else { return }
        state = .paused
        refresh()
    }

    /// Clears what was recorded, from the screen and from the disk.
    func forget() {
        stopSensors()
        state = .idle
        points = []
        pointCount = 0
        lastPoint = nil
        startDate = nil
        analysis = .empty
        tracks = []
        recovered = false
        journal?.finish()
        if journal != nil { LiveStatus.end() }
    }

    /// From the scene: on screen or not.
    func setActive(_ active: Bool) {
        let was = appIsActive
        appIsActive = active
        if active && !was { refresh() }
    }

    /// Worked out again now: the numbers and the lines on the map.
    func refresh() {
        lastRefresh = Date()
        let clean = Segmenter.clean(points)
        analysis = Segmenter.analyze(clean)
        tracks = MapTrack.build(points: clean, segments: analysis.segments)
        // The lock screen and the Dynamic Island, for a real recording only.
        if journal != nil {
            LiveStatus.update(state: state, analysis: analysis, start: startDate)
            // And the friends, when sharing is on.
            LiveShare.update(state: state, point: lastPoint, phase: analysis.current)
        }
    }

    // MARK: Sensors

    private func startBarometer() {
        baro = nil
        offset = nil
        guard hasBarometer else { return }
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            self.baro = data.relativeAltitude.doubleValue
        }
    }

    private func stopSensors() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        altimeter.stopRelativeAltitudeUpdates()
        background?.invalidate()
        background = nil
    }

    /// The altitude of a fix: the barometer brought to the GPS's level when there is one.
    private func altitude(of fix: CLLocation) -> Double {
        let gpsGood = fix.verticalAccuracy > 0 && fix.verticalAccuracy <= 20
        if let baro {
            if let current = offset {
                if gpsGood { offset = current + 0.02 * (fix.altitude - baro - current) }
            } else if gpsGood {
                offset = fix.altitude - baro
            }
            if let offset { return baro + offset }
        }
        if let previous = gpsAlt {
            gpsAlt = gpsGood ? previous + 0.25 * (fix.altitude - previous) : previous
        } else {
            gpsAlt = fix.altitude
        }
        return gpsAlt ?? fix.altitude
    }

    private func add(_ fix: CLLocation) {
        lastFix = fix
        guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 50 else { return }
        if let last = points.last, fix.timestamp <= last.t { return }
        let point = TrackPoint(t: fix.timestamp,
                               lat: fix.coordinate.latitude, lon: fix.coordinate.longitude,
                               alt: altitude(of: fix),
                               speed: fix.speed, hAcc: fix.horizontalAccuracy, sAcc: fix.speedAccuracy)
        points.append(point)
        pointCount = points.count
        lastPoint = point
        journal?.append(point)
        // On screen the numbers follow closely; in a pocket, often enough for the lock screen.
        if Date().timeIntervalSince(lastRefresh) >= (appIsActive ? 8 : 30) { refresh() }
    }

    // MARK: CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard state == .recording else { return }
        for fix in locations { add(fix) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if startWhenAllowed && canRecord {
            startWhenAllowed = false
            start()
        } else if denied {
            startWhenAllowed = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Without a fix for a moment (a tunnel, the gondola station): it goes on by itself.
    }
}

/// The points of the day under way, one JSON per line in Documents/Registrazione: written as
/// they come, read back if the app is started again before the day is saved.
final class Journal {
    private let file: URL
    private var handle: FileHandle?
    private let encoder = JSONEncoder()

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Registrazione", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        file = base.appendingPathComponent("punti.jsonl")
    }

    func begin() {
        try? handle?.close()
        FileManager.default.createFile(atPath: file.path, contents: nil)
        handle = try? FileHandle(forWritingTo: file)
    }

    func reopen() {
        handle = try? FileHandle(forWritingTo: file)
        _ = try? handle?.seekToEnd()
    }

    func append(_ point: TrackPoint) {
        guard let handle, var data = try? encoder.encode(point) else { return }
        data.append(0x0A)
        try? handle.write(contentsOf: data)
    }

    func load() -> [TrackPoint]? {
        guard let data = try? Data(contentsOf: file), !data.isEmpty else { return nil }
        let decoder = JSONDecoder()
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(TrackPoint.self, from: Data($0)) }
    }

    func finish() {
        try? handle?.close()
        handle = nil
        try? FileManager.default.removeItem(at: file)
    }
}
