import Observation
import SwiftUI
import WatchConnectivity

/// Ski Apex on the Apple Watch: the numbers of the day the iPhone is recording, and the buttons
/// to start it, pause it and end it without taking the iPhone out of the pocket.
@main
struct SkiApexWatchApp: App {
    @State private var phone = PhoneLink()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(phone)
                .tint(Ink.accent)
        }
    }
}

/// The colors of the app, on the black of the watch.
enum Ink {
    static let accent = Color(red: 0.361, green: 0.812, blue: 1.0)
    static let lift = Color(red: 0.769, green: 0.710, blue: 0.992)
    static let sub = Color(red: 0.596, green: 0.663, blue: 0.749)
    static let good = Color(red: 0.204, green: 0.827, blue: 0.600)
    static let bad = Color(red: 1.0, green: 0.482, blue: 0.541)

    static func tint(_ phase: String) -> Color {
        switch phase {
        case "run": accent
        case "lift": lift
        default: sub
        }
    }
}

/// The watch's side of the link with the iPhone: what it last said, and the commands to it.
@Observable final class PhoneLink: NSObject, WCSessionDelegate {
    private(set) var state = WatchState.idle
    /// A few words from the iPhone, or about it: shown until the next command.
    private(set) var note: String?
    /// A command was sent and the answer is awaited.
    private(set) var busy = false

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ command: WatchCommand) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            note = String(localized: "iPhone non raggiungibile. Avvicinalo e apri Ski Apex.")
            return
        }
        busy = true
        note = nil
        session.sendMessage([WatchLink.commandKey: command.rawValue], replyHandler: { answer in
            DispatchQueue.main.async {
                self.busy = false
                self.note = answer[WatchLink.noteKey] as? String
                if let state = WatchState(packed: answer) { self.state = state }
            }
        }, errorHandler: { _ in
            DispatchQueue.main.async {
                self.busy = false
                self.note = String(localized: "L'iPhone non ha risposto. Riprova.")
            }
        })
    }

    private func take(_ packed: [String: Any]) {
        guard let state = WatchState(packed: packed) else { return }
        DispatchQueue.main.async { self.state = state }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        take(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        take(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        take(message)
    }
}

struct WatchRootView: View {
    @Environment(PhoneLink.self) private var phone

    var body: some View {
        if phone.state.state == "idle" {
            ReadyView()
        } else {
            TabView {
                NowView()
                TotalsView()
                ControlsView()
            }
            .tabViewStyle(.verticalPage)
        }
    }
}

/// Before the day: one button.
struct ReadyView: View {
    @Environment(PhoneLink.self) private var phone

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: "figure.skiing.downhill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Ink.accent)
                Text("Pronto").font(.headline)
                Button {
                    phone.send(.start)
                } label: {
                    Label("Inizia", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(phone.busy)
                Text(phone.note ?? String(localized: "La giornata la registra l'iPhone: tienilo in tasca."))
                    .font(.caption2)
                    .foregroundStyle(phone.note == nil ? Ink.sub : Color.white)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private func phaseLabel(_ phase: String) -> LocalizedStringKey {
    switch phase {
    case "run": "In pista"
    case "lift": "In risalita"
    case "paused": "In pausa"
    default: "Fermo"
    }
}

private func phaseSymbol(_ phase: String) -> String {
    switch phase {
    case "run": "figure.skiing.downhill"
    case "lift": "cablecar"
    case "paused": "pause.fill"
    default: "mountain.2"
    }
}

/// What is happening now: skiing or on a lift, the speed, the clock of the day.
struct NowView: View {
    @Environment(PhoneLink.self) private var phone

    var body: some View {
        let state = phone.state
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(phaseLabel(state.phase))
            } icon: {
                Image(systemName: phaseSymbol(state.phase))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Ink.tint(state.phase))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(state.speed)
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(state.speedUnit).font(.caption2).foregroundStyle(Ink.sub)
            }
            HStack {
                if let start = state.start, state.state == "recording" {
                    Text(start, style: .timer).font(.footnote.monospacedDigit())
                }
                Spacer()
                Label(state.altitude, systemImage: "mountain.2").font(.caption2).foregroundStyle(Ink.sub)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

/// The numbers of the day so far.
struct TotalsView: View {
    @Environment(PhoneLink.self) private var phone

    var body: some View {
        let state = phone.state
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Total(value: "\(state.runs)", label: "Discese")
                Total(value: state.vertical, label: "Dislivello")
            }
            HStack(spacing: 8) {
                Total(value: state.distance, label: "Sciati")
                Total(value: state.maxSpeed, label: "Vel. max")
            }
        }
        .padding(.horizontal, 2)
    }
}

private struct Total: View {
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(.body, design: .rounded, weight: .semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.55)
            Text(label).font(.caption2).foregroundStyle(Ink.sub).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Pause and end, a swipe away so that a glove does not press them by mistake.
struct ControlsView: View {
    @Environment(PhoneLink.self) private var phone
    @State private var confirming = false

    var body: some View {
        let paused = phone.state.state == "paused"
        VStack(spacing: 8) {
            Button {
                phone.send(paused ? .resume : .pause)
            } label: {
                Label(LocalizedStringKey(paused ? "Riprendi" : "Pausa"), systemImage: paused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.bordered)
            Button {
                confirming = true
            } label: {
                Label("Fine", systemImage: "flag.checkered")
            }
            .buttonStyle(.bordered)
            .tint(Ink.bad)
            if let note = phone.note {
                Text(note).font(.caption2).foregroundStyle(Ink.sub).multilineTextAlignment(.center)
            }
        }
        .disabled(phone.busy)
        .confirmationDialog("Finita la giornata?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Salva la giornata") { phone.send(.finish) }
            Button("Annulla", role: .cancel) {}
        }
    }
}
