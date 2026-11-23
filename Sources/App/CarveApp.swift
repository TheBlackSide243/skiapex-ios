import SwiftUI

@main
struct CarveApp: App {
    @Environment(\.scenePhase) private var phase
    @State private var library: Library
    @State private var recorder: Recorder

    init() {
        Theme.dressBars()
        if Demo.isOn {
            _library = State(initialValue: Demo.library())
            _recorder = State(initialValue: Demo.recorder())
        } else {
            _library = State(initialValue: Library())
            _recorder = State(initialValue: Recorder())
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(recorder)
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
}

/// Launched with `-demo`: made-up days and a day under way, for the screenshots.
enum Demo {
    static let isOn = ProcessInfo.processInfo.arguments.contains("-demo")

    static func library() -> Library {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("carve-demo", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        let library = Library(directory: dir)
        let places = ["Breuil-Cervinia", "Courmayeur", "Livigno"]
        for (i, place) in places.enumerated() {
            let start = Calendar.current.date(byAdding: .day, value: -(i * 9 + 2), to: Date())!
            let points = SkiSim.day(laps: 7 + i * 2, start: start, seed: UInt64(11 + i))
            try? library.save(SkiDay(points: points, place: place))
        }
        return library
    }

    static func recorder() -> Recorder {
        let points = SkiSim.day(laps: 4, start: Date(timeIntervalSinceNow: -2.5 * 3600), seed: 5)
        return Recorder.preview(Array(points.dropLast(420)))
    }
}
