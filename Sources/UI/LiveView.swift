import MapKit
import SwiftUI
import UIKit

/// The day under way, on the sheet over the map: the speed, the numbers and the buttons. Before
/// starting: what you ride today and the button to begin. The map with the track is behind (see
/// `Backdrop`).
struct LiveView: View {
    @Environment(Recorder.self) private var recorder
    @Environment(Library.self) private var library
    @Environment(Social.self) private var social
    @Environment(\.openURL) private var openURL
    @AppStorage(Prefs.sport) private var sport = Sport.ski.rawValue
    @State private var confirmStop = false
    @State private var saving = false
    @State private var saved: DaySummary?
    @State private var error: String?
    /// The pistes and the lifts around, to say which one is under the skis.
    @State private var around: Terrain?
    @State private var passing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ErrorBanner(error: $error)
                    if recorder.handed {
                        handedPanel
                    } else if recorder.state == .idle {
                        startPanel
                    } else {
                        livePanel
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 26)
                .padding(.bottom, 20)
            }
            .screen()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $saved) { DayDetailView(id: $0.id) }
            // While a day is recorded, the friends on the map are asked for every half minute.
            .task(id: recorder.state == .recording) {
                guard recorder.state == .recording else { return }
                while !Task.isCancelled {
                    await loadAround()
                    await social.loadLive()
                    try? await Task.sleep(for: .seconds(30))
                }
            }
            .confirmationDialog("Finita la giornata?", isPresented: $confirmStop, titleVisibility: .visible) {
                Button("Salva la giornata") { Task { await save() } }
                Button("Scarta la registrazione", role: .destructive) { recorder.forget() }
                Button("Continua a sciare", role: .cancel) {}
            } message: {
                Text("Salvandola trovi discese, risalite e numeri in Giornate.")
            }
        }
    }

    // MARK: Pieces

    /// What is happening now, the piste under the skis and how good the position is.
    private var status: some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor).frame(width: 10, height: 10)
            Text(LocalizedStringKey(statusText)).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
            if let name = wayName {
                Text(name).font(.headline.weight(.regular)).foregroundStyle(Theme.sub).lineLimit(1)
            }
            Spacer(minLength: 6)
            if let alt = recorder.lastPoint?.alt {
                Label(Fmt.height(alt), systemImage: "mountain.2").font(.subheadline).foregroundStyle(Theme.sub).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        switch recorder.state {
        case .idle: return recorder.denied ? "Posizione non permessa" : "Pronto"
        case .paused: return recorder.recovered ? "Ripresa dopo la chiusura" : "In pausa"
        case .recording:
            switch recorder.analysis.current {
            case .run: return "In pista"
            case .lift: return "In risalita"
            case .idle: return "Fermo"
            }
        }
    }

    private var statusColor: Color {
        switch recorder.state {
        case .idle: return recorder.denied ? Theme.bad : Theme.sub
        case .paused: return Theme.warn
        case .recording:
            switch recorder.analysis.current {
            case .run: return Theme.accent
            case .lift: return Theme.lift
            case .idle: return Theme.good
            }
        }
    }

    /// The piste or the lift you are on, when the pistes around are known.
    private var wayName: String? {
        guard recorder.state == .recording, let around, let point = recorder.lastPoint else { return nil }
        return Self.way(at: point, doing: recorder.analysis.current, in: around)
    }

    /// The name of the piste (skiing) or of the lift (going up) closest to a point.
    static func way(at point: TrackPoint, doing kind: SegmentKind, in terrain: Terrain) -> String? {
        let wanted: OSMWay.Kind
        switch kind {
        case .run: wanted = .piste
        case .lift: wanted = .lift
        case .idle: return nil
        }
        guard let i = terrain.nearest(lat: point.lat, lon: point.lon, within: wanted == .piste ? 45 : 70, where: { $0.kind == wanted && $0.label != nil }) else { return nil }
        return terrain.ways[i].label
    }

    /// The pistes around the day under way: the ones downloaded, or asked once to OpenStreetMap
    /// when the internet is allowed.
    private func loadAround() async {
        guard around == nil, !Demo.isOn, let point = recorder.lastPoint else { return }
        if let kept = Terrains.shared.known(lat: point.lat, lon: point.lon) {
            around = kept
        } else if UserDefaults.standard.object(forKey: Prefs.online) as? Bool ?? true {
            around = try? await Terrains.shared.terrain(lat: point.lat, lon: point.lon)
        }
    }

    @ViewBuilder private var startPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Registra").font(.largeTitle.weight(.heavy)).foregroundStyle(Theme.text)
            Text(recorder.denied
                 ? LocalizedStringKey("Per registrare serve la posizione: permettila in Impostazioni → Ski Apex → Posizione.")
                 : LocalizedStringKey("Premi Inizia ai piedi della pista, metti l'iPhone in tasca e scia: discese e risalite le riconosce da sola."))
                .font(.subheadline).foregroundStyle(Theme.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if recorder.denied {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: { Label("Apri Impostazioni", systemImage: "gear") }
                .buttonStyle(PrimaryButtonStyle())
        } else {
            sportPicker
            Button {
                recorder.start()
            } label: { Label("Inizia la giornata", systemImage: "play.fill") }
                .buttonStyle(PrimaryButtonStyle())
                .sensoryFeedback(.start, trigger: recorder.state == .recording)
            if WatchBridge.shared.watchReady { watchButton("Registra con l'Apple Watch") }
        }
    }

    /// What is on the feet today: the day is saved as this.
    private var sportPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cosa fai oggi?").font(.headline).foregroundStyle(Theme.text)
            // All of them in sight, on as many lines as it takes: none is found by scrolling.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(Sport.allCases) { one in
                    Button { sport = one.rawValue } label: {
                        ChoicePill(title: one.label, symbol: one.symbol, on: sport == one.rawValue, wide: true)
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .sensoryFeedback(.selection, trigger: sport)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The day passes to the watch: the iPhone can be put away.
    private func watchButton(_ title: String) -> some View {
        Button {
            passing = true
            Task {
                if let note = await WatchBridge.shared.handOff() { error = note }
                passing = false
            }
        } label: {
            if passing { ProgressView() } else { Label(LocalizedStringKey(title), systemImage: "applewatch") }
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(passing)
    }

    /// The day went on to the watch: what to do now, and the way back.
    @ViewBuilder private var handedPanel: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "applewatch.radiowaves.left.and.right").font(.title2.weight(.semibold)).foregroundStyle(Theme.accent)
                .frame(width: 52, height: 52)
                .iconBox()
            VStack(alignment: .leading, spacing: 5) {
                Text("La giornata continua sul Watch").font(.title3.weight(.heavy)).foregroundStyle(Theme.text)
                Text("Puoi mettere via l'iPhone. A fine giornata premi Fine sul Watch e apri Ski Apex qui: la giornata arriva da sola, con quello che avevi già registrato.")
                    .font(.subheadline).foregroundStyle(Theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Button { recorder.takeBack() } label: { Label("Torna a registrare con l'iPhone", systemImage: "iphone") }
            .buttonStyle(SecondaryButtonStyle())
    }

    @ViewBuilder private var livePanel: some View {
        status
        HStack(alignment: .lastTextBaseline) {
            FigureText("\(currentSpeed) \(Fmt.speedUnit)", big: .system(size: 84, weight: .heavy), small: .system(size: 18, weight: .bold))
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText())
                .animation(.snappy, value: currentSpeed)
                .lineLimit(1).minimumScaleFactor(0.6)
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(Fmt.clock(elapsed)).font(.title2.weight(.bold)).monospacedDigit().foregroundStyle(Theme.text)
                }
                Text("dall'inizio").font(.subheadline).foregroundStyle(Theme.sub)
            }
        }
        let s = recorder.analysis.stats
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), alignment: .leading, spacing: 18) {
            LiveCell(value: "\(s.runs)", label: "discese", symbol: "arrow.triangle.2.circlepath")
            LiveCell(value: Fmt.height(s.vertical), label: "dislivello", symbol: "arrow.down")
            LiveCell(value: Fmt.speed(s.maxSpeed), label: "vel. max", symbol: "speedometer")
            LiveCell(value: Fmt.distance(s.runDistance), label: "sciati", symbol: "arrow.right")
            LiveCell(value: "\(s.lifts)", label: "risalite", symbol: "cablecar")
            LiveCell(value: Fmt.height(s.topAlt), label: "quota max", symbol: "mountain.2")
        }
        HStack(spacing: 10) {
            if recorder.state == .recording {
                Button { recorder.pause() } label: { Label("Pausa", systemImage: "pause.fill") }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Button { recorder.resume() } label: { Label("Riprendi", systemImage: "play.fill") }
                    .buttonStyle(PrimaryButtonStyle())
            }
            Button { confirmStop = true } label: {
                if saving { ProgressView() } else { Text("Fine") }
            }
            .buttonStyle(SecondaryButtonStyle(color: Theme.bad))
            .frame(maxWidth: 120)
            .disabled(saving)
        }
        if WatchBridge.shared.watchReady { watchButton("Continua sul Watch") }
    }

    private var currentSpeed: String {
        guard recorder.state == .recording, let p = recorder.lastPoint, p.speed >= 0,
              Demo.isOn || Date().timeIntervalSince(p.t) < 10 else { return "0" }
        return Fmt.speedValue(p.speed)
    }

    private var elapsed: TimeInterval {
        guard let start = recorder.startDate else { return 0 }
        return Date().timeIntervalSince(start)
    }

    // MARK: Saving

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            if let day = try Session.finish() {
                saved = day
            } else {
                error = String(localized: "Troppo pochi punti GPS: non c'è niente da salvare.")
            }
        } catch {
            // The points stay: the day can be saved again from the paused recording.
            self.error = String(localized: "Non sono riuscito a salvare la giornata: \(error.localizedDescription)")
        }
    }
}

/// One of the six numbers of the day under way.
private struct LiveCell: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            FigureText(value, big: .system(.title3, design: .default, weight: .bold), small: .system(.caption, design: .default, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.caption2.weight(.bold)).accessibilityHidden(true)
                Text(LocalizedStringKey(label)).font(.footnote)
            }
            .foregroundStyle(Theme.sub).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
