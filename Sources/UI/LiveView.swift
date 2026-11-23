import MapKit
import SwiftUI
import UIKit

/// The day under way: the map with the tracks so far, and on glass the speed, the numbers and the
/// buttons. Before starting: where you are and the button to begin.
struct LiveView: View {
    @Environment(Recorder.self) private var recorder
    @Environment(Library.self) private var library
    @Environment(Social.self) private var social
    @Environment(\.openURL) private var openURL
    @AppStorage(Prefs.mapLook) private var mapLook = MapLook.standard.rawValue
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var confirmStop = false
    @State private var saving = false
    @State private var saved: DaySummary?
    @State private var error: String?

    private var look: MapLook { MapLook(rawValue: mapLook) ?? .standard }

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $camera) {
                    UserAnnotation()
                    TrackMapContent(tracks: recorder.tracks, colorful: false)
                    // The friends skiing now who share where they are.
                    ForEach(social.live) { friend in
                        Annotation(friend.name, coordinate: friend.coordinate) { FriendMarker(friend: friend) }
                    }
                }
                .mapStyle(look.style)
                .mapControls { MapCompass() }
                .ignoresSafeArea(edges: .top)

                VStack(spacing: 12) {
                    HStack(alignment: .top) {
                        statusPill
                        Spacer()
                        VStack(spacing: 10) {
                            MapButton(symbol: look == .standard ? "globe.europe.africa" : "map",
                                      label: look == .standard ? "Satellite" : "Mappa") {
                                mapLook = (look == .standard ? MapLook.satellite : MapLook.standard).rawValue
                            }
                            MapButton(symbol: "location.fill", label: "Dove sono") {
                                withAnimation { camera = .userLocation(fallback: .automatic) }
                            }
                        }
                    }
                    Spacer()
                    ErrorBanner(error: $error)
                    panel
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $saved) { DayDetailView(id: $0.id) }
            // While a day is recorded, the friends on the map are asked for every half minute.
            .task(id: recorder.state == .recording) {
                guard recorder.state == .recording else { return }
                while !Task.isCancelled {
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

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor).frame(width: 9, height: 9)
            Text(LocalizedStringKey(statusText)).font(.caption.weight(.semibold)).foregroundStyle(Theme.text)
            if let fix = recorder.lastFix, recorder.state == .recording {
                Text("±\(Int(fix.horizontalAccuracy.rounded())) m").font(.caption2).foregroundStyle(Theme.sub)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glass(in: Capsule())
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

    @ViewBuilder private var panel: some View {
        VStack(spacing: 16) {
            if recorder.state == .idle {
                startPanel
            } else {
                livePanel
            }
        }
        .padding(18)
        .glass()
    }

    @ViewBuilder private var startPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SKI APEX").font(.display(.largeTitle)).tracking(-0.5).foregroundStyle(Theme.accent)
            Text(recorder.denied
                 ? LocalizedStringKey("Per registrare serve la posizione: permettila in Impostazioni → Ski Apex → Posizione.")
                 : LocalizedStringKey("Premi Inizia ai piedi della pista, metti l'iPhone in tasca e scia: discese e risalite le riconosce da sola."))
                .prose().font(.subheadline).foregroundStyle(Theme.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if recorder.denied {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: { Label("Apri Impostazioni", systemImage: "gear") }
                .buttonStyle(PrimaryButtonStyle())
        } else {
            Button {
                recorder.start()
            } label: { Label("Inizia la giornata", systemImage: "play.fill") }
                .buttonStyle(PrimaryButtonStyle())
                .sensoryFeedback(.start, trigger: recorder.state == .recording)
        }
    }

    @ViewBuilder private var livePanel: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text(currentSpeed)
                    .font(.system(size: 64, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: currentSpeed)
                Text(Fmt.speedUnit).font(.caption.weight(.semibold)).foregroundStyle(Theme.sub)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(Fmt.clock(elapsed)).font(.display(.title3)).monospacedDigit().foregroundStyle(Theme.text)
                }
                if let alt = recorder.lastPoint?.alt {
                    Label(Fmt.height(alt), systemImage: "mountain.2").font(.caption).foregroundStyle(Theme.sub)
                }
            }
        }
        let s = recorder.analysis.stats
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            LiveCell(value: "\(s.runs)", label: "Discese")
            LiveCell(value: Fmt.height(s.vertical), label: "Dislivello")
            LiveCell(value: Fmt.speedValue(s.maxSpeed), label: "Max \(Fmt.speedUnit)")
            LiveCell(value: Fmt.distance(s.runDistance), label: "Sciati")
            LiveCell(value: "\(s.lifts)", label: "Risalite")
            LiveCell(value: Fmt.height(s.topAlt), label: "Quota max")
        }
        HStack(spacing: 12) {
            if recorder.state == .recording {
                Button { recorder.pause() } label: { Label("Pausa", systemImage: "pause.fill") }
                    .buttonStyle(SecondaryButtonStyle())
            } else {
                Button { recorder.resume() } label: { Label("Riprendi", systemImage: "play.fill") }
                    .buttonStyle(PrimaryButtonStyle())
            }
            Button { confirmStop = true } label: {
                if saving { ProgressView() } else { Label("Fine", systemImage: "flag.checkered") }
            }
            .buttonStyle(SecondaryButtonStyle(color: Theme.bad))
            .disabled(saving)
        }
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

private struct LiveCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.display(.headline)).monospacedDigit().foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(LocalizedStringKey(label)).font(.caption2).foregroundStyle(Theme.sub).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Theme.deep.opacity(0.55), in: Theme.roundSmall)
        .accessibilityElement(children: .combine)
    }
}
