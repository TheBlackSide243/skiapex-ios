import SwiftUI
import UIKit

/// The app is used upright, in a pocket and on a lift. App Store Connect wants every orientation
/// declared in Info.plist, so the limit is set here.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .portrait
    }
}

@main
struct SkiApexApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var phase
    @State private var library: Library
    @State private var recorder: Recorder

    init() {
        Theme.dressBars()
        _library = State(initialValue: Shared.library)
        _recorder = State(initialValue: Shared.recorder)
        // A day on the lock screen left from a recording that is no more.
        if Shared.recorder.state == .idle { LiveStatus.end() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(recorder)
                .environment(Shared.guide)
                .environment(Shared.social)
                .onOpenURL { url in
                    // skiapex://friend/<code>: an invitation, from the page of its link.
                    if url.scheme == "skiapex", url.host == "friend", let code = url.pathComponents.last, code.count == 8 {
                        Shared.social.pendingCode = code.uppercased()
                    }
                }
                .onChange(of: phase) { _, now in
                    recorder.setActive(now == .active)
                }
                .modifier(Dressed())
        }
    }
}

/// Settings stored with @AppStorage.
enum Prefs {
    /// `Units.rawValue`.
    static let units = "units"
    /// `MapLook.rawValue`.
    static let mapLook = "mapLook"
    /// `Sport.rawValue`: what new days are saved as.
    static let sport = "sport"
    /// Ask OpenStreetMap and Open-Meteo for the names of the pistes and the weather. On unless set off.
    static let online = "online"
    /// Save every day in Apple Health as it ends. Off unless set on.
    static let healthAuto = "healthAuto"
}

/// Launched with `-demo`: made-up days and a day under way, for the screenshots. `-screen <name>`
/// opens one screen: ready, live, days, day, timeline, run, replay, share, manual, stats, heat,
/// guide, friends, settings, empty.
enum Demo {
    static let isOn = ProcessInfo.processInfo.arguments.contains("-demo")

    static let screen: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard isOn, let i = args.firstIndex(of: "-screen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()

    /// The tab the screen asked for is in.
    static var tab: Int {
        switch screen {
        case "days", "day", "timeline", "run", "replay", "share", "manual", "stats", "heat", "empty": 1
        case "guide": 2
        case "friends": 3
        case "settings": 4
        default: 0
        }
    }

    static func library() -> Library {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("skiapex-demo", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        let library = Library(directory: dir)
        if screen == "empty" { return library }
        let places = ["Breuil-Cervinia", "Courmayeur", "Livigno"]
        for (i, place) in places.enumerated() {
            let morning = Calendar.current.date(bySettingHour: 9, minute: 5, second: 0, of: Date()) ?? Date()
            let start = Calendar.current.date(byAdding: .day, value: -(i * 9 + 2), to: morning) ?? morning
            let points = SkiSim.day(laps: 7 + i * 2, start: start, seed: UInt64(11 + i))
            var day = SkiDay(points: points, place: place, sport: i == 1 ? .snowboard : .ski)
            name(&day)
            day.weather = DayWeather(tempMin: -8 + Double(i), tempMax: -2 + Double(i), snowfall: i == 0 ? 12 : 0,
                                     windMax: 14 + Double(i * 9), code: i == 0 ? 71 : i == 1 ? 0 : 2)
            day.mapped = true
            try? library.save(day)
        }
        // A day written by hand, a trip planned and a ski area kept.
        let before = Calendar.current.date(byAdding: .day, value: -40, to: Date()) ?? Date()
        try? library.save(SkiDay(manual: before, duration: 5 * 3600, place: "Madesimo", sport: .ski, runs: 12, vertical: 4300,
                                 distance: 21_000, maxSpeed: 0))
        let soon = Calendar.current.date(byAdding: .day, value: 5, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        library.saveTrip(Trip(name: resorts[0].name, start: soon, end: soon.addingTimeInterval(3 * 86_400), resort: resorts[0]))
        if !library.isFavorite(resorts[1]) { library.toggleFavorite(resorts[1]) }
        return library
    }

    /// Ski areas for the pictures of the guide: real places, made-up snow.
    static let resorts = [
        Resort(id: "demo1", name: "Breuil-Cervinia", region: "Valle d'Aosta, Italia", lat: 45.9336, lon: 7.6295),
        Resort(id: "demo2", name: "Livigno", region: "Lombardia, Italia", lat: 46.5386, lon: 10.1357),
        Resort(id: "demo3", name: "Courmayeur", region: "Valle d'Aosta, Italia", lat: 45.7969, lon: 6.9689),
    ]

    /// Made-up names for the pistes and the lift, as OpenStreetMap would give them.
    private static func name(_ day: inout SkiDay) {
        let pistes = [("Pista del Sole", "easy"), ("Gran Bosco", "intermediate"), ("Canalone", "advanced")]
        for i in day.segments.indices {
            switch day.segments[i].kind {
            case .run:
                let piste = pistes[(day.segments[i].number - 1) % pistes.count]
                day.segments[i].name = piste.0
                day.segments[i].difficulty = piste.1
            case .lift:
                day.segments[i].name = "Seggiovia Cima Bianca"
            case .idle:
                break
            }
        }
    }

    /// A day under way, stopped in the middle of its last run as if it were now; nothing yet for
    /// the screen before starting.
    static func recorder() -> Recorder {
        if screen == "ready" { return Recorder(journal: nil) }
        let points = Segmenter.clean(SkiSim.day(laps: 4, start: Date(timeIntervalSinceNow: -3 * 3600), seed: 5))
        let runs = Segmenter.analyze(points).segments.filter { $0.kind == .run }
        guard let last = runs.last else { return Recorder.preview(points) }
        let cut = last.start + (last.end - last.start) * 6 / 10
        let shift = Date().timeIntervalSince(points[cut].t)
        return Recorder.preview(points[...cut].map { p in
            var q = p
            q.t = p.t.addingTimeInterval(shift)
            return q
        })
    }
}
