import Charts
import SwiftUI

/// "3 volte", "1 volta".
func timesText(_ count: Int) -> String {
    count == 1 ? String(localized: "1 volta") : String(localized: "\(count) volte")
}

/// The pistes you skied: how many times each, your best time and your top speed on it.
struct PistesView: View {
    /// Only the ones of a ski area, when given.
    var resort: Resort?
    @Environment(Library.self) private var library
    @State private var order = Order.most
    @State private var entries: [PisteEntry] = []
    @State private var opened: PisteEntry?

    enum Order: String, CaseIterable, Identifiable {
        case most, fastest, latest

        var id: String { rawValue }

        var label: String {
            switch self {
            case .most: "Più fatte"
            case .fastest: "Più veloci"
            case .latest: "Ultime"
            }
        }
    }

    private var sorted: [PisteEntry] {
        switch order {
        case .most: entries
        case .fastest: entries.sorted { $0.topSpeed > $1.topSpeed }
        case .latest: entries.sorted { $0.last > $1.last }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if entries.isEmpty {
                    empty
                } else {
                    StatGrid {
                        StatTile(value: "\(entries.count)", label: "Piste diverse", symbol: "signpost.right")
                        StatTile(value: "\(entries.reduce(0) { $0 + $1.count })", label: "Discese contate", symbol: "figure.skiing.downhill")
                    }
                    HStack(spacing: 8) {
                        ForEach(Order.allCases) { choice in
                            Button { withAnimation(.snappy) { order = choice } } label: {
                                ChoicePill(title: choice.label, on: choice == order, wide: true)
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                    Panel {
                        let list = sorted
                        ForEach(list) { entry in
                            NavigationLink { PisteDetailView(entry: entry) } label: { PisteRowView(entry: entry, showsPlace: resort == nil) }
                                .buttonStyle(PressStyle())
                            if entry.id != list.last?.id { Divider().overlay(Theme.line) }
                        }
                    }
                    Text("Qui ci sono le discese fatte su una pista che OpenStreetMap conosce per nome. Il tempo migliore conta solo le discese fatte per intero, o quasi.")
                        .prose().font(.caption).foregroundStyle(Theme.sub)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
        .screen()
        .navigationTitle(LocalizedStringKey(resort == nil ? "Le tue piste" : "Le tue piste qui"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $opened) { PisteDetailView(entry: $0) }
        .task(id: library.saves) {
            entries = resort.map { PisteBook.entries(library.days, nearLat: $0.lat, lon: $0.lon) } ?? PisteBook.entries(library.days)
            // The picture of one piste opens the one skied most.
            if Demo.screen == "piste", opened == nil { opened = entries.first }
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "signpost.right")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 84, height: 84)
                .iconBox()
            Text("Ancora nessuna pista").font(.display(.headline)).foregroundStyle(Theme.text)
            Text("Le piste compaiono qui quando una giornata registrata passa su piste che OpenStreetMap conosce per nome.")
                .prose().font(.subheadline).foregroundStyle(Theme.sub).multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .card()
        .padding(.top, 40)
    }
}

/// One piste in a list: its badge, its name, how many times and the best time.
struct PisteRowView: View {
    let entry: PisteEntry
    var showsPlace = true

    var body: some View {
        HStack(spacing: 12) {
            PisteBadge(difficulty: entry.difficulty, ref: entry.ref, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
            }
            Spacer(minLength: 6)
            if let best = entry.best {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.lap(best.seconds)).font(.display(.subheadline)).monospacedDigit().foregroundStyle(Theme.accent)
                    Text("migliore").font(.caption2).foregroundStyle(Theme.sub)
                }
            }
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.sub)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        // How many times first: a long name of a place is what gets cut.
        if showsPlace, let place = entry.place { return "\(timesText(entry.count)) · \(place)" }
        return "\(timesText(entry.count)) · \(Fmt.speed(entry.topSpeed))"
    }
}

/// One piste: your numbers on it, your times one by one, and the challenge with your friends.
struct PisteDetailView: View {
    let entry: PisteEntry
    @Environment(Library.self) private var library
    @Environment(Social.self) private var social
    @AppStorage(Prefs.sharePistes) private var shares = false
    @State private var board: [PisteRow]?
    @State private var asked = false

    /// The challenge is on: always in the pictures.
    private var on: Bool { shares || Demo.isOn }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                StatGrid {
                    StatTile(value: "\(entry.count)", label: entry.count == 1 ? "Volta" : "Volte", symbol: "repeat")
                    StatTile(value: entry.best.map { Fmt.lap($0.seconds) } ?? "–", label: "Tempo migliore", symbol: "stopwatch", color: Theme.accent)
                    StatTile(value: Fmt.speed(entry.topSpeed), label: "Velocità max", symbol: "speedometer")
                    StatTile(value: Fmt.height(entry.vertical), label: "Dislivello in tutto", symbol: "arrow.down.right")
                    StatTile(value: Fmt.distance(entry.meters), label: "Lunghezza", symbol: "point.topleft.down.to.point.bottomright.curvepath")
                    StatTile(value: Fmt.height(entry.fullDrop), label: "Dislivello", symbol: "triangle")
                }
                if entry.whole.count >= 3 { times }
                challenge
                laps
                Text("Il tempo migliore conta solo le discese fatte per intero o quasi: almeno l'85% del dislivello più grande che hai registrato su questa pista.")
                    .prose().font(.caption).foregroundStyle(Theme.sub)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .screen()
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(on)-\(social.account?.id ?? "")") {
            guard on else { return }
            if !Demo.isOn { await social.sharePistes(library.days) }
            board = await social.pisteBoard(entry)
            asked = true
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            PisteBadge(difficulty: entry.difficulty, ref: entry.ref, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name).font(.display(.title3)).foregroundStyle(Theme.text).lineLimit(2).minimumScaleFactor(0.7)
                Text(subtitle).font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let place = entry.place { parts.append(place) }
        if let label = Theme.difficultyLabel(entry.difficulty) { parts.append(String(localized: String.LocalizationValue(label))) }
        parts.append(String(localized: "ultima volta \(Fmt.dayShort(entry.last))"))
        return parts.joined(separator: " · ")
    }

    /// The times down the whole piste, from the first to the last: the best one in full color.
    private var times: some View {
        let whole = Array(entry.whole.enumerated())
        let best = entry.best?.id
        return Panel("I tuoi tempi") {
            Chart(whole, id: \.offset) { item in
                BarMark(x: .value("Discesa", "\(item.offset + 1)"), y: .value("Tempo", item.element.seconds))
                    .foregroundStyle(item.element.id == best ? Theme.accent : Theme.accent.opacity(0.32))
                    .cornerRadius(4)
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Theme.line)
                    AxisValueLabel {
                        if let s = value.as(Double.self) { Text(Fmt.lap(s)).font(.caption2).foregroundStyle(Theme.sub) }
                    }
                }
            }
            .frame(height: 130)
            .accessibilityLabel(Text("I tempi delle tue discese su questa pista, dalla prima all'ultima"))
        }
    }

    // MARK: The challenge

    @ViewBuilder private var challenge: some View {
        Panel("Sfida con gli amici") {
            if !social.signedIn {
                Text("Per sfidare gli amici su questa pista serve l'account degli amici: lo trovi nella schermata Amici.")
                    .prose().font(.subheadline).foregroundStyle(Theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !on {
                Text("Con la sfida accesa i tuoi amici vedono le piste che hai sciato, con il tuo tempo migliore su ognuna, e tu vedi i loro. Le tracce restano sul tuo iPhone.")
                    .prose().font(.subheadline).foregroundStyle(Theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
                Button { shares = true } label: { Label("Accendi la sfida", systemImage: "flag.checkered") }
                    .buttonStyle(PrimaryButtonStyle())
            } else if let board {
                let mine = board.contains { $0.me }
                ForEach(Array(board.enumerated()), id: \.element.id) { place, row in
                    HStack(spacing: 12) {
                        Text("\(place + 1)").font(.display(.subheadline)).monospacedDigit()
                            .foregroundStyle(row.me ? Theme.accent : Theme.sub)
                            .frame(width: 22)
                        Avatar(id: row.id, name: row.name, photo: row.photo, size: 36, ring: row.me ? Theme.accent : nil)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(row.name).font(.subheadline.weight(row.me ? .bold : .regular)).foregroundStyle(Theme.text).lineLimit(1)
                                if row.me { Text("tu").font(.caption2.weight(.semibold)).foregroundStyle(Theme.accent) }
                            }
                            Text("\(timesText(row.runs)) · \(Fmt.speed(row.speed))").font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Text(Fmt.lap(row.best)).font(.display(.subheadline)).monospacedDigit()
                            .foregroundStyle(row.me ? Theme.accent : Theme.text)
                    }
                    .accessibilityElement(children: .combine)
                    if row.id != board.last?.id { Divider().overlay(Theme.line) }
                }
                if board.count <= (mine ? 1 : 0) {
                    Text("Per ora ci sei solo tu su questa pista. Quando un amico la scia con la sfida accesa, compare qui.")
                        .prose().font(.caption).foregroundStyle(Theme.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if asked {
                Text("Non riesco a leggere la classifica di questa pista. Controlla la connessione e riprova.")
                    .prose().font(.subheadline).foregroundStyle(Theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(12)
            }
        }
    }

    // MARK: Every time down it

    private var laps: some View {
        let list = Array(entry.laps.reversed().prefix(40))
        let best = entry.best?.id
        let least = entry.fullDrop * PisteBook.wholeShare
        return Panel("Le tue discese") {
            ForEach(list) { lap in
                NavigationLink(value: lap.day) {
                    HStack(spacing: 10) {
                        Image(systemName: lap.id == best ? "trophy.fill" : "figure.skiing.downhill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(lap.id == best ? Theme.warn : Theme.sub)
                            .frame(width: 24)
                            .accessibilityLabel(Text(LocalizedStringKey(lap.id == best ? "Il tuo tempo migliore" : "Discesa")))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Fmt.dayShort(lap.date)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                            Text(lap.drop >= least ? "\(Fmt.time(lap.date)) · \(Fmt.speed(lap.maxSpeed))"
                                 : "\(Fmt.time(lap.date)) · \(String(localized: "non per intero"))")
                                .font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Text(Fmt.lap(lap.seconds)).font(.display(.subheadline)).monospacedDigit()
                            .foregroundStyle(lap.id == best ? Theme.accent : Theme.text)
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.sub)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                if lap.id != list.last?.id { Divider().overlay(Theme.line) }
            }
        }
    }
}

/// On the page of a ski area: the pistes you skied there most, and the way to all of them.
struct ResortPistes: View {
    let resort: Resort
    @Environment(Library.self) private var library

    var body: some View {
        let entries = PisteBook.entries(library.days, nearLat: resort.lat, lon: resort.lon)
        if !entries.isEmpty {
            Panel("Le tue piste qui") {
                ForEach(entries.prefix(3)) { entry in
                    NavigationLink { PisteDetailView(entry: entry) } label: { PisteRowView(entry: entry, showsPlace: false) }
                        .buttonStyle(PressStyle())
                    Divider().overlay(Theme.line)
                }
                NavigationLink { PistesView(resort: resort) } label: {
                    HStack {
                        Text(entries.count == 1 ? String(localized: "Vedi la pista") : String(localized: "Tutte le \(entries.count) piste"))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
    }
}

/// On the page of a run: how you did on its piste the other times.
struct RunPisteLink: View {
    let day: SkiDay
    let run: Segment
    @Environment(Library.self) private var library

    var body: some View {
        let summary = library.days.first { $0.id == day.id }
        if let entry = PisteBook.entry(named: run.name, of: summary, in: PisteBook.entries(library.days)), let best = entry.best {
            let record = best.day == day.id && abs(best.date.timeIntervalSince(run.startTime)) < 1
            NavigationLink { PisteDetailView(entry: entry) } label: {
                HStack(spacing: 12) {
                    Image(systemName: record ? "trophy.fill" : "signpost.right.fill")
                        .font(.footnote.weight(.semibold)).foregroundStyle(record ? Theme.warn : Theme.accent)
                        .frame(width: 36, height: 36)
                        .iconBox(record ? Theme.warn : Theme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(LocalizedStringKey(record ? "Il tuo tempo migliore su questa pista" : "Su questa pista"))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.8)
                        Text("\(timesText(entry.count)) · \(String(localized: "migliore")) \(Fmt.lap(best.seconds))")
                            .font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.sub)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
        }
    }
}
