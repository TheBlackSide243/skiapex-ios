import CoreLocation
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(Recorder.self) private var recorder
    @Environment(Library.self) private var library
    @AppStorage(Prefs.units) private var units = Units.metric.rawValue
    @AppStorage(Prefs.mapLook) private var mapLook = MapLook.standard.rawValue
    @AppStorage(Prefs.sport) private var sport = Sport.ski.rawValue
    @AppStorage(Prefs.online) private var online = true
    @AppStorage(Prefs.healthAuto) private var healthAuto = false
    @State private var made = false
    @State private var backup: URL?
    @State private var restoring = false
    @State private var backupNote: String?
    @State private var error: String?

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Panel("Attività") {
                        Picker("Attività", selection: $sport) {
                            ForEach(Sport.allCases) { Text(LocalizedStringKey($0.label)).tag($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                        Text("Le nuove giornate vengono salvate così. Puoi cambiarlo per ogni giornata dal suo menu.")
                            .prose().font(.caption).foregroundStyle(Theme.sub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Panel("Unità") {
                        Picker("Unità", selection: $units) {
                            ForEach(Units.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                    }
                    Panel("Mappa") {
                        Picker("Mappa", selection: $mapLook) {
                            ForEach(MapLook.allCases) { Text(LocalizedStringKey($0.label)).tag($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                    }
                    Panel("Internet") {
                        Toggle(isOn: $online) {
                            Text("Nomi delle piste e meteo").font(.subheadline).foregroundStyle(Theme.text)
                        }
                        .tint(Theme.accent)
                        Text("Quando apri una giornata, Ski Apex chiede a OpenStreetMap i nomi delle piste e degli impianti della zona e a Open-Meteo il meteo di quel giorno. Viene inviata solo la zona della giornata, senza account e senza il tuo nome. Spento, non esce niente dall'iPhone.")
                            .prose().font(.caption).foregroundStyle(Theme.sub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if HealthSync.available {
                        Panel("Salute") {
                            Toggle(isOn: $healthAuto) {
                                Text("Salva le giornate in Salute").font(.subheadline).foregroundStyle(Theme.text)
                            }
                            .tint(Theme.accent)
                            Text("Ogni giornata finita viene salvata in Salute come allenamento di sci o snowboard, con il percorso, e se portavi un Apple Watch ne leggo il battito. Puoi farlo anche a mano dal menu di una giornata. Con l'app installata da Feather può non essere disponibile.")
                                .prose().font(.caption).foregroundStyle(Theme.sub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Panel("Copia di sicurezza") {
                        ErrorBanner(error: $error)
                        Text("Tutte le giornate in un file zip, da tenere su iCloud Drive o da portare su un altro iPhone. Ripristinando, le giornate che ci sono già non vengono toccate.")
                            .prose().font(.caption).foregroundStyle(Theme.sub)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            do {
                                backup = try library.exportBackup()
                                backupNote = nil
                            } catch {
                                self.error = error.localizedDescription
                            }
                        } label: { Label("Prepara la copia", systemImage: "archivebox") }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(library.days.isEmpty)
                        if let backup {
                            ShareLink(item: backup) { Label("Salva o invia la copia", systemImage: "square.and.arrow.up") }
                                .buttonStyle(PrimaryButtonStyle())
                        }
                        Button { restoring = true } label: { Label("Ripristina da una copia", systemImage: "arrow.down.doc") }
                            .buttonStyle(SecondaryButtonStyle())
                        if let backupNote {
                            Text(backupNote).font(.caption).foregroundStyle(Theme.good)
                        }
                    }
                    Panel("Sensori") {
                        InfoRow("Posizione", permission)
                        InfoRow("Barometro", recorder.hasBarometer ? String(localized: "Sì, per il dislivello") : String(localized: "No, quota dal GPS"))
                    }
                    Panel("Come funziona") {
                        Text("Ski Apex registra il GPS circa una volta al secondo, anche a schermo spento, e misura la quota con il barometro. Una discesa è quando scendi muovendoti per almeno \(Int(Segmenter.minRunDrop)) m di dislivello; una risalita quando sali di almeno \(Int(Segmenter.minLiftGain)) m. Le soste brevi in pista restano dentro la discesa.")
                            .prose().font(.subheadline).foregroundStyle(Theme.sub)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Consigli: carica l'iPhone prima di partire, con il freddo la batteria scende in fretta. Tienilo in una tasca interna. Le giornate restano solo su questo iPhone e le trovi anche nell'app File, nella cartella Ski Apex.")
                            .prose().font(.subheadline).foregroundStyle(Theme.sub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Panel("Prova") {
                        Text("Una giornata inventata, con risalite e discese, per vedere l'app senza andare sulla neve.")
                            .prose().font(.subheadline).foregroundStyle(Theme.sub)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            let laps = 6 + Int.random(in: 0...4)
                            let start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
                            var day = SkiDay(points: SkiSim.day(laps: laps, start: start, seed: UInt64.random(in: 1...1_000_000)),
                                             place: String(localized: "Giornata di prova"), sport: Sport.current)
                            // Made up: there is nothing to look for on the internet.
                            day.mapped = true
                            day.weather = DayWeather(tempMin: -6, tempMax: -1, snowfall: 8, windMax: 15, code: 71)
                            try? library.save(day)
                            made = true
                        } label: { Label("Crea una giornata di prova", systemImage: "wand.and.stars") }
                            .buttonStyle(SecondaryButtonStyle())
                            .sensoryFeedback(.success, trigger: made)
                        if made {
                            Text("Fatto: la trovi in Giornate.").font(.caption).foregroundStyle(Theme.good)
                        }
                    }
                    Panel("Informazioni") {
                        InfoRow("Versione", version)
                        InfoRow("Giornate salvate", "\(library.days.count)")
                        Text("Velocità, distanze e quote sono stime del GPS e del barometro: non usarle per la sicurezza.")
                            .prose().font(.caption).foregroundStyle(Theme.sub)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Nomi di piste e impianti: © i contributori di OpenStreetMap (ODbL). Meteo: Open-Meteo.com.")
                            .prose().font(.caption).foregroundStyle(Theme.sub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
            }
            .screen()
            .navigationTitle("Impostazioni")
            .fileImporter(isPresented: $restoring, allowedContentTypes: [.zip]) { result in
                do {
                    let added = try library.restore(from: try result.get())
                    backupNote = String(localized: "Giornate aggiunte: \(added).")
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    private var permission: String {
        switch recorder.authorization {
        case .authorizedAlways, .authorizedWhenInUse: String(localized: "Permessa")
        case .denied, .restricted: String(localized: "Non permessa")
        default: String(localized: "Da chiedere")
        }
    }
}
