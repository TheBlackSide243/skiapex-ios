import HealthKit
import Observation
import SwiftUI
import WatchConnectivity
import WatchKit

/// Ski Apex on the Apple Watch. It records a day by itself, with the GPS of the watch, and sends
/// it to the iPhone when it ends; or, when the iPhone is the one recording, it shows its numbers
/// and commands it: start, pause, end.
@main
struct SkiApexWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchDelegate.self) private var delegate
    @State private var phone = PhoneLink.shared
    @State private var recorder = WatchRecorder.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(phone)
                .environment(recorder)
                .tint(Ink.accent)
        }
    }
}

/// The iPhone can open the watch app for a workout ("Continua sul Watch"): the day starts here.
final class WatchDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        DispatchQueue.main.async {
            // The link first: it is what passes the day to the iPhone.
            _ = PhoneLink.shared
            WatchRecorder.shared.start()
        }
    }
}

/// The colors of the app, on the black of the watch.
enum Ink {
    /// The ice blue of the icon, as on the iPhone.
    static let accent = Color(red: 0.361, green: 0.812, blue: 1.0)
    static let lift = Color(red: 0.769, green: 0.710, blue: 0.992)
    /// The dot of the button that records, and the button that ends.
    static let record = Color(red: 0.949, green: 0.333, blue: 0.353)
    static let sub = Color(red: 0.635, green: 0.647, blue: 0.694)
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

/// The watch's side of the link with the iPhone: what it last said, the commands to it, and the
/// days recorded on the watch on their way to it.
@Observable final class PhoneLink: NSObject, WCSessionDelegate {
    static let shared = PhoneLink()

    private(set) var state = WatchState.idle
    /// A few words from the iPhone, or about it: shown until the next command.
    private(set) var note: String?
    /// A command was sent and the answer is awaited.
    private(set) var busy = false
    /// The iPhone is near and its app can be asked.
    private(set) var reachable = false
    /// The days recorded here that the iPhone does not have yet.
    private(set) var waiting = 0

    override init() {
        super.init()
        let recorder = WatchRecorder.shared
        recorder.deliver = { [weak self] file in self?.queue(file) }
        recorder.live = { [weak self] packet in self?.tell(packet) ?? false }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// The day under way here, for the iPhone to show: queued in order, it arrives when the
    /// iPhone is near, all of it.
    func tell(_ packet: [String: Any]) -> Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        guard session.activationState == .activated else { return false }
        session.transferUserInfo(packet)
        return true
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
                if let state = WatchState(packed: answer) { self.take(state) }
            }
        }, errorHandler: { _ in
            DispatchQueue.main.async {
                self.busy = false
                self.note = String(localized: "L'iPhone non ha risposto. Riprova.")
            }
        })
    }

    private func take(_ new: WatchState) {
        state = new
        // The units the iPhone writes in are the ones the watch uses when it records by itself.
        if new.state != "idle" { UserDefaults.standard.set(new.speedUnit == "km/h", forKey: WatchFmt.metricKey) }
        // And how often the GPS gives a point.
        if let every = new.every { UserDefaults.standard.set(GPSRate.near(every).rawValue, forKey: GPSRate.key) }
    }

    private func take(_ packed: [String: Any]) {
        // "Record": the iPhone passed the day to the watch. Only if it was just said.
        if packed[WatchLink.commandKey] as? String == WatchLink.record,
           let at = packed[WatchLink.atKey] as? Date, Date().timeIntervalSince(at) < 600 {
            DispatchQueue.main.async { WatchRecorder.shared.start() }
        }
        guard let state = WatchState(packed: packed) else { return }
        DispatchQueue.main.async { self.take(state) }
    }

    // MARK: The days recorded here

    /// Sends the file of a day to the iPhone: now if it is near, when it is otherwise.
    func queue(_ file: URL) {
        let session = WCSession.default
        if session.activationState == .activated { transfer(file, with: session) }
        count()
    }

    private func transfer(_ file: URL, with session: WCSession) {
        let name = file.deletingPathExtension().lastPathComponent
        let parts = name.split(separator: "_")
        let metadata: [String: Any] = [WatchLink.kindKey: "day", WatchLink.idKey: String(parts.first ?? ""),
                                       WatchLink.healthKey: parts.last == "1"]
        session.transferFile(file, metadata: metadata)
    }

    /// The days still in the folder that are not on their way: after the app was closed.
    private func resend(with session: WCSession) {
        let going = Set(session.outstandingFileTransfers.map { $0.file.fileURL.lastPathComponent })
        let files = (try? FileManager.default.contentsOfDirectory(at: WatchRecorder.outbox, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "jsonl" && !going.contains(file.lastPathComponent) {
            transfer(file, with: session)
        }
        count()
    }

    private func count() {
        let files = (try? FileManager.default.contentsOfDirectory(at: WatchRecorder.outbox, includingPropertiesForKeys: nil)) ?? []
        let left = files.filter { $0.pathExtension == "jsonl" }.count
        DispatchQueue.main.async { self.waiting = left }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        take(session.receivedApplicationContext)
        let near = session.isReachable
        DispatchQueue.main.async { self.reachable = near }
        if activationState == .activated { resend(with: session) }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let near = session.isReachable
        DispatchQueue.main.async { self.reachable = near }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        take(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        take(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        take(userInfo)
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        // Arrived: the iPhone has the day, the file can go. Otherwise it stays for the next try.
        if error == nil { try? FileManager.default.removeItem(at: fileTransfer.file.fileURL) }
        count()
    }
}

struct WatchRootView: View {
    @Environment(PhoneLink.self) private var phone
    @Environment(WatchRecorder.self) private var recorder

    var body: some View {
        Group {
            if recorder.state != .idle {
                // The watch is recording.
                DayPages(state: recorder.watchState, note: recorder.note, busy: false) { recorder.handle($0) }
            } else if phone.state.state != "idle" {
                // The iPhone is recording: its numbers, and its buttons.
                DayPages(state: phone.state, note: phone.note, busy: phone.busy) { phone.send($0) }
            } else {
                ReadyView()
            }
        }
        .fontDesign(.rounded)
    }
}

/// The button that records, as on the iPhone: white and round, with a red dot.
private struct RecordDot: View {
    var size: CGFloat = 62

    var body: some View {
        ZStack {
            Circle().fill(Color.white)
            Circle().fill(Ink.record).frame(width: size * 0.36, height: size * 0.36)
        }
        .frame(width: size, height: size)
    }
}

/// Before the day: start it here, or on the iPhone.
struct ReadyView: View {
    @Environment(PhoneLink.self) private var phone
    @Environment(WatchRecorder.self) private var recorder

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Button {
                    recorder.start()
                } label: {
                    VStack(spacing: 5) {
                        RecordDot()
                        Text("Inizia").font(.system(.headline, design: .rounded, weight: .heavy))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Inizia la giornata"))
                if phone.reachable {
                    Button {
                        phone.send(.start)
                    } label: {
                        Label("Con l'iPhone", systemImage: "iphone")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Ink.accent)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Ink.accent.opacity(0.18), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(phone.busy)
                }
                if let note = recorder.note ?? phone.note {
                    Text(note).font(.caption2).multilineTextAlignment(.center)
                } else {
                    Text("Il Watch registra da solo con il suo GPS: l'iPhone può restare in tasca.")
                        .font(.caption2).foregroundStyle(Ink.sub).multilineTextAlignment(.center)
                }
                if phone.waiting > 0 {
                    Label("Giornate in attesa dell'iPhone: \(phone.waiting)", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption2).foregroundStyle(Ink.sub)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// The day under way, a page for each thing: now, the totals, the buttons.
struct DayPages: View {
    let state: WatchState
    let note: String?
    let busy: Bool
    let send: (WatchCommand) -> Void

    var body: some View {
        TabView {
            NowView(state: state)
            TotalsView(state: state)
            ControlsView(state: state, note: note, busy: busy, send: send)
        }
        .tabViewStyle(.verticalPage)
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

/// What is happening now: skiing or on a lift, the speed, the clock of the day, and how much
/// was skied so far.
struct NowView: View {
    let state: WatchState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Label {
                    Text(phaseLabel(state.phase))
                } icon: {
                    Image(systemName: phaseSymbol(state.phase))
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(Ink.tint(state.phase))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Ink.tint(state.phase).opacity(0.2), in: Capsule())
                Spacer()
                if let heart = state.heart {
                    Label(heart, systemImage: "heart.fill").font(.caption2).foregroundStyle(Ink.bad)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(state.speed)
                    .font(.system(size: 58, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(state.speedUnit.uppercased()).font(.system(.caption2, design: .rounded, weight: .bold)).foregroundStyle(Ink.sub)
            }
            HStack(spacing: 6) {
                if let start = state.start, state.state == "recording" {
                    Text(start, style: .timer).font(.footnote.weight(.semibold).monospacedDigit())
                }
                Spacer()
                Image(systemName: "arrow.down.right").font(.caption2.weight(.bold)).foregroundStyle(Ink.accent)
                Text(UnitText.styled(state.vertical, big: .system(.footnote, design: .rounded, weight: .bold),
                                     small: .system(size: 9, weight: .bold, design: .rounded)))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

/// The numbers of the day so far: no boxes, the numbers bold with their units small beside them.
struct TotalsView: View {
    let state: WatchState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Total(value: "\(state.runs)", label: "Discese")
                Total(value: state.vertical, label: "Dislivello", color: Ink.accent)
            }
            HStack(spacing: 8) {
                Total(value: state.distance, label: "Sciati")
                Total(value: state.maxSpeed, label: "Vel. max")
            }
            HStack(spacing: 5) {
                Image(systemName: "mountain.2").font(.caption2.weight(.bold))
                Text(UnitText.styled(state.altitude, big: .system(.caption, design: .rounded, weight: .bold),
                                     small: .system(size: 9, weight: .bold, design: .rounded)))
            }
            .foregroundStyle(Ink.sub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }
}

private struct Total: View {
    let value: String
    let label: LocalizedStringKey
    var color = Color.white

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(UnitText.styled(value, big: .system(.title3, design: .rounded, weight: .bold),
                                 small: .system(size: 10, weight: .bold, design: .rounded)))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.55)
            Text(label).font(.caption2).foregroundStyle(Ink.sub).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Pause and end, a swipe away so that a glove does not press them by mistake: two round
/// buttons, the one that ends in red.
struct ControlsView: View {
    let state: WatchState
    let note: String?
    let busy: Bool
    let send: (WatchCommand) -> Void
    @State private var confirming = false

    var body: some View {
        let paused = state.state == "paused"
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                round(paused ? "play.fill" : "pause.fill", LocalizedStringKey(paused ? "Riprendi" : "Pausa"), fill: .white, ink: .black) {
                    send(paused ? .resume : .pause)
                }
                round("flag.checkered", "Fine", fill: Ink.record, ink: .white) {
                    confirming = true
                }
            }
            if let note {
                Text(note).font(.caption2).foregroundStyle(Ink.sub).multilineTextAlignment(.center)
            }
        }
        .disabled(busy)
        .confirmationDialog("Finita la giornata?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Salva la giornata") { send(.finish) }
            Button("Annulla", role: .cancel) {}
        }
    }

    private func round(_ symbol: String, _ title: LocalizedStringKey, fill: Color, ink: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ink)
                    .frame(width: 56, height: 56)
                    .background(fill, in: Circle())
                Text(title).font(.caption2.weight(.semibold))
            }
        }
        .buttonStyle(.plain)
    }
}
