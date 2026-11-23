import SwiftUI
import UniformTypeIdentifiers

/// The days saved, newest first, with the numbers of the season on top.
struct DaysView: View {
    @Environment(Library.self) private var library
    @State private var season: Season?
    @State private var path: [UUID] = []
    @State private var importing = false
    @State private var error: String?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 14) {
                    ErrorBanner(error: $error)
                    if library.days.isEmpty {
                        empty
                    } else {
                        if library.seasons.count > 1 { seasonPicker }
                        totals
                        ForEach(shown) { day in
                            NavigationLink(value: day.id) { DayCard(day: day) }
                                .buttonStyle(PressStyle())
                        }
                    }
                }
                .padding(16)
            }
            .screen()
            .navigationTitle("Giornate")
            .navigationDestination(for: UUID.self) { DayDetailView(id: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { importing = true } label: { Label("Importa GPX", systemImage: "square.and.arrow.down") }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml, .xml],
                          allowsMultipleSelection: true) { result in
                bring(result)
            }
            .onAppear {
                if season == nil { season = library.seasons.first }
                // The screenshots of a day open the newest one.
                let inside = ["day", "timeline", "run", "replay", "share"]
                if inside.contains(Demo.screen ?? ""), path.isEmpty, let first = library.days.first { path = [first.id] }
            }
        }
    }

    /// The files chosen become days; the last one is opened.
    private func bring(_ result: Result<[URL], Error>) {
        do {
            var last: UUID?
            for url in try result.get() {
                let id = try library.importGPX(url)
                last = id
                Task { await library.enrich(id) }
            }
            season = nil
            if let last { path = [last] }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private var current: Season? { season ?? library.seasons.first }
    private var shown: [DaySummary] { library.days(in: current) }

    private var seasonPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(library.seasons) { s in
                    let on = s == current
                    Button { withAnimation(.snappy) { season = s } } label: {
                        Text(s.label).font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .foregroundStyle(on ? Theme.onAccent : Theme.text)
                            .background(on ? Theme.accent : Theme.input, in: Capsule())
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
    }

    private var totals: some View {
        let days = shown
        let s = days.map(\.stats)
        let label = current?.label ?? ""
        return VStack(alignment: .leading, spacing: 12) {
            Text("STAGIONE \(label)").font(.caption.weight(.bold)).foregroundStyle(Theme.sub)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                StatTile(value: "\(days.count)", label: "Giornate", symbol: "calendar")
                StatTile(value: "\(s.reduce(0) { $0 + $1.runs })", label: "Discese", symbol: "figure.skiing.downhill")
                StatTile(value: Fmt.height(s.reduce(0) { $0 + $1.vertical }), label: "Dislivello", symbol: "arrow.down.right")
                StatTile(value: Fmt.distance(s.reduce(0) { $0 + $1.runDistance }), label: "Sciati", symbol: "point.topleft.down.to.point.bottomright.curvepath")
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "figure.skiing.downhill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 84, height: 84)
                .iconBox()
            Text("Ancora nessuna giornata").font(.display(.headline)).foregroundStyle(Theme.text)
            Text("Registra una giornata dalla scheda Registra, o importa un file GPX con il pulsante in alto. Per vedere com'è, in Impostazioni puoi crearne una di prova.")
                .prose().font(.subheadline).foregroundStyle(Theme.sub).multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .card()
        .padding(.top, 40)
    }
}

/// One day in the list.
struct DayCard: View {
    let day: DaySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(day.title ?? String(localized: "Giornata sulla neve"))
                        .font(.display(.headline)).foregroundStyle(Theme.text).lineLimit(1)
                    HStack(spacing: 6) {
                        Image(systemName: (day.sport ?? .ski).symbol).font(.caption2).foregroundStyle(Theme.accent)
                            .accessibilityLabel(Text(LocalizedStringKey((day.sport ?? .ski).label)))
                        Text(Fmt.day(day.start).capitalized).font(.caption).foregroundStyle(Theme.sub)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.sub)
            }
            HStack(spacing: 0) {
                figure("\(day.stats.runs)", "discese")
                figure(Fmt.height(day.stats.vertical), "dislivello")
                figure(Fmt.speedValue(day.stats.maxSpeed), "max \(Fmt.speedUnit)")
                figure(Fmt.distance(day.stats.runDistance), "sciati")
            }
        }
        .padding(16)
        .card()
        .contentShape(Rectangle())
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.accent)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(LocalizedStringKey(label)).font(.caption2).foregroundStyle(Theme.sub).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
