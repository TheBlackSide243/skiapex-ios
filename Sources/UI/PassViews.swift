import SwiftUI

extension PassCharge.Tariff {
    var label: String {
        switch self {
        case .paid: String(localized: "Pagato")
        case .day: String(localized: "Giornaliero")
        case .hours(let hours): String(localized: "\(hours) ore")
        case .morning: String(localized: "Mattiniero")
        case .afternoon: String(localized: "Pomeridiano")
        case .days(let count): String(localized: "\(count)° giorno di fila")
        case .reached: String(localized: "Traguardo raggiunto")
        case .discounted: String(localized: "Sconto del traguardo")
        case .same: String(localized: "Stessa giornata")
        case .unknown: String(localized: "Da scrivere")
        }
    }
}

extension PassCharge {
    /// "Stima · 4 ore", "Pagato".
    var note: String {
        estimated && amount != nil ? String(localized: "Stima · \(tariff.label)") : tariff.label
    }
}

extension Snowit {
    /// The tariffs, when they are those of that season.
    static func tariffs(for season: Season) -> SnowitBook? {
        guard let book, book.season == season.year else { return nil }
        return book
    }

    static let account = URL(string: "https://snowit.ski/account/memberships")
    static func prices(of zone: SnowitBook.Zone) -> URL? { URL(string: "https://snowit.ski/snowitpass/pricing/\(zone.s)") }
}

/// A sum in euros, typed.
struct MoneyField: View {
    let title: String
    @Binding var value: Double?
    @State private var text = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField(LocalizedStringKey(title), text: $text)
                .keyboardType(.decimalPad)
                .font(.headline).monospacedDigit()
            Text(verbatim: "€").font(.headline).foregroundStyle(Theme.sub)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(Theme.input, in: Theme.roundSmall)
        .onAppear { text = value.map(Self.plain) ?? "" }
        .onChange(of: text) { _, now in value = Self.parse(now) }
    }

    /// "74,50" and "74.5" are both seventy-four and a half. nil for what is not a sum.
    static func parse(_ text: String) -> Double? {
        let clean = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let x = Double(clean), x >= 0, x < 100_000 else { return nil }
        return x
    }

    static func plain(_ x: Double) -> String {
        if x == x.rounded() { return String(Int(x)) }
        return String(format: "%.2f", x).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ",")
    }
}

/// What skiing cost in a season: how the pass is paid, what that makes for each day, each run and
/// each thousand meters, and with SnowitPass how far the spending goals are.
struct PassView: View {
    @Environment(Library.self) private var library
    let season: Season
    @State private var plan = PassPlan()
    @State private var loaded = false
    @State private var editing: DaySummary?

    private var days: [DaySummary] { library.days(in: season) }
    private var book: SnowitBook? { Snowit.tariffs(for: season) }

    var body: some View {
        let summary = Passes.summary(plan, days: days, book: book)
        ScrollView {
            VStack(spacing: 14) {
                how
                if plan.kind != .off {
                    figures(summary)
                    if plan.kind == .season { payOff(summary) }
                    if !summary.bill.goals.isEmpty { goals(summary) }
                    if plan.kind != .season { list(summary) }
                    about
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .screen()
        .navigationTitle("Skipass e costi")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !loaded else { return }
            plan = Demo.isOn ? Passes.demo : Passes.plan(of: season)
            loaded = true
        }
        .onChange(of: plan) { _, now in
            if loaded, !Demo.isOn { Passes.set(now, for: season) }
        }
        .sheet(item: $editing) { day in
            PassDayEditor(day: day, season: season, plan: $plan)
        }
    }

    private var how: some View {
        Panel("Come paghi lo skipass") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(PassPlan.Kind.allCases) { kind in
                    Button {
                        withAnimation(.snappy) { plan.kind = kind }
                    } label: {
                        ChoicePill(title: kind.title, on: plan.kind == kind, wide: true)
                    }
                    .buttonStyle(PressStyle())
                }
            }
            switch plan.kind {
            case .off:
                words("Scegli come paghi e vedi quanto ti costa ogni giornata, ogni discesa e ogni mille metri di dislivello.")
            case .season:
                MoneyField(title: "Prezzo dello stagionale", value: $plan.seasonPrice)
                age
            case .daily:
                age
                words("Per ogni giornata scrivi quanto hai pagato. Dove conosco il prezzo del giornaliero lo propongo io.")
            case .snowit:
                age
                Toggle(isOn: $plan.activation) {
                    Text("Conta l'attivazione").font(.subheadline).foregroundStyle(Theme.text)
                }
                .tint(Theme.accent)
                words("SnowitPass è lo skipass a consumo di Snowit: passi dai tornelli e a fine giornata paghi la tariffa migliore per il tempo che hai sciato.")
            }
        }
    }

    private var age: some View {
        HStack {
            Text("Categoria").font(.subheadline).foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            Picker("Categoria", selection: $plan.age) {
                ForEach(PassAge.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
            }
            .pickerStyle(.menu)
            .tint(Theme.accent)
        }
    }

    private func words(_ text: LocalizedStringKey) -> some View {
        Text(text).prose().font(.caption).foregroundStyle(Theme.sub).fixedSize(horizontal: false, vertical: true)
    }

    private func figures(_ summary: PassSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            StatGrid {
                StatTile(value: Fmt.money(summary.total), label: "Spesa della stagione", symbol: "eurosign")
                StatTile(value: summary.perDay.map(Fmt.money) ?? "–", label: "A giornata", symbol: "calendar")
                StatTile(value: summary.perRun.map(Fmt.money) ?? "–", label: "A discesa", symbol: "figure.skiing.downhill")
                StatTile(value: summary.perKilometer.map(Fmt.money) ?? "–", label: "Ogni 1000 m", symbol: "arrow.down.right")
            }
            if summary.bill.activation > 0 {
                words("Compresi \(Fmt.money(summary.bill.activation)) per attivare SnowitPass.")
            }
            if plan.kind != .season, summary.bill.unknown == 1 {
                words("1 giornata senza prezzo, non contata qui: toccala per scriverlo.")
            } else if plan.kind != .season, summary.bill.unknown > 1 {
                words("\(summary.bill.unknown) giornate senza prezzo, non contate qui: toccale per scriverlo.")
            }
        }
    }

    @ViewBuilder private func payOff(_ summary: PassSummary) -> some View {
        if summary.total > 0 {
            Panel("Si è ripagato?") {
                InfoRow("Stagionale", Fmt.money(summary.total))
                if summary.listDays > 0 {
                    InfoRow("Le stesse giornate coi giornalieri", Fmt.money(summary.list))
                    if summary.list >= summary.total {
                        Label("Sì: coi giornalieri avresti speso \(Fmt.money(summary.list - summary.total)) in più.", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.good)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let more = summary.daysToPayOff {
                        words("Non ancora: mancano circa \(more) giornate come queste.")
                    }
                } else {
                    words("Dei posti dove hai sciato non conosco il prezzo del giornaliero, quindi non so dirti se si è ripagato.")
                }
            }
        }
    }

    private func goals(_ summary: PassSummary) -> some View {
        Panel("Traguardi di spesa") {
            ForEach(summary.bill.goals) { state in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: state.goal.n).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                        Spacer(minLength: 8)
                        Text("\(Fmt.money(state.spent)) di \(Fmt.money(state.target))")
                            .font(.subheadline).monospacedDigit().foregroundStyle(Theme.sub)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    ProgressBar(fraction: state.fraction, color: state.reached ? Theme.good : Theme.accent)
                    Text(Self.benefit(state, book: book)).font(.caption).foregroundStyle(Theme.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// What reaching a goal gives, and what is left to it.
    static func benefit(_ state: PassGoalState, book: SnowitBook?) -> String {
        let names = state.goal.z.compactMap { book?.zone($0)?.n }
        let place = state.goal.k == "R" || names.count > 5
            ? String(localized: "nei comprensori di \(state.goal.n)")
            : String(localized: "a \(names.formatted(.list(type: .and)))")
        let free = state.goal.x == 0
        if state.reached {
            return free ? String(localized: "Raggiunto: fino a fine stagione scii gratis \(place).")
                : String(localized: "Raggiunto: fino a fine stagione hai lo sconto \(place).")
        }
        let left = Fmt.money(state.left)
        return free ? String(localized: "Ancora \(left), poi scii gratis \(place) fino a fine stagione.")
            : String(localized: "Ancora \(left), poi hai l'80% di sconto \(place) fino a fine stagione.")
    }

    private func list(_ summary: PassSummary) -> some View {
        Panel("Giornate") {
            ForEach(days) { day in
                let charge = summary.bill.charges[day.id]
                Button { editing = day } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(day.title ?? String(localized: "Giornata sulla neve"))
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                            Text(Fmt.dayShort(day.start)).font(.caption).foregroundStyle(Theme.sub)
                        }
                        Spacer(minLength: 6)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(charge?.amount.map(Fmt.money) ?? "–")
                                .font(.display(.subheadline)).monospacedDigit().foregroundStyle(Theme.accent)
                            Text(charge?.note ?? "").font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
                        }
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.sub)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                if day.id != days.last?.id { Divider().overlay(Theme.line) }
            }
        }
    }

    @ViewBuilder private var about: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch plan.kind {
            case .snowit:
                if book != nil {
                    words("Sono stime, fatte con le tariffe che Snowit pubblica per la stagione \(season.label): contano il tempo tra il primo e l'ultimo impianto, i giorni di fila e i traguardi di spesa. Snowit non lascia leggere gli addebiti ad altre app: quello vero lo vedi nella loro, e lo scrivi qui toccando la giornata. Ski Apex non è collegata a Snowit.")
                } else {
                    words("Di questa stagione non ho le tariffe di Snowit: scrivi tu l'addebito di ogni giornata. Ski Apex non è collegata a Snowit.")
                }
                if let url = Snowit.account {
                    Link(destination: url) { Label("Guarda gli addebiti su Snowit", systemImage: "arrow.up.right") }
                        .buttonStyle(SecondaryButtonStyle())
                }
            case .daily, .season:
                words("I prezzi dei giornalieri sono quelli che Snowit pubblica per i comprensori di SnowitPass, stagione \(season.label): negli altri posti scrivi tu il prezzo. Ski Apex non è collegata a Snowit.")
            case .off:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

/// What was paid for one day, and whose tariffs it is reckoned with.
struct PassDayEditor: View {
    let day: DaySummary
    let season: Season
    @Binding var plan: PassPlan
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var amount: Double?

    private var book: SnowitBook? { Snowit.tariffs(for: season) }
    private var key: String { day.id.uuidString }

    /// What the day is reckoned to cost without what was written for it.
    private var estimate: PassCharge? {
        var bare = plan
        bare.paid[key] = nil
        return Passes.summary(bare, days: library.days(in: season), book: book).bill.charges[day.id]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Panel {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(day.title ?? String(localized: "Giornata sulla neve")).font(.headline).foregroundStyle(Theme.text)
                            Text(Fmt.day(day.start)).font(.caption).foregroundStyle(Theme.sub)
                        }
                        MoneyField(title: "Quanto hai pagato", value: $amount)
                        if let estimate, let sum = estimate.amount, estimate.tariff != .same {
                            Text("Stima: \(Fmt.money(sum)) · \(estimate.tariff.label)")
                                .font(.caption).foregroundStyle(Theme.sub)
                        }
                    }
                    if let book, let title = day.title {
                        Panel {
                            HStack {
                                Text("Tariffe di").font(.subheadline).foregroundStyle(Theme.text)
                                Spacer(minLength: 8)
                                Picker("Tariffe di", selection: zone(title, book: book)) {
                                    Text("Nessuna").tag("-")
                                    ForEach(book.zones.filter(\.hasRates)) { Text(verbatim: $0.n).tag($0.s) }
                                }
                                .pickerStyle(.menu)
                                .tint(Theme.accent)
                            }
                            Text("Vale per tutte le giornate a \(title).").font(.caption).foregroundStyle(Theme.sub)
                        }
                    }
                    Button {
                        plan.paid[key] = amount
                        dismiss()
                    } label: { Label("Salva", systemImage: "checkmark") }
                        .buttonStyle(PrimaryButtonStyle())
                    if plan.paid[key] != nil {
                        Button {
                            plan.paid[key] = nil
                            dismiss()
                        } label: { Label("Torna alla stima", systemImage: "arrow.uturn.backward") }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Skipass della giornata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Chiudi") { dismiss() } }
            }
        }
        .modifier(Dressed())
        .presentationDetents([.medium, .large])
        .onAppear { amount = plan.paid[key] }
    }

    /// The place whose tariffs the days there are reckoned with: the one chosen, or the one found.
    private func zone(_ title: String, book: SnowitBook) -> Binding<String> {
        Binding(
            get: { Passes.passDay(day, plan: plan, book: book).zone ?? "-" },
            set: { plan.zones[title] = $0 }
        )
    }
}

/// On the page of a ski area of SnowitPass: what a day costs there today.
struct PassPricePanel: View {
    let lat: Double
    let lon: Double

    var body: some View {
        let season = Season(Date())
        let age = Passes.plan(of: season).age
        if let book = Snowit.tariffs(for: season), let zone = Snowit.zone(lat: lat, lon: lon, in: book),
           let rates = Snowit.rates(of: zone, on: Date(), age: age, in: book), let full = rates.d?.first {
            Panel("Skipass") {
                InfoRow("Giornaliero", Fmt.money(full))
                ForEach(rates.h ?? [], id: \.self) { band in
                    if band.count == 2 { InfoRow(String(localized: "\(Int(band[0])) ore"), Fmt.money(band[1])) }
                }
                if let am = rates.am?.first { InfoRow("Mattiniero", Fmt.money(am)) }
                if let pm = rates.pm?.first { InfoRow("Pomeridiano", Fmt.money(pm)) }
                Text("Prezzi di oggi, \(String(localized: String.LocalizationValue(age.title))), con SnowitPass: lo skipass a consumo di Snowit, che a fine giornata fa pagare la tariffa migliore per il tempo sciato. Ski Apex non è collegata a Snowit.")
                    .prose().font(.caption).foregroundStyle(Theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
                if let url = Snowit.prices(of: zone) {
                    Link(destination: url) { Label("Tariffe e attivazione su Snowit", systemImage: "arrow.up.right") }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }
}
