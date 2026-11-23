import MapKit
import SwiftUI

/// Every run of every day in one place, one over the other: where the lines are brightest is
/// where you ski most, and what stays dark is still to be tried.
struct HeatmapView: View {
    @Environment(Library.self) private var library
    @State private var lines: [HeatLine] = []
    @State private var loading = true
    @State private var chosen: String?
    @State private var camera: MapCameraPosition = .automatic

    struct HeatLine: Identifiable {
        let id: Int
        let coordinates: [CLLocationCoordinate2D]
    }

    /// The places with a track, the latest first, each with its days.
    private var places: [(name: String, days: [DaySummary])] {
        var order: [String] = []
        var groups: [String: [DaySummary]] = [:]
        for day in library.days where day.lat != nil {
            let name = day.title ?? String(localized: "Giornata sulla neve")
            if groups[name] == nil { order.append(name) }
            groups[name, default: []].append(day)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        let all = places
        let current = all.first { $0.name == chosen } ?? all.first
        ZStack(alignment: .bottom) {
            Map(position: $camera) {
                ForEach(lines) { line in
                    MapPolyline(coordinates: line.coordinates)
                        .stroke(Theme.runColors[1].opacity(0.34), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
            }
            .mapStyle(.imagery(elevation: .realistic))
            .ignoresSafeArea(edges: .bottom)

            VStack(alignment: .leading, spacing: 10) {
                if all.isEmpty {
                    Text("La mappa di calore si riempie con le giornate registrate.")
                        .prose().font(.subheadline).foregroundStyle(Theme.sub)
                } else if let current {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(current.name).font(.display(.headline)).foregroundStyle(Theme.text).lineLimit(1)
                            Text("\(current.days.count) giornate · \(current.days.reduce(0) { $0 + $1.stats.runs }) discese")
                                .font(.caption).foregroundStyle(Theme.sub)
                        }
                        Spacer()
                        if loading { ProgressView().controlSize(.small) }
                        if all.count > 1 {
                            Menu {
                                ForEach(all, id: \.name) { place in
                                    Button(place.name) { chosen = place.name }
                                }
                            } label: {
                                Label("Cambia posto", systemImage: "chevron.up.chevron.down")
                                    .labelStyle(.iconOnly)
                                    .font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                                    .frame(width: 44, height: 44)
                                    .background(Theme.input.opacity(0.6), in: Circle())
                            }
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass()
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .navigationTitle("Mappa di calore")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: current?.name) {
            await load(current?.days ?? [])
        }
    }

    /// The runs of the days of one place, each as a line of at most a hundred points.
    private func load(_ days: [DaySummary]) async {
        loading = true
        let library = library
        let ids = days.prefix(60).map(\.id)
        let made = await Task.detached(priority: .userInitiated) { () -> [HeatLine] in
            var out: [HeatLine] = []
            for id in ids {
                guard let day = library.day(id) else { continue }
                for run in day.runs where run.end < day.points.count && run.start < run.end {
                    let step = max(1, (run.end - run.start) / 100)
                    let coordinates = stride(from: run.start, through: run.end, by: step).map { day.points[$0].coordinate }
                    out.append(HeatLine(id: out.count, coordinates: coordinates))
                }
            }
            return out
        }.value
        lines = made
        loading = false
        withAnimation { camera = .automatic }
    }
}
