import MapKit
import SwiftUI

/// The map behind everything and, over it, a sheet with the screen chosen: the day under way,
/// the diary (with the numbers), the guide to the ski areas, the friends, the settings. The sheet
/// is pulled up and down; on its right edge are the picture that opens the settings, the three
/// screens to move between and the button that records.
struct RootView: View {
    @Environment(Social.self) private var social
    @State private var tab = Demo.tab
    @State private var detent = Demo.detent
    @State private var recenter = 0

    /// How high the sheet can stand: low, to look at the map, in the middle, and all the way up.
    static let low = PresentationDetent.fraction(0.42)
    static let middle = PresentationDetent.fraction(0.68)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Backdrop(tab: tab, covered: detent == Self.low ? 0.42 : 0.68, recenter: recenter)
                .ignoresSafeArea()
            MapButton(symbol: "location.fill", label: "Dove sono") { recenter += 1 }
                .padding(.trailing, 16)
                .padding(.top, 8)
        }
        .sheet(isPresented: .constant(true)) {
            SheetRoot(tab: $tab)
                .presentationDetents([Self.low, Self.middle, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: Self.middle))
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(36)
                .presentationBackground(Theme.bg)
                .interactiveDismissDisabled()
        }
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
    }
}

/// What is on the sheet: the screen chosen, and on its right edge the way to the others.
private struct SheetRoot: View {
    @Binding var tab: Int
    @Environment(Social.self) private var social
    @Environment(Library.self) private var library
    @AppStorage(Prefs.units) private var units = Units.metric.rawValue
    /// The day just ended, to ask how the snow was.
    @State private var asked: AskedDay?

    var body: some View {
        GeometryReader { box in
            // Where the screen keeps something of its own on the right edge (the clock and the
            // battery of an iPhone that opens), nothing of a screen may go there: the buttons do,
            // lower down, and the screens take all the rest.
            let band = box.safeAreaInsets.trailing
            Group {
                switch tab {
                case 0: LiveView()
                case 2: GuideView()
                case 3: FriendsView()
                case 4: SettingsView()
                default: DaysView()
                }
            }
            // The right edge is kept free for the buttons, and the bottom can be scrolled clear of them.
            .environment(\.railInset, Rail.reserved(band: band))
            .environment(\.railFoot, Rail.foot)
            // Every number again in the new units, every color again in the new look.
            .id("\(tab)" + units + Looks.shared.look.rawValue)
            .overlay(alignment: .bottomTrailing) {
                if Chrome.shared.hidden == 0 {
                    Rail(tab: $tab, band: band).offset(x: band)
                }
            }
        }
        // For the pictures: a band on the right edge, as on the iPhones that have one.
        .safeAreaPadding(.trailing, Demo.band)
        .modifier(Dressed())
        .sensoryFeedback(.selection, trigger: tab)
        // A day ended, here or on the watch: how was the snow?
        .onChange(of: library.asking, initial: true) { _, id in
            if let id { asked = AskedDay(id: id) }
        }
        .sheet(item: $asked, onDismiss: { library.ask(nil) }) { SnowSheet(id: $0.id) }
        // An invitation opened from its link goes to the friends.
        .onChange(of: social.pendingCode) { _, code in
            if code != nil { tab = 3 }
        }
    }
}

/// On the right edge of the sheet, at the bottom: your picture, which opens the settings, and the
/// three screens, each a round button, one over the other; beside them the button that records,
/// white with a red dot as on a camera.
struct Rail: View {
    @Binding var tab: Int
    /// How wide the band is that the screen keeps free on its right edge: 0 on most iPhones.
    var band: CGFloat = 0
    @Environment(Recorder.self) private var recorder
    @Environment(Social.self) private var social

    /// The width of the column of buttons.
    static let width: CGFloat = 64
    /// How much of the bottom of a screen the round button covers: it can be scrolled clear of it.
    static let foot: CGFloat = 84
    /// The red of what records.
    static let red = Color(hex: 0xff453a)

    /// How much of the right edge of a screen the column takes: all of its width, less the band
    /// the screen already leaves free there.
    static func reserved(band: CGFloat) -> CGFloat { max(0, width - band) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            record
            VStack(spacing: 8) {
                profile
                item(1, "calendar", "Giornate")
                item(2, "mountain.2.fill", "Guida")
                item(3, "person.2.fill", "Amici")
            }
            // In the middle of the column, or of the band when it is wider.
            .frame(width: max(Self.width, band))
        }
        .padding(.bottom, 6)
    }

    /// The button that records: a red dot while nothing is recorded, then what the day is doing.
    private var record: some View {
        Button { tab = 0 } label: {
            ZStack {
                Circle().fill(Color.white)
                switch recorder.state {
                case .idle:
                    Circle().fill(Self.red).frame(width: 26, height: 26)
                case .recording:
                    Image(systemName: "figure.skiing.downhill").font(.system(size: 27, weight: .semibold)).foregroundStyle(Self.red)
                case .paused:
                    Image(systemName: "pause.fill").font(.system(size: 24, weight: .semibold)).foregroundStyle(Self.red)
                }
            }
            .frame(width: 66, height: 66)
            .overlay(Circle().strokeBorder(tab == 0 ? Theme.accent : Color.black.opacity(0.1), lineWidth: tab == 0 ? 3.5 : 1))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(Text("Registra"))
    }

    /// Your picture: it opens the settings, with the profile at the top.
    private var profile: some View {
        Button { tab = 4 } label: {
            Group {
                if let me = social.account {
                    Avatar(id: me.id, name: me.name, photo: me.photo, size: 50)
                } else {
                    Image(systemName: "person.fill").font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                        .frame(width: 50, height: 50)
                        .background(Theme.input, in: Circle())
                }
            }
            .overlay(Circle().strokeBorder(tab == 4 ? Theme.accent : Color.white.opacity(0.18), lineWidth: 2))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(Text("Impostazioni"))
    }

    private func item(_ index: Int, _ symbol: String, _ label: String) -> some View {
        Button { tab = index } label: {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tab == index ? Theme.onAccent : Theme.text)
                .frame(width: 50, height: 50)
                .background(tab == index ? Theme.accent : Theme.input, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(tab == index ? 0 : 0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(Text(LocalizedStringKey(label)))
        .accessibilityAddTraits(tab == index ? .isSelected : [])
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
        case .run: base = colorful ? Theme.runColor(track.number) : Theme.track
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
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.input, in: Capsule())
    }
}
