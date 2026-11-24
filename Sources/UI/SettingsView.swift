import CoreLocation
import SwiftUI
import UniformTypeIdentifiers

/// The pages the settings open.
enum SettingsPage: String, Hashable {
    case profile, look, recording, integrations, maps, backup, help, news, privacy, credits
}

/// Settings: your profile at the top, then a short list of pages, each with its own things, and
/// what the app is at the bottom.
struct SettingsView: View {
    @Environment(Social.self) private var social
    @Environment(Library.self) private var library
    @State private var path: [SettingsPage] = SettingsView.demoPath

    /// For the pictures: `-screen looks` and `-screen profile` open a page.
    private static var demoPath: [SettingsPage] {
        switch Demo.screen {
        case "looks": [.look]
        case "profile": [.profile]
        default: []
        }
    }

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "v\(v) (\(b))"
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 14) {
                    profileCard
                    MenuGroup {
                        MenuRow(page: .look, symbol: "paintpalette.fill", color: Color(hex: 0x8b5cf6), title: "Aspetto",
                                detail: String(localized: String.LocalizationValue(Looks.shared.look.label)))
                        MenuRow(page: .recording, symbol: "slider.horizontal.3", color: Color(hex: 0x3b82f6), title: "Registrazione")
                        MenuRow(page: .integrations, symbol: "arrow.left.arrow.right", color: Color(hex: 0x6366f1), title: "Integrazioni")
                        MenuRow(page: .maps, symbol: "map.fill", color: Color(hex: 0x14b8a6), title: "Mappe scaricate")
                        MenuRow(page: .backup, symbol: "archivebox.fill", color: Color(hex: 0x22a55b), title: "Copia di sicurezza", last: true)
                    }
                    MenuGroup {
                        MenuRow(page: .help, symbol: "questionmark.bubble.fill", color: Color(hex: 0xef4444), title: "Aiuto e prova", last: true)
                    }
                    about
                    MenuGroup {
                        MenuRow(page: .news, symbol: "sparkles", color: Color(hex: 0xeab308), title: "Novità")
                        MenuRow(page: .privacy, symbol: "lock.shield.fill", color: Color(hex: 0x0ea5e9), title: "Ski Apex e i tuoi dati")
                        MenuRow(page: .credits, symbol: "hammer.fill", color: Color(hex: 0xf97316), title: "Riconoscimenti", last: true)
                    }
                    HStack(spacing: 10) {
                        ShareLink(item: Self.invite) { tile("Consiglia Ski Apex", symbol: "square.and.arrow.up") }
                            .buttonStyle(PressStyle())
                        Link(destination: Self.source) { tile("Pagina su GitHub", symbol: "link") }
                            .buttonStyle(PressStyle())
                    }
                }
                .padding(16)
            }
            .screen()
            .navigationTitle("Impostazioni")
            .navigationDestination(for: SettingsPage.self) { page in
                switch page {
                case .profile: ProfileView()
                case .look: LookPage()
                case .recording: RecordingPage()
                case .integrations: IntegrationsPage()
                case .maps: MapsPage()
                case .backup: BackupPage()
                case .help: HelpPage()
                case .news: NewsPage()
                case .privacy: PrivacyPage()
                case .credits: CreditsPage()
                }
            }
        }
    }

    static let invite = URL(string: "https://testflight.apple.com/join/Kszu8FAj")!
    static let source = URL(string: "https://github.com/TheBlackSide243/skiapex-ios")!

    /// Who you are for your friends, or the way to an account.
    private var profileCard: some View {
        NavigationLink(value: SettingsPage.profile) {
            HStack(spacing: 14) {
                if let account = social.account {
                    Avatar(id: account.id, name: account.name, photo: account.photo, size: 62)
                } else {
                    Image(systemName: "person.fill").font(.title2).foregroundStyle(Theme.accent)
                        .frame(width: 62, height: 62)
                        .background(Theme.deep, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(social.account?.name ?? String(localized: "Accedi o crea un account"))
                        .font(.display(.headline)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
                    Text(LocalizedStringKey(social.signedIn ? "Profilo, foto e account" : "Per le classifiche e gli amici in diretta"))
                        .font(.caption).foregroundStyle(Theme.sub).lineLimit(2)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.sub)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
        .buttonStyle(PressStyle())
    }

    /// What the app is, with its icon and its version.
    private var about: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(IconArt.previewInUse)
                    .resizable()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ski Apex").font(.display(.title3)).foregroundStyle(Theme.text)
                    Text(version).font(.subheadline).foregroundStyle(Theme.sub)
                }
            }
            Text("Il diario delle tue giornate sulla neve: registra discese e risalite da sola, e tiene tutto sul tuo iPhone. \(library.days.count) giornate salvate.")
                .prose().font(.subheadline).foregroundStyle(Theme.sub)
                .fixedSize(horizontal: false, vertical: true)
            Text("Niente pubblicità, niente abbonamenti, niente dati venduti.")
                .prose().font(.subheadline).foregroundStyle(Theme.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    private func tile(_ title: String, symbol: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.body.weight(.semibold))
            Text(LocalizedStringKey(title)).font(.caption.weight(.semibold)).multilineTextAlignment(.center)
        }
        .foregroundStyle(Theme.accent)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .card()
    }
}

/// A group of rows in one card.
struct MenuGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .card()
    }
}

/// One row of the settings: a colored tile with a symbol, a title, and the page it opens.
struct MenuRow: View {
    let page: SettingsPage
    let symbol: String
    let color: Color
    let title: String
    var detail: String?
    /// The last of its group: no line under it.
    var last = false

    var body: some View {
        NavigationLink(value: page) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityHidden(true)
                Text(LocalizedStringKey(title)).font(.body).foregroundStyle(Theme.text).lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 6)
                if let detail {
                    Text(detail).font(.subheadline).foregroundStyle(Theme.sub).lineLimit(1)
                }
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.sub)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The line under it starts where the words do.
            .overlay(alignment: .bottom) {
                if !last {
                    Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 48)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

/// A page of the settings: its panels one under the other.
private struct SettingsPageBody<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 14) { content }
                .padding(16)
        }
        .screen()
        .navigationTitle(LocalizedStringKey(title))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A sentence of a page, in the plain face.
private struct Words: View {
    let text: LocalizedStringKey
    var small = false

    init(_ text: LocalizedStringKey, small: Bool = false) {
        self.text = text
        self.small = small
    }

    var body: some View {
        Text(text).prose().font(small ? .caption : .subheadline).foregroundStyle(Theme.sub)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: The pages

private struct LookPage: View {
    var body: some View {
        SettingsPageBody(title: "Aspetto") { LookPanel() }
    }
}

/// What a recording is saved as and how its numbers are shown.
private struct RecordingPage: View {
    @Environment(Recorder.self) private var recorder
    @AppStorage(Prefs.units) private var units = Units.metric.rawValue
    @AppStorage(Prefs.mapLook) private var mapLook = MapLook.standard.rawValue
    @AppStorage(Prefs.sport) private var sport = Sport.ski.rawValue

    var body: some View {
        SettingsPageBody(title: "Registrazione") {
            Panel("Attività") {
                Picker("Attività", selection: $sport) {
                    ForEach(Sport.allCases) { Text(LocalizedStringKey($0.label)).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                Words("Le nuove giornate vengono salvate così. Puoi cambiarlo per ogni giornata dal suo menu.", small: true)
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
            Panel("Sensori") {
                InfoRow("Posizione", permission)
                InfoRow("Barometro", recorder.hasBarometer ? String(localized: "Sì, per il dislivello") : String(localized: "No, quota dal GPS"))
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

/// What Ski Apex talks to: the internet for names and weather, Apple Health, the Apple Watch.
private struct IntegrationsPage: View {
    @AppStorage(Prefs.online) private var online = true
    @AppStorage(Prefs.healthAuto) private var healthAuto = false

    var body: some View {
        SettingsPageBody(title: "Integrazioni") {
            Panel("Internet") {
                Toggle(isOn: $online) {
                    Text("Nomi delle piste e meteo").font(.subheadline).foregroundStyle(Theme.text)
                }
                .tint(Theme.accent)
                Words("Quando apri una giornata, Ski Apex chiede a OpenStreetMap i nomi delle piste e degli impianti della zona e a Open-Meteo il meteo di quel giorno. Viene inviata solo la zona della giornata, senza account e senza il tuo nome. Spento, non esce niente dall'iPhone.", small: true)
            }
            if HealthSync.available {
                Panel("Salute") {
                    Toggle(isOn: $healthAuto) {
                        Text("Salva le giornate in Salute").font(.subheadline).foregroundStyle(Theme.text)
                    }
                    .tint(Theme.accent)
                    Words("Ogni giornata finita viene salvata in Salute come allenamento di sci o snowboard, con il percorso, e se portavi un Apple Watch ne leggo il battito. Puoi farlo anche a mano dal menu di una giornata. Con l'app installata da Feather può non essere disponibile.", small: true)
                }
            }
            Panel("Apple Watch") {
                Words("Sul Watch, Ski Apex registra la giornata da sola con il GPS dell'orologio: l'iPhone può restare in tasca o a casa. Quando finisci, la giornata arriva qui in Giornate appena i due sono vicini.")
                Words("Se invece registri con l'iPhone, il Watch ne mostra i numeri e fa da telecomando: pausa, riprendi, fine. L'app per il Watch arriva con la versione TestFlight.", small: true)
            }
            Panel("Siri e widget") {
                Words("\"Inizia la giornata con Ski Apex\", \"Metti in pausa Ski Apex\", \"Finisci la giornata con Ski Apex\": li trovi anche nell'app Comandi Rapidi. I widget \"Registra\" e \"Neve in arrivo\" si aggiungono dalla schermata Home tenendo premuto.", small: true)
            }
        }
    }
}

/// The ski areas kept on the iPhone.
private struct MapsPage: View {
    var body: some View {
        SettingsPageBody(title: "Mappe scaricate") {
            SavedMapsPanel()
            Words("La mappa di sfondo resta quella di Apple, che tiene in memoria solo le zone già guardate: prima di partire apri la mappa della stazione una volta con il campo.", small: true)
        }
    }
}

/// All the days in one file, and back.
private struct BackupPage: View {
    @Environment(Library.self) private var library
    @State private var backup: URL?
    @State private var restoring = false
    @State private var note: String?
    @State private var error: String?

    var body: some View {
        SettingsPageBody(title: "Copia di sicurezza") {
            Panel("Copia di sicurezza") {
                ErrorBanner(error: $error)
                Words("Tutte le giornate in un file zip, da tenere su iCloud Drive o da portare su un altro iPhone. Ripristinando, le giornate che ci sono già non vengono toccate.", small: true)
                Button {
                    do {
                        backup = try library.exportBackup()
                        note = nil
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
                if let note {
                    Text(note).font(.caption).foregroundStyle(Theme.good)
                }
            }
            CloudPanel()
            Panel("Dove sono le giornate") {
                InfoRow("Giornate salvate", "\(library.days.count)")
                Words("Sono su questo iPhone e le trovi anche nell'app File, nella cartella Ski Apex. Con la copia su iCloud accesa sono anche lì.", small: true)
            }
        }
        .fileImporter(isPresented: $restoring, allowedContentTypes: [.zip]) { result in
            do {
                let added = try library.restore(from: try result.get())
                note = String(localized: "Giornate aggiunte: \(added).")
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// The copy of the days in iCloud: its switch, and what the last pass did.
private struct CloudPanel: View {
    @Environment(Library.self) private var library
    @AppStorage(Prefs.cloud) private var on = false

    var body: some View {
        let cloud = CloudCopy.shared
        Panel("iCloud") {
            Toggle(isOn: $on) {
                Text("Copia le giornate su iCloud").font(.subheadline).foregroundStyle(Theme.text)
            }
            .tint(Theme.accent)
            .onChange(of: on) { _, now in
                if now { Task { await cloud.sync(library) } } else { cloud.stop() }
            }
            Words("Accesa, ogni giornata salvata va anche nel tuo iCloud e torna da sola su un altro iPhone con lo stesso account, o su questo se lo cambi. Una giornata eliminata qui viene tolta anche lì.", small: true)
            if on {
                switch cloud.state {
                case .off:
                    EmptyView()
                case .working:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Controllo iCloud…").font(.subheadline).foregroundStyle(Theme.sub)
                    }
                case .unavailable:
                    Words("Qui iCloud non si può usare: questa versione dell'app non ce l'ha (succede con quella installata con Feather, e finché non è attivato per quella di TestFlight), oppure l'iPhone non è collegato a iCloud. Le giornate restano su questo iPhone.", small: true)
                case .failed(let why):
                    Text(why).font(.caption).foregroundStyle(Theme.bad)
                case .done:
                    InfoRow("Giornate su iCloud", "\(cloud.outcome.inCloud)")
                    if cloud.outcome.waiting > 0 {
                        InfoRow("In arrivo da iCloud", "\(cloud.outcome.waiting)")
                    }
                    if let last = cloud.last {
                        InfoRow("Ultimo controllo", Fmt.time(last))
                    }
                }
                Button { Task { await cloud.sync(library) } } label: { Label("Controlla ora", systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(cloud.state == .working)
            }
        }
        .task { if on { await cloud.sync(library) } }
    }
}

/// How it works, and a made-up day to try it.
private struct HelpPage: View {
    @Environment(Library.self) private var library
    @State private var made = false

    var body: some View {
        SettingsPageBody(title: "Aiuto e prova") {
            Panel("Come funziona") {
                Words("Ski Apex registra il GPS circa una volta al secondo, anche a schermo spento, e misura la quota con il barometro. Una discesa è quando scendi muovendoti per almeno \(Int(Segmenter.minRunDrop)) m di dislivello; una risalita quando sali di almeno \(Int(Segmenter.minLiftGain)) m. Le soste brevi in pista restano dentro la discesa.")
                Words("Consigli: carica l'iPhone prima di partire, con il freddo la batteria scende in fretta. Tienilo in una tasca interna. Le giornate restano solo su questo iPhone e le trovi anche nell'app File, nella cartella Ski Apex.")
                Words("Velocità, distanze e quote sono stime del GPS e del barometro: non usarle per la sicurezza.", small: true)
            }
            Panel("Prova") {
                Words("Una giornata inventata, con risalite e discese, per vedere l'app senza andare sulla neve.")
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
        }
    }
}

/// What came with this version.
private struct NewsPage: View {
    private static let news: [(symbol: String, title: String, text: String)] = [
        ("signpost.right.fill", "Le tue piste", "Per ogni pista quante volte l'hai fatta, il tuo tempo migliore e la velocità massima. In Statistiche, nella pagina di una stazione e di una discesa."),
        ("flag.checkered", "Sfida sulla pista", "Accendi la sfida e in ogni pista vedi la classifica dei tempi con i tuoi amici."),
        ("person.2.fill", "Punto d'incontro", "In Esplora tocca un rifugio, una pista o un impianto e scegli Troviamoci qui: gli amici lo vedono sulla mappa, con il percorso per arrivarci."),
        ("photo.fill", "Schede da condividere nuove", "Le discese nel colore della pista, il profilo della giornata e l'icona dell'app, in formato post o storia."),
        ("icloud.fill", "Copia su iCloud", "Le giornate anche nel tuo iCloud, per ritrovarle cambiando iPhone. Si accende in Copia di sicurezza, dove iCloud è disponibile."),
        ("applewatch", "Watch e widget rinnovati", "Lo stesso aspetto dell'app sul Watch e nei widget, e una complicazione per aprire Ski Apex dal quadrante."),
        ("chart.xyaxis.line", "Il profilo della giornata", "Su con gli impianti, giù per le piste nel colore dei cartelli: in ogni giornata dell'elenco e in testa alla sua pagina."),
        ("circle.fill", "Bollini delle piste", "Ogni pista con il suo colore e il suo numero, come sui cartelli; sulla mappa le discese prendono il colore della pista."),
        ("magnifyingglass", "La stazione sulla mappa", "Apri una stazione dalla Guida e la mappa dietro la mostra con tutte le piste e gli impianti."),
        ("eyeglasses", "Icona nuova", "Una maschera da sci con la vetta nella lente. Quattro disegni, e il primo anche negli altri colori: si scelgono in Aspetto."),
        ("map", "La mappa dietro a tutto", "Le schermate stanno su un pannello che tiri su e giù sopra la mappa; a destra la tua foto, Giornate, Guida, Amici e il pulsante per registrare."),
        ("mountain.2.fill", "Mappa invernale", "Neve, ombre e curve di livello disegnate dall'app, con le montagne di notte da lontano. Anche in giornata, discesa, Rivivi ed Esplora."),
        ("figure.snowboarding", "Cosa fai oggi?", "Sci, snowboard, telemark o slittino: lo scegli prima di iniziare a registrare."),
        ("snowflake", "Com'era la neve?", "A fine giornata dici com'era la neve: chi apre la stazione lo vede, insieme alla giornata media di chi ha sciato lì."),
        ("applewatch.radiowaves.left.and.right", "Continua sul Watch", "Inizi dall'iPhone, passi la giornata al Watch e metti via il telefono: a fine giornata arriva tutto qui."),
        ("mountain.2", "La pagina della stazione", "Piste, impianti, quote, la neve di oggi ora per ora e quella dell'ultima settimana."),
        ("arrow.down.circle", "Mappe scaricate", "Piste e impianti di una stazione sull'iPhone, per quando non c'è campo. E il nome della pista mentre scii."),
        ("square.and.arrow.up", "Riepilogo della stagione", "I numeri della stagione in un'immagine da condividere. Da Statistiche."),
        ("applewatch", "Il Watch registra da solo", "Con il GPS dell'orologio, senza iPhone: la giornata arriva qui quando finisci."),
        ("point.topleft.down.to.point.bottomright.curvepath", "Mappa delle piste e percorsi", "Piste, impianti e rifugi di una stazione, e la strada da un punto all'altro. Dalla Guida."),
        ("person.crop.circle", "Foto del profilo", "I tuoi amici ti vedono in classifica e sulla mappa con la tua foto."),
        ("person.badge.key", "Accesso con Apple e Google", "Un account per gli amici senza inventare una password."),
        ("paintpalette", "Temi e icone", "Sei aspetti per l'app e l'icona negli stessi colori."),
        ("square.grid.2x2", "Widget", "La neve in arrivo in una località a scelta, e un tasto per registrare."),
        ("dot.radiowaves.left.and.right", "Amici vicini", "In diretta sulla mappa, con un avviso quando uno è vicino; con il Bluetooth anche senza campo."),
    ]

    var body: some View {
        SettingsPageBody(title: "Novità") {
            Panel {
                ForEach(Array(Self.news.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.symbol).font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
                            .frame(width: 34, height: 34)
                            .iconBox()
                        VStack(alignment: .leading, spacing: 3) {
                            Text(LocalizedStringKey(item.title)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                            Text(LocalizedStringKey(item.text)).prose().font(.caption).foregroundStyle(Theme.sub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if i < Self.news.count - 1 { Divider().overlay(Theme.line) }
                }
            }
        }
    }
}

/// What stays on the iPhone and what leaves it.
private struct PrivacyPage: View {
    var body: some View {
        SettingsPageBody(title: "Ski Apex e i tuoi dati") {
            Panel("Sul tuo iPhone") {
                Words("Le giornate, con le tracce e i posti, restano sul tuo iPhone, e nel tuo iCloud se accendi la copia. Nessuno le vede se non le condividi tu.")
            }
            Panel("Quello che esce") {
                Words("Nomi delle piste e meteo: la zona della giornata, a OpenStreetMap e Open-Meteo, senza il tuo nome. Si spegne da Integrazioni.")
                Words("Mappa invernale: i riquadri della zona che guardi, chiesti come quote a un archivio pubblico (AWS Open Data), senza il tuo nome. Si spegne con lo stesso interruttore, e resta la mappa di Apple.")
                Words("Amici: il nome, la foto se la metti e i totali della stagione. Se accedi con Apple o Google, al server arriva solo un identificativo: niente email.")
                Words("Posizione in diretta: solo se la accendi e solo mentre registri. Il server tiene l'ultima, non la salva e la dimentica dopo dieci minuti.")
                Words("Bluetooth: solo se lo accendi. Passa un codice che cambia ogni giorno, non la posizione.")
                Words("Com'era la neve: solo se lo dici a fine giornata. Parte la zona della stazione al chilometro, com'era la neve e i numeri della giornata, senza nomi; agli amici il tuo nome solo se lo lasci acceso.")
                Words("Sfida sulle piste: solo se la accendi. Agli amici arrivano i nomi delle piste che hai sciato, dove sono al chilometro, il tuo tempo migliore, la velocità massima e quante volte. Spegnendola il server cancella tutto.")
                Words("Punto d'incontro: solo quando lo mandi. Agli amici arriva il posto che hai scelto sulla mappa, non dove sei, e sparisce dopo l'orario o dopo mezza giornata.")
                Words("Copia su iCloud: solo se la accendi. Le giornate vanno nel tuo iCloud, quello di Apple: il server di Ski Apex non le vede.")
            }
            Panel("Mai") {
                Words("Niente pubblicità, niente tracciamento, niente dati venduti. Eliminando l'account dal Profilo, il server cancella tutto quello che aveva.")
            }
        }
    }
}

/// Whose work Ski Apex stands on.
private struct CreditsPage: View {
    var body: some View {
        SettingsPageBody(title: "Riconoscimenti") {
            Panel("Mappe e nomi") {
                Words("Nomi di piste, impianti, rifugi e stazioni: © i contributori di OpenStreetMap, con licenza ODbL. Ricerca delle stazioni: Photon di komoot.")
                Link("openstreetmap.org/copyright", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                    .font(.subheadline)
            }
            Panel("Meteo e quote") {
                Words("Meteo delle giornate, neve prevista e quote: Open-Meteo.com, con licenza CC BY 4.0.")
                Link("open-meteo.com", destination: URL(string: "https://open-meteo.com")!)
                    .font(.subheadline)
            }
            Panel("Mappa") {
                Words("La mappa sotto le tracce è Mappe di Apple.")
            }
        }
    }
}
