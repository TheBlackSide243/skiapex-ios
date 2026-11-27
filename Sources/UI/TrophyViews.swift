import SwiftUI

/// One trophy: lit when earned, with the day it was; faint with how far along it is when not.
struct TrophyTile: View {
    let trophy: Trophy

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: trophy.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(trophy.done ? Theme.onAccent : Theme.sub)
                .frame(width: 46, height: 46)
                .background(trophy.done ? Theme.accent : Theme.input, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(trophy.title)).font(.subheadline.weight(.semibold))
                    .foregroundStyle(trophy.done ? Theme.text : Theme.sub)
                    .lineLimit(2).minimumScaleFactor(0.85)
                Text(LocalizedStringKey(trophy.detail)).font(.caption).foregroundStyle(Theme.sub)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let earned = trophy.earned {
                Text(Fmt.dayShort(earned)).font(.caption2.weight(.semibold)).foregroundStyle(Theme.accent)
            } else {
                ProgressBar(fraction: trophy.progress, color: Theme.sub)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 172, alignment: .topLeading)
        .card()
        .opacity(trophy.done ? 1 : 0.8)
        .accessibilityElement(children: .combine)
    }
}

/// Every trophy: the ones earned first, the newest of them on top, then the ones closest to come.
struct TrophiesView: View {
    @Environment(Library.self) private var library

    var body: some View {
        let all = Trophies.all(library.days)
        let earned = all.filter(\.done).sorted { ($0.earned ?? .distantPast) > ($1.earned ?? .distantPast) }
        let open = all.filter { !$0.done }.sorted { $0.progress > $1.progress }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(earned.count) di \(all.count)").font(.display(.title2)).monospacedDigit().foregroundStyle(Theme.text)
                    .padding(.horizontal, 4)
                ProgressBar(fraction: all.isEmpty ? 0 : Double(earned.count) / Double(all.count))
                    .padding(.horizontal, 4)
                if !earned.isEmpty {
                    SectionTitle("Conquistati")
                    grid(earned)
                }
                if !open.isEmpty {
                    SectionTitle("Da conquistare")
                    grid(open)
                }
            }
            .padding(16)
        }
        .screen()
        .navigationTitle("Trofei")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func grid(_ trophies: [Trophy]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(trophies) { TrophyTile(trophy: $0) }
        }
    }
}

/// On the page of a day: the trophies it earned.
struct DayTrophies: View {
    let id: UUID
    @Environment(Library.self) private var library

    var body: some View {
        if let day = library.days.first(where: { $0.id == id }) {
            let earned = Trophies.earned(on: day, among: library.days)
            if !earned.isEmpty {
                Panel(earned.count == 1 ? "Trofeo di questa giornata" : "Trofei di questa giornata") {
                    ForEach(earned) { trophy in
                        HStack(spacing: 12) {
                            Image(systemName: trophy.symbol).font(.footnote.weight(.semibold)).foregroundStyle(Theme.onAccent)
                                .frame(width: 36, height: 36)
                                .background(Theme.accent, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(LocalizedStringKey(trophy.title)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                                Text(LocalizedStringKey(trophy.detail)).font(.caption).foregroundStyle(Theme.sub)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}
