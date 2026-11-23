import AppIntents
import Foundation

/// The one recorder and the one library of the app: the screens and the Siri commands use the same.
enum Shared {
    static let library: Library = Demo.isOn ? Demo.library() : Library()
    static let recorder: Recorder = Demo.isOn ? Demo.recorder() : Recorder()
    static let guide = Guide(demo: Demo.isOn ? Demo.resorts : [])
    static let social = Social(demo: Demo.isOn)
}

/// The end of a day, from the Fine button or from a Siri command.
enum Session {
    /// Stops the recording and saves the day. nil when too little was recorded: then it is
    /// thrown away. If it cannot be saved the recording stays, paused, to try again.
    @MainActor static func finish() throws -> DaySummary? {
        let recorder = Shared.recorder
        let points = recorder.stop()
        guard points.count >= 10 else {
            recorder.forget()
            return nil
        }
        // The town, the names of the pistes and the weather come when the day is opened.
        let day = SkiDay(points: points, sport: Sport.current)
        do {
            try Shared.library.save(day)
        } catch {
            recorder.hold()
            throw error
        }
        recorder.forget()
        // Asked as soon as the app is looked at: how was the snow?
        Shared.library.ask(day.id)
        // The friends' leaderboard hears about the new day.
        Task { await Shared.social.refresh(season: Season(day.start), days: Shared.library.days) }
        if UserDefaults.standard.bool(forKey: Prefs.healthAuto) {
            Task { _ = try? await HealthSync.save(day.id) }
        }
        return day.summary
    }
}

struct StartDayIntent: AppIntent {
    static var title: LocalizedStringResource = "Inizia la giornata"
    static var description = IntentDescription("Avvia la registrazione della giornata sugli sci, o la riprende se è in pausa.")
    // The first time, iOS asks for the location on screen.
    static var openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let recorder = Shared.recorder
        switch recorder.state {
        case .recording:
            return .result(dialog: "La registrazione è già in corso.")
        case .paused:
            recorder.resume()
            return .result(dialog: "Registrazione ripresa.")
        case .idle:
            recorder.start()
            return .result(dialog: "Registrazione avviata. Buone discese!")
        }
    }
}

struct PauseDayIntent: AppIntent {
    static var title: LocalizedStringResource = "Metti in pausa la giornata"
    static var description = IntentDescription("Mette in pausa la registrazione in corso.")

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard Shared.recorder.state == .recording else {
            return .result(dialog: "Non c'è una registrazione in corso.")
        }
        Shared.recorder.pause()
        return .result(dialog: "Registrazione in pausa.")
    }
}

struct FinishDayIntent: AppIntent {
    static var title: LocalizedStringResource = "Finisci la giornata"
    static var description = IntentDescription("Ferma la registrazione e salva la giornata.")

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard Shared.recorder.state != .idle else {
            return .result(dialog: "Non c'è una registrazione in corso.")
        }
        guard let day = try Session.finish() else {
            return .result(dialog: "Troppo pochi punti GPS: non c'era niente da salvare.")
        }
        let text = String(localized: "Giornata salvata: \(day.stats.runs) discese, \(Fmt.height(day.stats.vertical)) di dislivello.")
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

struct SkiApexShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartDayIntent(),
                    phrases: ["Inizia la giornata con \(.applicationName)", "Avvia la registrazione con \(.applicationName)"],
                    shortTitle: "Inizia la giornata", systemImageName: "play.fill")
        AppShortcut(intent: PauseDayIntent(),
                    phrases: ["Metti in pausa \(.applicationName)"],
                    shortTitle: "Pausa", systemImageName: "pause.fill")
        AppShortcut(intent: FinishDayIntent(),
                    phrases: ["Finisci la giornata con \(.applicationName)", "Salva la giornata con \(.applicationName)"],
                    shortTitle: "Finisci la giornata", systemImageName: "flag.checkered")
    }
}
