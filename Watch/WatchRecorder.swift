import CoreLocation
import CoreMotion
import Foundation
import HealthKit
import Observation

/// Numbers as the watch writes them: in the units of the iPhone once it said them, in the ones
/// of the region before.
enum WatchFmt {
    static let metricKey = "metric"

    static var metric: Bool {
        UserDefaults.standard.object(forKey: metricKey) as? Bool ?? (Locale.current.measurementSystem != .us)
    }

    static func speedValue(_ ms: Double) -> String { "\(Int((max(0, ms) * (metric ? 3.6 : 2.236_94)).rounded()))" }
    static var speedUnit: String { metric ? "km/h" : "mph" }
    static func speed(_ ms: Double) -> String { "\(speedValue(ms)) \(speedUnit)" }
    static func height(_ m: Double) -> String { metric ? "\(Int(m.rounded())) m" : "\(Int((m * 3.280_84).rounded())) ft" }

    static func distance(_ m: Double) -> String {
        if metric {
            return m < 1000 ? "\(Int(m.rounded())) m" : String(format: "%.1f km", m / 1000)
        }
        return String(format: "%.1f mi", m / 1609.344)
    }
}

/// Records a day on the Apple Watch alone: the GPS of the watch about once a second and its
/// barometer for the altitude, as the iPhone does. A workout session keeps the app running with
/// the wrist down, reads the heart rate and saves the workout in Health. Every point is written to
/// a file as it comes, so that a day is found again if the app is closed. When the day ends its
/// points wait in a folder to be sent to the iPhone, which keeps the day.
@Observable final class WatchRecorder: NSObject, CLLocationManagerDelegate, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    enum State { case idle, recording, paused }

    /// The one recorder of the watch app: the screens, the iPhone's orders and the system use it.
    static let shared = WatchRecorder()

    private(set) var state: State = .idle
    private(set) var startDate: Date?
    private(set) var analysis = Segmenter.Result.empty
    private(set) var lastPoint: TrackPoint?
    /// Beats a minute, from the workout session.
    private(set) var heart: Double?
    /// A few words about the last thing done: shown until the next one.
    private(set) var note: String?

    /// Gets the file of a day that ended, to send it to the iPhone.
    @ObservationIgnored var deliver: ((URL) -> Void)?

    @ObservationIgnored private var points: [TrackPoint] = []
    private let manager = CLLocationManager()
    private let altimeter = CMAltimeter()
    private let health = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var route: HKWorkoutRouteBuilder?
    @ObservationIgnored private var baro: Double?
    @ObservationIgnored private var offset: Double?
    @ObservationIgnored private var gpsAlt: Double?
    @ObservationIgnored private var lastRefresh = Date.distantPast
    @ObservationIgnored private var startWhenAllowed = false
    @ObservationIgnored private var journal: FileHandle?
    private let encoder = JSONEncoder()

    /// The watch app may go on getting the location with the wrist down: it says so in its
    /// Info.plist. Asked for only then, since asking without it stops the app.
    private static let backgroundLocation =
        (Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])?.contains("location") == true

    private static var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private static var journalFile: URL { documents.appendingPathComponent("punti.jsonl") }

    /// The days that ended, each in a file, until the iPhone has them. The name ends with 1 when
    /// the workout is in Health already.
    static var outbox: URL {
        let folder = documents.appendingPathComponent("Outbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        // A day left from before, when the app was closed in the middle of it: found again, paused.
        if let data = try? Data(contentsOf: Self.journalFile), !data.isEmpty {
            let decoder = JSONDecoder()
            let saved = data.split(separator: 0x0A).compactMap { try? decoder.decode(TrackPoint.self, from: Data($0)) }
            if !saved.isEmpty {
                points = saved
                startDate = saved.first?.t
                lastPoint = saved.last
                state = .paused
                journal = try? FileHandle(forWritingTo: Self.journalFile)
                _ = try? journal?.seekToEnd()
                refresh()
            }
        }
    }

    /// The day under way as the screens of the watch show it.
    var watchState: WatchState {
        let stats = analysis.stats
        var speed = 0.0
        if state == .recording, let point = lastPoint, point.speed >= 0, Date().timeIntervalSince(point.t) < 15 { speed = point.speed }
        return WatchState(state: state == .paused ? "paused" : "recording",
                          phase: state == .paused ? "paused" : analysis.current.rawValue,
                          start: startDate, speed: WatchFmt.speedValue(speed), speedUnit: WatchFmt.speedUnit, runs: stats.runs,
                          vertical: WatchFmt.height(stats.vertical), distance: WatchFmt.distance(stats.runDistance),
                          maxSpeed: WatchFmt.speed(stats.maxSpeed), altitude: lastPoint.map { WatchFmt.height($0.alt) } ?? "–",
                          heart: heart.map { "\(Int($0.rounded()))" })
    }

    // MARK: What the buttons do

    func handle(_ command: WatchCommand) {
        switch command {
        case .start: start()
        case .pause: pause()
        case .resume: resume()
        case .finish: finish()
        }
    }

    func start() {
        guard state == .idle else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            startWhenAllowed = true
            manager.requestWhenInUseAuthorization()
            return
        case .authorizedWhenInUse, .authorizedAlways:
            break
        default:
            note = String(localized: "Consenti la posizione a Ski Apex nelle Impostazioni del Watch.")
            return
        }
        points = []
        lastPoint = nil
        analysis = .empty
        heart = nil
        note = nil
        startDate = Date()
        FileManager.default.createFile(atPath: Self.journalFile.path, contents: nil)
        journal = try? FileHandle(forWritingTo: Self.journalFile)
        resume()
    }

    func resume() {
        guard state != .recording else { return }
        state = .recording
        note = nil
        if Self.backgroundLocation { manager.allowsBackgroundLocationUpdates = true }
        manager.startUpdatingLocation()
        startBarometer()
        Task { @MainActor in await self.beginWorkout() }
    }

    func pause() {
        guard state == .recording else { return }
        state = .paused
        stopSensors()
        session?.pause()
        refresh()
    }

    /// Ends the day: its points go to the folder of the days for the iPhone.
    func finish() {
        guard state != .idle else { return }
        stopSensors()
        let inHealth = session != nil
        endWorkout()
        try? journal?.close()
        journal = nil
        let count = Segmenter.clean(points).count
        state = .idle
        points = []
        lastPoint = nil
        startDate = nil
        analysis = .empty
        heart = nil
        guard count >= 10 else {
            try? FileManager.default.removeItem(at: Self.journalFile)
            note = String(localized: "Troppo pochi punti GPS: niente da salvare.")
            return
        }
        let file = Self.outbox.appendingPathComponent("\(UUID().uuidString)_\(inHealth ? 1 : 0).jsonl")
        do {
            try FileManager.default.moveItem(at: Self.journalFile, to: file)
            deliver?(file)
            note = String(localized: "Giornata finita: la trovi sull'iPhone appena è vicino.")
        } catch {
            note = String(localized: "Non riesco a salvare la giornata.")
        }
    }

    // MARK: The workout

    /// The workout session: started with the day, paused and resumed with it. Without Health
    /// (not allowed, or not there) the day is recorded all the same, while the app is on screen.
    @MainActor private func beginWorkout() async {
        if let session {
            session.resume()
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await health.requestAuthorization(toShare: [HKObjectType.workoutType(), HKSeriesType.workoutRoute()],
                                                  read: [HKQuantityType(.heartRate)])
            // Asked while the day went on: it may have paused or ended in the meantime.
            guard state != .idle, session == nil else { return }
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .downhillSkiing
            configuration.locationType = .outdoor
            let made = try HKWorkoutSession(healthStore: health, configuration: configuration)
            let live = made.associatedWorkoutBuilder()
            live.dataSource = HKLiveWorkoutDataSource(healthStore: health, workoutConfiguration: configuration)
            live.delegate = self
            made.delegate = self
            let begin = startDate ?? Date()
            made.startActivity(with: begin)
            try await live.beginCollection(at: begin)
            session = made
            builder = live
            route = live.seriesBuilder(for: .workoutRoute()) as? HKWorkoutRouteBuilder
            if state == .paused { made.pause() }
        } catch {
            // No workout: nothing else changes.
        }
    }

    private func endWorkout() {
        guard let session, let builder else { return }
        self.session = nil
        self.builder = nil
        route = nil
        let end = Date()
        session.end()
        Task {
            try? await builder.endCollection(at: end)
            _ = try? await builder.finishWorkout()
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {}

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let type = HKQuantityType(.heartRate)
        guard collectedTypes.contains(type),
              let beats = workoutBuilder.statistics(for: type)?.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) else { return }
        DispatchQueue.main.async { self.heart = beats }
    }

    // MARK: Sensors

    private func startBarometer() {
        baro = nil
        offset = nil
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            self.baro = data.relativeAltitude.doubleValue
        }
    }

    private func stopSensors() {
        manager.stopUpdatingLocation()
        if Self.backgroundLocation { manager.allowsBackgroundLocationUpdates = false }
        altimeter.stopRelativeAltitudeUpdates()
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
        guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 50 else { return }
        if let last = points.last, fix.timestamp <= last.t { return }
        let point = TrackPoint(t: fix.timestamp, lat: fix.coordinate.latitude, lon: fix.coordinate.longitude,
                               alt: altitude(of: fix), speed: fix.speed, hAcc: fix.horizontalAccuracy, sAcc: fix.speedAccuracy)
        points.append(point)
        lastPoint = point
        if let journal, var data = try? encoder.encode(point) {
            data.append(0x0A)
            try? journal.write(contentsOf: data)
        }
        route?.insertRouteData([fix]) { _, _ in }
        // The numbers are worked out every quarter of a minute: the watch is a small computer.
        if Date().timeIntervalSince(lastRefresh) >= 15 { refresh() }
    }

    private func refresh() {
        lastRefresh = Date()
        analysis = Segmenter.analyze(Segmenter.clean(points))
    }

    // MARK: CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard state == .recording else { return }
        for fix in locations { add(fix) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard startWhenAllowed, status != .notDetermined else { return }
        startWhenAllowed = false
        start()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Without a fix for a moment: it goes on by itself.
    }
}
