import Observation
import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

/// The colors of one look of the app.
struct Palette {
    /// A dark look, with light words: the bars and the maps of iOS follow it.
    let dark: Bool
    let bg: Color
    let panel: Color
    let deep: Color
    let input: Color
    let line: Color
    let text: Color
    let sub: Color
    /// What you can do, and the runs on the map.
    let accent: Color
    let onAccent: Color
    /// The lifts on the map and in the charts.
    let lift: Color
    let good: Color
    let bad: Color
    let warn: Color
    /// The top of the picture to share: the sky over the page.
    let sky: Color
}

/// The looks to choose from in Settings. Each has an icon of the app in its colors.
enum Look: String, CaseIterable, Identifiable {
    case night, aurora, sunrise, forest, carbon, snow

    var id: String { rawValue }

    var label: String {
        switch self {
        case .night: "Notte"
        case .aurora: "Aurora"
        case .sunrise: "Alba"
        case .forest: "Bosco"
        case .carbon: "Carbone"
        case .snow: "Neve"
        }
    }

    /// The icon of the app in these colors, as iOS knows it: nil for the one the app comes with.
    var iconName: String? {
        switch self {
        case .night: nil
        case .aurora: "AppIcon-Aurora"
        case .sunrise: "AppIcon-Alba"
        case .forest: "AppIcon-Bosco"
        case .carbon: "AppIcon-Carbone"
        case .snow: "AppIcon-Neve"
        }
    }

    /// The look whose icon is on the Home Screen now.
    static var iconInUse: Look {
        let name = UIApplication.shared.alternateIconName
        return allCases.first { $0.iconName == name } ?? .night
    }

    /// The same icon as a picture, to show it in Settings.
    var iconPreview: String { "IconPreview-\(rawValue)" }

    var palette: Palette {
        switch self {
        case .night: Self.nightColors
        case .aurora: Self.auroraColors
        case .sunrise: Self.sunriseColors
        case .forest: Self.forestColors
        case .carbon: Self.carbonColors
        case .snow: Self.snowColors
        }
    }

    private static func darkLook(bg: UInt32, panel: UInt32, deep: UInt32, input: UInt32, text: UInt32, sub: UInt32,
                                 accent: UInt32, onAccent: UInt32, lift: UInt32, sky: UInt32) -> Palette {
        Palette(dark: true, bg: Color(hex: bg), panel: Color(hex: panel), deep: Color(hex: deep), input: Color(hex: input),
                line: Color.white.opacity(0.09), text: Color(hex: text), sub: Color(hex: sub), accent: Color(hex: accent),
                onAccent: Color(hex: onAccent), lift: Color(hex: lift), good: Color(hex: 0x34d399), bad: Color(hex: 0xff7b8a),
                warn: Color(hex: 0xfbbf24), sky: Color(hex: sky))
    }

    /// The night over the mountain: grey panels on a sheet that fades from the blue of a glacier
    /// in the shade, and the light blue of the ice (the line on the icon of the app) for what you
    /// can do, with dark words on it.
    private static let nightColors = darkLook(bg: 0x191b20, panel: 0x292b30, deep: 0x1f2126, input: 0x34373e, text: 0xffffff,
                                              sub: 0xa2a7b1, accent: 0x5ccfff, onAccent: 0x06202e, lift: 0xc4b5fd, sky: 0x23455c)
    /// Northern lights: dark teal and mint.
    private static let auroraColors = darkLook(bg: 0x171c1d, panel: 0x272d2e, deep: 0x1d2324, input: 0x343c3d, text: 0xffffff,
                                               sub: 0xa0abab, accent: 0x4fdcc6, onAccent: 0x04201c, lift: 0xd8b4fe, sky: 0x2c4f52)
    /// The first light on the peaks: plum and peach.
    private static let sunriseColors = darkLook(bg: 0x1d1a1e, panel: 0x2e2a30, deep: 0x242026, input: 0x3c363e, text: 0xffffff,
                                                sub: 0xaea4ac, accent: 0xff9f6b, onAccent: 0x2a1206, lift: 0xf9a8d4, sky: 0x5a3950)
    /// Among the firs: dark green and lime.
    private static let forestColors = darkLook(bg: 0x191c19, panel: 0x292d29, deep: 0x1f231f, input: 0x363b36, text: 0xffffff,
                                               sub: 0xa3aba3, accent: 0xa3e635, onAccent: 0x0f1f04, lift: 0x7dd3fc, sky: 0x33503a)
    /// Black, for the screens that turn their pixels off, and the yellow of the piste poles.
    private static let carbonColors = darkLook(bg: 0x000000, panel: 0x1c1c1e, deep: 0x111113, input: 0x2c2c2e, text: 0xffffff,
                                               sub: 0x9a9aa2, accent: 0xffd60a, onAccent: 0x1a1500, lift: 0xc4b5fd, sky: 0x1c1c1f)
    /// A light look, for the sun on the snow.
    private static let snowColors = Palette(
        dark: false, bg: Color(hex: 0xf1f5fa), panel: Color(hex: 0xffffff), deep: Color(hex: 0xe3eaf2), input: Color(hex: 0xe8eef6),
        line: Color.black.opacity(0.10), text: Color(hex: 0x0f1b2d), sub: Color(hex: 0x5b6b80), accent: Color(hex: 0x0a84c6),
        onAccent: Color(hex: 0xffffff), lift: Color(hex: 0x7c5cd6), good: Color(hex: 0x0e9f6e), bad: Color(hex: 0xd43f52),
        warn: Color(hex: 0xb7791f), sky: Color(hex: 0xcfe2f4))
}

/// The look in use: one for the whole app, remembered between launches.
@Observable final class Looks {
    static let shared = Looks()

    private(set) var look: Look

    private init() {
        look = Look(rawValue: UserDefaults.standard.string(forKey: Prefs.theme) ?? "") ?? .night
    }

    func choose(_ new: Look) {
        guard new != look else { return }
        look = new
        UserDefaults.standard.set(new.rawValue, forKey: Prefs.theme)
    }
}

/// The look of Ski Apex: the map behind everything and a sheet over it, in the colors chosen in
/// Settings (see `Look`). Cards are grey with very round corners and no outline; what floats on
/// the map is glass (the Liquid Glass of iOS 26 and later, a frosted material before); the things
/// you press are pills. Everything is set in the round face of the system: titles heavy, numbers
/// bold with their unit small beside them.
enum Theme {
    private static var colors: Palette { Looks.shared.look.palette }

    static var dark: Bool { colors.dark }
    static var bg: Color { colors.bg }
    static var panel: Color { colors.panel }
    static var deep: Color { colors.deep }
    static var input: Color { colors.input }
    static var line: Color { colors.line }
    static var text: Color { colors.text }
    static var sub: Color { colors.sub }
    static var accent: Color { colors.accent }
    static var onAccent: Color { colors.onAccent }
    static var lift: Color { colors.lift }
    static var good: Color { colors.good }
    static var bad: Color { colors.bad }
    static var warn: Color { colors.warn }
    static var sky: Color { colors.sky }

    /// Each run of a day in its own color on the map, in turn.
    static let runColors: [Color] = ([0x5ccfff, 0xff8a4c, 0x34d399, 0xf472b6, 0xfbbf24, 0xa78bfa, 0x22d3ee, 0xfb7185] as [UInt32]).map { Color(hex: $0) }
    static func runColor(_ number: Int) -> Color { runColors[max(0, number - 1) % runColors.count] }

    /// The color of a piste on the signs: green, blue, red, black; yellow off piste.
    static func difficultyColor(_ difficulty: String?) -> Color? {
        switch difficulty {
        case "novice": Color(hex: 0x34d399)
        case "easy": Color(hex: 0x4f9dff)
        case "intermediate": Color(hex: 0xf2555a)
        case "advanced", "expert": Color(hex: 0x0a0d12)
        case "freeride", "extreme": Color(hex: 0xfbbf24)
        default: nil
        }
    }

    static func difficultyLabel(_ difficulty: String?) -> String? {
        switch difficulty {
        case "novice": "Principianti"
        case "easy": "Facile"
        case "intermediate": "Media"
        case "advanced": "Difficile"
        case "expert": "Esperti"
        case "freeride", "extreme": "Fuoripista"
        default: nil
        }
    }

    /// From slow to fast, for the speed drawn along a run.
    static let speedColors: [Color] = ([0x4f9dff, 0x34d399, 0xfbbf24, 0xff8a4c, 0xf2555a] as [UInt32]).map { Color(hex: $0) }

    static let round = RoundedRectangle(cornerRadius: 28, style: .continuous)
    static let roundSmall = RoundedRectangle(cornerRadius: 16, style: .continuous)

    /// The line of a day on the map: a color no piste has.
    static let track = Color(hex: 0xa23bf0)

    /// The round face of the app in the bars too, which are not SwiftUI's to dress: the titles of
    /// the screens and the segmented pickers. Called once, before the first screen.
    @MainActor static func dressBars() {
        func round(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let plain = UIFont.systemFont(ofSize: size, weight: weight)
            return plain.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? plain
        }
        UISegmentedControl.appearance().setTitleTextAttributes([.font: round(13, .semibold)], for: .normal)
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: round(UIFont.preferredFont(forTextStyle: .largeTitle).pointSize, .heavy)]
        UINavigationBar.appearance().titleTextAttributes = [.font: round(UIFont.preferredFont(forTextStyle: .headline).pointSize, .bold)]
    }
}

extension Font {
    /// The big words and numbers of a screen.
    static func display(_ style: Font.TextStyle) -> Font {
        .system(style, design: .rounded, weight: .bold)
    }
}

extension View {
    /// A card: the grey surface, very round.
    func card(_ fill: Color = Theme.panel) -> some View {
        background(fill, in: Theme.round)
    }

    /// Glass, for what floats over the map.
    @ViewBuilder func glass<S: Shape>(in shape: S, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                glassEffect(.regular.tint(tint.opacity(0.35)), in: shape)
            } else {
                glassEffect(.regular, in: shape)
            }
        } else {
            background(.ultraThinMaterial, in: shape)
                .background((tint ?? .clear).opacity(0.25), in: shape)
                .overlay(shape.stroke(Theme.line, lineWidth: 1))
        }
    }

    func glass() -> some View { glass(in: Theme.round) }

    /// The disc around a symbol, in a faint tint of its color.
    func iconBox(_ color: Color = Theme.accent) -> some View {
        background(color.opacity(0.16), in: Circle())
    }

    /// Sentences. They were once set in another face than the numbers; now everything is in one.
    func prose() -> some View { self }

    /// The page behind every scrolling screen: the sheet, night blue at the top. On the sheet
    /// over the map its right edge is kept free for the buttons (see `Rail`).
    func screen() -> some View { modifier(Screen()) }
}

private struct Screen: ViewModifier {
    @Environment(\.railInset) private var rail
    @Environment(\.railFoot) private var foot

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .contentMargins(.trailing, rail, for: .scrollContent)
            .contentMargins(.bottom, foot, for: .scrollContent)
            .background(Ground())
    }
}

private struct RailInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct RailFootKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// How much of the right edge of a screen the buttons of the sheet take: 0 where there are none.
    var railInset: CGFloat {
        get { self[RailInsetKey.self] }
        set { self[RailInsetKey.self] = newValue }
    }

    /// How much room a screen leaves under its last thing, to scroll it clear of the round button.
    var railFoot: CGFloat {
        get { self[RailFootKey.self] }
        set { self[RailFootKey.self] = newValue }
    }
}

/// The whole app in its look. Every sheet opened over a screen wears it, and has no buttons on
/// its right edge.
struct Dressed: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environment(\.railInset, 0)
            .environment(\.railFoot, 0)
            .tint(Theme.accent)
            .fontDesign(.rounded)
            .preferredColorScheme(Theme.dark ? .dark : .light)
    }
}

/// A card with its title inside, at the top.
struct Panel<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(LocalizedStringKey(title)).font(.title3.weight(.heavy)).foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 12) { content }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// A key/value row.
struct InfoRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(LocalizedStringKey(label)).foregroundStyle(Theme.sub)
            Spacer(minLength: 12)
            Text(value).foregroundStyle(Theme.text).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

/// One number, bold, its unit small beside it and what it counts under it. No box of its own:
/// several stand together in a `StatGrid`.
struct StatTile: View {
    let value: String
    let label: String
    var symbol: String?
    var color: Color = Theme.text

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            FigureText(value).foregroundStyle(color)
                .contentTransition(.numericText())
                .lineLimit(1).minimumScaleFactor(0.5)
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.caption2.weight(.bold)).accessibilityHidden(true)
                }
                Text(LocalizedStringKey(label)).font(.subheadline)
            }
            .foregroundStyle(Theme.sub)
            .lineLimit(1).minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The main action: the pill in the accent.
struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .background(color, in: Capsule())
            .foregroundStyle(Theme.onAccent)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// The other actions: a pill in a faint tint of the accent, with its words in the accent. In
/// another color (red for what ends) the pill is grey and the words take the color.
struct SecondaryButtonStyle: ButtonStyle {
    var color: Color = Theme.text

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .padding(.horizontal, 16)
            .foregroundStyle(color == Theme.text ? Theme.accent : color)
            .background(color == Theme.text ? Theme.accent.opacity(0.18) : Theme.input, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// A card that opens something: it gives a little under the finger.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// A red banner for the last error, dismissable.
struct ErrorBanner: View {
    @Binding var error: String?

    var body: some View {
        if let error {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.bad)
                Text(error).prose().font(.footnote).foregroundStyle(Theme.text)
                Spacer()
                Button { self.error = nil } label: { Image(systemName: "xmark").foregroundStyle(Theme.sub) }
                    .accessibilityLabel(Text("Chiudi"))
            }
            .padding(14)
            .background(Theme.bad.opacity(0.16), in: Theme.round)
        }
    }
}
