import SwiftUI

extension GoalProgress {
    var title: String {
        switch kind {
        case .days: "Giornate sulla neve"
        case .vertical: "Dislivello"
        case .distance: "Chilometri"
        }
    }

    var symbol: String {
        switch kind {
        case .days: "calendar"
        case .vertical: "arrow.down.right"
        case .distance: "point.topleft.down.to.point.bottomright.curvepath"
        }
    }

    /// A number of this goal as it is shown: "12", "42.300 m", "184 km".
    func text(_ x: Double) -> String {
        switch kind {
        case .days: "\(Int(x.rounded(.up)))"
        case .vertical: Fmt.height(x)
        case .distance: Fmt.distance(x)
        }
    }

    /// "8 di 12", "42.300 m di 60.000 m".
    var count: String { String(localized: "\(text(done)) di \(text(target))") }

    /// What is left, and the pace it takes: "Mancano 8 giornate: una ogni 2 settimane fino a
    /// metà aprile", "Mancano 36.128 m: 1806 m a settimana fino a metà aprile".
    func note(season: Season, now: Date = Date()) -> String? {
        guard !reached else { return nil }
        let weekly = Goals.weekly(self, season: season, now: now)
        switch kind {
        case .days:
            let days = Int(left.rounded(.up))
            let what = days == 1 ? String(localized: "Manca 1 giornata") : String(localized: "Mancano \(days) giornate")
            guard let weekly else { return what }
            // Less than one a week reads better as one every so many weeks.
            if weekly < 0.95 {
                return String(localized: "\(what): una ogni \(max(2, Int((1 / weekly).rounded()))) settimane fino a metà aprile")
            }
            let pace = weekly.formatted(.number.precision(.fractionLength(weekly < 10 ? 1 : 0)))
            return String(localized: "\(what): \(pace) a settimana fino a metà aprile")
        case .vertical, .distance:
            guard let weekly else { return String(localized: "Mancano \(text(left))") }
            let pace = kind == .vertical ? Fmt.height(weekly) : Fmt.distance(weekly)
            return String(localized: "Mancano \(text(left)): \(pace) a settimana fino a metà aprile")
        }
    }
}

/// A bar that fills from the left.
struct ProgressBar: View {
    let fraction: Double
    var color: Color = Theme.accent

    var body: some View {
        GeometryReader { box in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.input)
                Capsule().fill(color).frame(width: max(8, box.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// One goal: what it is, how far along, and what it takes to get there.
struct GoalRow: View {
    let goal: GoalProgress
    let season: Season

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(LocalizedStringKey(goal.title), systemImage: goal.symbol)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Spacer(minLength: 8)
                if goal.reached {
                    Label("Raggiunto", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.good)
                } else {
                    Text(goal.count).font(.subheadline).monospacedDigit().foregroundStyle(Theme.sub)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            ProgressBar(fraction: goal.fraction, color: goal.reached ? Theme.good : Theme.accent)
            if goal.reached {
                Text(goal.count).font(.caption).foregroundStyle(Theme.sub)
            } else if let note = goal.note(season: season) {
                Text(note).font(.caption).foregroundStyle(Theme.sub).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// In the statistics of a season: its goals, or the way to set them.
struct GoalsPanel: View {
    let season: Season
    let days: [DaySummary]
    @State private var goals = SeasonGoals()
    @State private var editing = false

    var body: some View {
        let list = Goals.progress(goals, days: days)
        Panel("Obiettivi della stagione") {
            if list.isEmpty {
                Text("Datti un traguardo per questa stagione: giornate sulla neve, dislivello, chilometri. Qui vedi a che punto sei.")
                    .prose().font(.subheadline).foregroundStyle(Theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(list) { GoalRow(goal: $0, season: season) }
            }
            Button { editing = true } label: {
                Label(LocalizedStringKey(list.isEmpty ? "Scegli gli obiettivi" : "Cambia gli obiettivi"), systemImage: "target")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .task(id: season) { goals = Demo.isOn ? Goals.demo : Goals.of(season) }
        .sheet(isPresented: $editing) { GoalsEditor(season: season, goals: $goals) }
    }
}

/// The goals of a season, each turned on and set with its own steps.
struct GoalsEditor: View {
    let season: Season
    @Binding var goals: SeasonGoals
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Panel {
                        Toggle(isOn: Binding(get: { goals.days != nil }, set: { goals.days = $0 ? 20 : nil })) {
                            Text("Giornate sulla neve").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                        }
                        .tint(Theme.accent)
                        if let days = goals.days {
                            Stepper(value: Binding(get: { days }, set: { goals.days = $0 }), in: 1...250) {
                                Text("\(days) giornate").font(.subheadline).monospacedDigit().foregroundStyle(Theme.text)
                            }
                        }
                    }
                    Panel {
                        Toggle(isOn: Binding(get: { goals.vertical != nil }, set: { goals.vertical = $0 ? 100_000 : nil })) {
                            Text("Dislivello").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                        }
                        .tint(Theme.accent)
                        if let vertical = goals.vertical {
                            Stepper(value: Binding(get: { vertical }, set: { goals.vertical = $0 }), in: 5000...2_000_000, step: 5000) {
                                Text(Fmt.height(vertical)).font(.subheadline).monospacedDigit().foregroundStyle(Theme.text)
                            }
                        }
                    }
                    Panel {
                        Toggle(isOn: Binding(get: { goals.distance != nil }, set: { goals.distance = $0 ? 500_000 : nil })) {
                            Text("Chilometri sciati").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                        }
                        .tint(Theme.accent)
                        if let distance = goals.distance {
                            Stepper(value: Binding(get: { distance }, set: { goals.distance = $0 }), in: 25_000...10_000_000, step: 25_000) {
                                Text(Fmt.distance(distance)).font(.subheadline).monospacedDigit().foregroundStyle(Theme.text)
                            }
                        }
                    }
                    Text("Valgono per la stagione \(season.label) e restano su questo iPhone. Contano tutte le giornate della stagione, anche quelle aggiunte a mano.")
                        .prose().font(.caption).foregroundStyle(Theme.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Obiettivi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Fine") { dismiss() } }
            }
        }
        .modifier(Dressed())
        .presentationDetents([.medium, .large])
        .onChange(of: goals) { _, now in
            if !Demo.isOn { Goals.set(now, for: season) }
        }
    }
}
