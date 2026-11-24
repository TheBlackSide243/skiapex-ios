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
            Text("LA MIA STAGIONE").font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(1.5).foregroundStyle(Theme.accent)
            Text(recap.label).font(.system(size: 46, weight: .heavy, design: .rounded)).foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.6)
            Spacer(minLength: 14)
            VStack(alignment: .leading, spacing: 2) {
                FigureText(Fmt.height(recap.vertical), big: .system(size: 50, weight: .heavy, design: .rounded),
                           small: .system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text("di dislivello sciato").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(Theme.sub)
                if recap.everests >= 0.5 {
                    Text("\(recap.everests.formatted(.number.precision(.fractionLength(1)))) volte l'Everest")
                        .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 14)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 16) {
                CardFigure(value: "\(recap.days)", label: "Giornate", size: 22)
                CardFigure(value: "\(recap.runs)", label: "Discese", size: 22)
                CardFigure(value: Fmt.distance(recap.distance), label: "Sciati", size: 22)
                CardFigure(value: Fmt.speed(recap.maxSpeed), label: "Velocità max", size: 22)
                CardFigure(value: Fmt.duration(recap.time), label: "Sulla neve", size: 22)
                CardFigure(value: "\(recap.places)", label: "Posti", size: 22)
            }
            if let best = recap.best, best.stats.vertical > 0 {
                Spacer(minLength: 14)
                Text("LA GIORNATA MIGLIORE").font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(1).foregroundStyle(Theme.sub)
                Text("\(best.title ?? Fmt.dayShort(best.start)) · \(Fmt.height(best.stats.vertical))")
                    .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if let legs = best.shape, legs.count > 1 {
                    DayProfile(legs: legs, lineWidth: 2).frame(height: 34).padding(.top, 8)
                }
            }
            Spacer(minLength: 14)
            Rectangle().fill(Theme.line).frame(height: 1)
            CardFoot().padding(.top, 12)
        }
        .padding(24)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(
            LinearGradient(stops: [.init(color: Theme.sky, location: 0), .init(color: Theme.bg, location: 0.5), .init(color: Theme.deep, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        )
        .fontDesign(.rounded)
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
