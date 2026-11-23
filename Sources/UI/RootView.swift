import MapKit
import SwiftUI

/// Three tabs: the day under way, the days saved, the settings.
struct RootView: View {
    @AppStorage(Prefs.units) private var units = Units.metric.rawValue
    @State private var tab = ProcessInfo.processInfo.arguments.contains("-days") ? 1 : 0

    var body: some View {
        TabView(selection: $tab) {
            LiveView()
                .tabItem { Label("Registra", systemImage: "figure.skiing.downhill") }
                .tag(0)
            DaysView()
                .tabItem { Label("Giornate", systemImage: "calendar") }
                .tag(1)
            SettingsView()
                .tabItem { Label("Impostazioni", systemImage: "gearshape") }
                .tag(2)
        }
        // Every number again in the new units.
        .id(units)
        .sensoryFeedback(.selection, trigger: tab)
    }
}

/// The lines of a day on a map: each run in its color (or all in the accent), the lifts dashed,
/// the time between thin.
struct TrackMapContent: MapContent {
    let tracks: [MapTrack]
    /// The one run to show, the others faded.
    var highlight: Int?
    var colorful = true

    var body: some MapContent {
        ForEach(tracks) { track in
            MapPolyline(coordinates: track.coordinates)
                .stroke(color(track), style: style(track))
        }
    }

    private func color(_ track: MapTrack) -> Color {
        let base: Color
        switch track.kind {
        case .run: base = colorful ? Theme.runColor(track.number) : Theme.accent
        case .lift: base = Theme.lift
        case .idle: base = Theme.sub
        }
        if let highlight, highlight != track.id { return base.opacity(0.25) }
        return base
    }

    private func style(_ track: MapTrack) -> StrokeStyle {
        switch track.kind {
        case .run: StrokeStyle(lineWidth: highlight == track.id ? 6 : 4, lineCap: .round, lineJoin: .round)
        case .lift: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [6, 6])
        case .idle: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        }
    }
}

/// A round button on glass, over the map.
struct MapButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 44, height: 44)
                .glass(in: Circle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(Text(LocalizedStringKey(label)))
    }
}
