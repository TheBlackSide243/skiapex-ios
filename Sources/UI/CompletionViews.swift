import SwiftUI

/// On the page of a ski area: how many of its pistes you have skied, by the color of the signs,
/// and which are left. Shown once you skied at least one there.
struct ResortCompletion: View {
    let resort: Resort
    let terrain: Terrain?
    @Environment(Library.self) private var library
    @State private var all = false

    var body: some View {
        if let terrain {
            let tally = Completion.tally(terrain.ways, skied: Completion.skied(library.days, nearLat: resort.lat, lon: resort.lon))
            if tally.done > 0 {
                Panel("Piste completate") {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(tally.done) di \(tally.total)").font(.display(.title2)).monospacedDigit().foregroundStyle(Theme.text)
                        Spacer(minLength: 8)
                        Text(Fmt.percent(tally.fraction * 100)).font(.headline).monospacedDigit()
                            .foregroundStyle(tally.complete ? Theme.good : Theme.accent)
                    }
                    ProgressBar(fraction: tally.fraction, color: tally.complete ? Theme.good : Theme.accent)
                    HStack(spacing: 14) {
                        ForEach(tally.byDifficulty) { grade in
                            HStack(spacing: 6) {
                                PisteBadge(difficulty: grade.difficulty, ref: nil, size: 16)
                                Text(verbatim: "\(grade.done)/\(grade.total)").font(.caption.weight(.semibold)).monospacedDigit()
                                    .foregroundStyle(Theme.sub)
                            }
                        }
                    }
                    if tally.complete {
                        Label("Le hai fatte tutte", systemImage: "checkmark.seal.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.good)
                    } else {
                        missing(tally.missing)
                    }
                    NavigationLink {
                        ExploreView(name: resort.name, center: resort.coordinate, highlight: true)
                    } label: { Label("Guardale sulla mappa", systemImage: "map") }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    @ViewBuilder private func missing(_ pistes: [PisteTally.Piste]) -> some View {
        Text("Ti mancano").font(.caption.weight(.semibold)).foregroundStyle(Theme.sub)
        ForEach(pistes.prefix(all ? 300 : 5)) { piste in
            HStack(spacing: 10) {
                PisteBadge(difficulty: piste.difficulty, ref: piste.ref, size: 22)
                Text(verbatim: piste.label).font(.subheadline).foregroundStyle(Theme.text).lineLimit(1)
                Spacer(minLength: 6)
                Text(Fmt.distance(piste.meters)).font(.caption).monospacedDigit().foregroundStyle(Theme.sub)
            }
        }
        if pistes.count > 5 {
            Button { withAnimation(.snappy) { all.toggle() } } label: {
                Text(all ? String(localized: "Mostra meno") : String(localized: "Tutte le \(pistes.count) che mancano"))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
            }
            .buttonStyle(PressStyle())
        }
    }
}
