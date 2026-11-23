import SwiftUI

/// The numbers of a ski area, from its pistes and lifts on OpenStreetMap: how many, how long,
/// from where to where.
struct ResortFacts: View {
    let terrain: Terrain

    /// The lowest and the highest end of a line, when the altitudes are known.
    static func altitudes(_ terrain: Terrain) -> (base: Double, top: Double)? {
        let ends = terrain.ways.flatMap { [$0.startAlt, $0.endAlt].compactMap { $0 } }
        guard let low = ends.min(), let high = ends.max(), high > low else { return nil }
        return (low, high)
    }

    var body: some View {
        let range = Self.altitudes(terrain)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                if let range {
                    Fact(value: Fmt.height(range.top - range.base), label: "Dislivello", symbol: "arrow.down")
                }
                Fact(value: "\(terrain.pistes)", label: "Piste", symbol: "number")
                Fact(value: "\(terrain.lifts)", label: "Impianti", symbol: "cablecar")
                Fact(value: Fmt.distance(terrain.pisteMeters), label: "Di piste", symbol: "arrow.right")
                if let range {
                    Fact(value: Fmt.height(range.base), label: "Quota base", symbol: "triangle")
                    Fact(value: Fmt.height(range.top), label: "Quota vetta", symbol: "mountain.2")
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

private struct Fact: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.display(.title3)).monospacedDigit().foregroundStyle(Theme.text).lineLimit(1)
            Label(LocalizedStringKey(label), systemImage: symbol).font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The snow of today at a ski area: fallen last night and during the day, the sky and the cold
/// stretch by stretch, the snow of the last week and the wind when it blows.
struct TodayPanel: View {
    let now: SnowNow

    var body: some View {
        Panel("Oggi") {
            HStack(alignment: .top, spacing: 10) {
                amount(now.overnight, "Stanotte")
                Text("+").font(.title3).foregroundStyle(Theme.sub).padding(.top, 2)
                amount(now.daytime, "Di giorno")
                Text("=").font(.title3).foregroundStyle(Theme.sub).padding(.top, 2)
                amount(now.today, "In tutto", strong: true)
            }
            if !now.blocks.isEmpty {
                HStack(spacing: 8) {
                    ForEach(now.blocks) { block in
                        VStack(spacing: 6) {
                            Text(block.label).font(.caption2).foregroundStyle(Theme.sub).lineLimit(1)
                            Image(systemName: block.symbol).font(.body).foregroundStyle(Theme.accent).frame(height: 22)
                            Text(Fmt.temperature(block.tempMin)).font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.text)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Image(systemName: "wind").font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(block.windy ? Theme.warn : .clear)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.deep.opacity(0.6), in: Theme.roundSmall)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if now.lastWeek >= 0.5 {
                banner("snowflake", String(localized: "\(Fmt.snow(now.lastWeek)) negli ultimi 7 giorni"), Theme.good)
            }
            if now.gustMax >= 40 {
                banner("wind", String(localized: "Raffiche fino a \(Fmt.wind(now.gustMax))"), Theme.warn)
            }
        }
    }

    private func amount(_ cm: Double, _ label: String, strong: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Fmt.snow(cm)).font(.display(.title3)).monospacedDigit().foregroundStyle(strong && cm >= 0.5 ? Theme.accent : Theme.text)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(LocalizedStringKey(label)).font(.caption).foregroundStyle(Theme.sub).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func banner(_ symbol: String, _ text: String, _ color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.16), in: Capsule())
    }
}

/// The buttons of a ski area's page: its map, and keeping its pistes on the iPhone.
struct ResortMapButtons: View {
    let resort: Resort
    let terrain: Terrain?
    @State private var store = Terrains.shared
    @State private var error: String?

    var body: some View {
        let kept = store.isSaved(resort.id)
        VStack(spacing: 10) {
            ErrorBanner(error: $error)
            HStack(spacing: 10) {
                NavigationLink {
                    ExploreView(name: resort.name, center: resort.coordinate)
                } label: { Label("Mappa", systemImage: "map.fill") }
                    .buttonStyle(PrimaryButtonStyle())
                Button {
                    if kept {
                        store.remove(resort.id)
                    } else if let terrain {
                        do {
                            try store.save(terrain, id: resort.id, name: resort.name, lat: resort.lat, lon: resort.lon)
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                } label: {
                    Label(LocalizedStringKey(kept ? "Scaricata" : "Scarica"), systemImage: kept ? "checkmark.circle.fill" : "arrow.down.circle")
                }
                .buttonStyle(SecondaryButtonStyle(color: kept ? Theme.good : Theme.text))
                .disabled(!kept && (terrain == nil || terrain?.ways.isEmpty == true))
                .sensoryFeedback(.success, trigger: kept)
            }
            if kept {
                Text("Piste, impianti e rifugi sono su questo iPhone: la mappa e i percorsi funzionano anche senza campo. Tocca di nuovo per toglierla.")
                    .prose().font(.caption).foregroundStyle(Theme.sub)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The ski areas kept on the iPhone, in Settings: to see them and to take them off.
struct SavedMapsPanel: View {
    @State private var store = Terrains.shared

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    var body: some View {
        Panel("Mappe scaricate") {
            if store.saved.isEmpty {
                Text("Nessuna. Dalla pagina di una stazione, in Guida, tocca Scarica: piste, impianti e rifugi restano sull'iPhone e la mappa funziona anche senza campo.")
                    .prose().font(.caption).foregroundStyle(Theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(store.saved) { map in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(map.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        Text("\(map.pistes) piste · \(map.lifts) impianti · \(Self.day.string(from: map.date))")
                            .font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Button(role: .destructive) { store.remove(map.id) } label: {
                        Image(systemName: "trash").foregroundStyle(Theme.bad).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(Text("Elimina"))
                }
            }
        }
    }
}
