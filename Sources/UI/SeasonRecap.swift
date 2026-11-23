import SwiftUI
import UIKit

/// The numbers of a season worth telling: what the picture to share is made of.
struct SeasonRecap {
    /// "2026/27", or the words for every season together.
    let label: String
    let days: Int
    let runs: Int
    let vertical: Double
    let distance: Double
    let maxSpeed: Double
    /// Seconds on the snow, lifts included.
    let time: Double
    /// How many different places.
    let places: Int
    /// The day with the most vertical.
    let best: DaySummary?

    init(label: String, days list: [DaySummary]) {
        self.label = label
        days = list.count
        runs = list.reduce(0) { $0 + $1.stats.runs }
        vertical = list.reduce(0) { $0 + $1.stats.vertical }
        distance = list.reduce(0) { $0 + $1.stats.runDistance }
        maxSpeed = list.map(\.stats.maxSpeed).max() ?? 0
        time = list.reduce(0) { $0 + $1.stats.totalTime }
        places = Set(list.compactMap { $0.title?.lowercased() }).count
        best = list.max { $0.stats.vertical < $1.stats.vertical }
    }

    /// How many times the height of Everest was skied down.
    var everests: Double { vertical / 8849 }
}

/// The picture of a season: its numbers big, in the colors of the app.
struct SeasonCard: View {
    let recap: SeasonRecap

    static let size = CGSize(width: 360, height: 560)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LA MIA STAGIONE").font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(1.5).foregroundStyle(Theme.accent)
            Text(recap.label).font(.system(size: 44, weight: .bold, design: .monospaced)).foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.6)
            Spacer(minLength: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(Fmt.height(recap.vertical)).font(.system(size: 46, weight: .bold, design: .monospaced)).foregroundStyle(Theme.accent)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text("di dislivello sciato").font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(Theme.sub)
                if recap.everests >= 0.5 {
                    Text("\(recap.everests.formatted(.number.precision(.fractionLength(1)))) volte l'Everest")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.text)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 14)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 14) {
                figure("\(recap.days)", "Giornate")
                figure("\(recap.runs)", "Discese")
                figure(Fmt.distance(recap.distance), "Sciati")
                figure(Fmt.speed(recap.maxSpeed), "Velocità max")
                figure(Fmt.duration(recap.time), "Sulla neve")
                figure("\(recap.places)", "Posti")
            }
            if let best = recap.best, best.stats.vertical > 0 {
                Spacer(minLength: 14)
                Text("LA GIORNATA MIGLIORE").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1).foregroundStyle(Theme.sub)
                Text("\(best.title ?? Fmt.dayShort(best.start)) · \(Fmt.height(best.stats.vertical))")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.text)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 14)
            HStack {
                Text("SKI APEX").font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(1.5).foregroundStyle(Theme.accent)
                Spacer()
                Image(systemName: "figure.skiing.downhill").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent)
            }
        }
        .padding(24)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(LinearGradient(colors: [Theme.sky, Theme.bg, Theme.deep], startPoint: .top, endPoint: .bottom))
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 20, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(LocalizedStringKey(label)).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Theme.sub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The picture of the season, shown before it is sent.
struct SeasonSheet: View {
    let recap: SeasonRecap
    @Environment(\.dismiss) private var dismiss
    @State private var file: URL?
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Spacer(minLength: 0)
                if let image {
                    Image(uiImage: image)
                        .resizable().scaledToFit()
                        .clipShape(Theme.round)
                        .overlay(Theme.round.strokeBorder(Theme.line, lineWidth: 1))
                        .shadow(color: .black.opacity(0.4), radius: 18, y: 10)
                        .accessibilityLabel(Text("Immagine con i numeri della stagione"))
                } else {
                    ProgressView()
                }
                Spacer(minLength: 0)
                if let file, let image {
                    ShareLink(item: file, preview: SharePreview("Ski Apex \(recap.label)", image: Image(uiImage: image))) {
                        Label("Condividi", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("La mia stagione")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Chiudi") { dismiss() } }
            }
            .task { render() }
        }
        .modifier(Dressed())
    }

    @MainActor private func render() {
        let renderer = ImageRenderer(content: SeasonCard(recap: recap).environment(\.colorScheme, Theme.dark ? .dark : .light))
        renderer.scale = 3
        guard let made = renderer.uiImage, let data = made.pngData() else { return }
        image = made
        let name = recap.label.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ski Apex \(name).png")
        try? data.write(to: url, options: .atomic)
        file = url
    }
}
