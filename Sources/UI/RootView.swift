import MapKit
import SwiftUI

/// Five tabs: the day under way, the diary (with the numbers), the guide to the ski areas, the
/// friends, the settings.
struct RootView: View {
    @Environment(Social.self) private var social
    @AppStorage(Prefs.units) private var units = Units.metric.rawValue
    @State private var tab = Demo.tab

    var body: some View {
        TabView(selection: $tab) {
            LiveView()
                .tabItem { Label("Registra", systemImage: "figure.skiing.downhill") }
                .tag(0)
            DaysView()
                .tabItem { Label("Giornate", systemImage: "book") }
                .tag(1)
            GuideView()
                .tabItem { Label("Guida", systemImage: "map") }
                .tag(2)
            FriendsView()
                .tabItem { Label("Amici", systemImage: "person.2") }
                .tag(3)
            SettingsView()
                .tabItem { Label("Impostazioni", systemImage: "gearshape") }
                .tag(4)
        }
        // Every number again in the new units, every color again in the new look.
        .id(units + Looks.shared.look.rawValue)
        .sensoryFeedback(.selection, trigger: tab)
        .onOpenURL { url in
            guard url.scheme == "skiapex" else { return }
            switch url.host {
            case "friend":
                // skiapex://friend/<code>: an invitation, from the page of its link.
                if let code = url.pathComponents.last, code.count == 8 { social.pendingCode = code.uppercased() }
            case "record":
                // From the widget: ready to start.
                tab = 0
            case "guide":
                tab = 2
            default:
                break
            }
        }
        // An invitation opened from its link goes to the friends.
        .onChange(of: social.pendingCode) { _, code in
            if code != nil { tab = 3 }
        }
    }
}

/// The lines of a day on a map: each run in its color (or all in the accent), the lifts dashed,
/// the time between thin.
struct TrackMapContent: MapContent {
    let tracks: [MapTrack]
    /// The one run to show, the others faded.
    var highlight: Int?
    var colorful = true
    /// Everything faded, under something else drawn on top.
    var dimmed = false

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
        if dimmed { return base.opacity(0.25) }
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

/// The color of a piste as on the signs, with its name for VoiceOver.
struct DifficultyDot: View {
    let difficulty: String?
    var size: CGFloat = 10

    var body: some View {
        if let color = Theme.difficultyColor(difficulty), let label = Theme.difficultyLabel(difficulty) {
            Circle().fill(color)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.75), lineWidth: 1))
                .frame(width: size, height: size)
                .accessibilityLabel(Text(LocalizedStringKey(label)))
        }
    }
}

/// A small pill with a symbol and a few words.
struct Chip: View {
    let symbol: String
    let text: String
    var color: Color = Theme.sub

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.caption2.weight(.semibold)).foregroundStyle(color)
            Text(text).font(.caption).foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.input, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
    }
}
