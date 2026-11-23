import SwiftUI
import UIKit

/// The look of Carve: a night-blue mountain under glass. Surfaces have round corners and a thin
/// outline; what floats on the map is glass (the Liquid Glass of iOS 26 and later, a frosted
/// material before); the things you press are pills. Titles, numbers and labels are set in the
/// monospaced face, sentences in the plain one (see `prose()`).
enum Theme {
    private static func c(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }

    static let bg = c(0x0b1626)
    static let panel = c(0x15253c)
    static let deep = c(0x08111e)
    static let input = c(0x1a2c47)
    static let line = Color.white.opacity(0.12)
    static let text = c(0xf2f6fb)
    static let sub = c(0x98a9bf)
    /// Glacier blue: what you can do, and the runs on the map.
    static let accent = c(0x5ccfff)
    static let onAccent = c(0x07121f)
    /// The lifts on the map and in the charts.
    static let lift = c(0xc4b5fd)
    static let good = c(0x34d399)
    static let bad = c(0xff7b8a)
    static let warn = c(0xfbbf24)

    /// Each run of a day in its own color on the map, in turn.
    static let runColors: [Color] = [c(0x5ccfff), c(0xff8a4c), c(0x34d399), c(0xf472b6), c(0xfbbf24), c(0xa78bfa), c(0x22d3ee), c(0xfb7185)]
    static func runColor(_ number: Int) -> Color { runColors[max(0, number - 1) % runColors.count] }

    static let round = RoundedRectangle(cornerRadius: 22, style: .continuous)
    static let roundSmall = RoundedRectangle(cornerRadius: 13, style: .continuous)

    /// The monospaced face in the segmented pickers too. Called once, before the first screen.
    @MainActor static func dressBars() {
        UISegmentedControl.appearance().setTitleTextAttributes([.font: UIFont.monospacedSystemFont(ofSize: 13, weight: .medium)], for: .normal)
    }
}

extension Font {
    /// The big words and numbers of a screen.
    static func display(_ style: Font.TextStyle) -> Font {
        .system(style, design: .monospaced, weight: .semibold)
    }
}

extension View {
    /// A card: the raised surface with its thin outline.
    func card(_ fill: Color = Theme.panel) -> some View {
        background(fill, in: Theme.round).overlay(Theme.round.strokeBorder(Theme.line, lineWidth: 1))
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

    /// The box around a symbol: dark, outlined in the accent.
    func iconBox(_ color: Color = Theme.accent) -> some View {
        background(Theme.deep, in: Theme.roundSmall).overlay(Theme.roundSmall.strokeBorder(color.opacity(0.55), lineWidth: 1))
    }

    /// Sentences: in the plain face, which reads better than the monospaced one.
    func prose() -> some View { fontDesign(nil) }

    /// The page behind every scrolling screen.
    func screen() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
    }
}

/// The whole app in its look.
struct Dressed: ViewModifier {
    func body(content: Content) -> some View {
        content
            .tint(Theme.accent)
            .fontDesign(.monospaced)
            .preferredColorScheme(.dark)
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
                Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 12) { content }
        }
        .padding(16)
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

/// One number, big, with what it counts under it.
struct StatTile: View {
    let value: String
    let label: String
    var symbol: String?
    var color: Color = Theme.text

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let symbol {
                Image(systemName: symbol).font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
                    .frame(width: 30, height: 30)
                    .iconBox()
                    .padding(.bottom, 4)
                    .accessibilityHidden(true)
            }
            Text(value).font(.display(.title3)).monospacedDigit().foregroundStyle(color)
                .contentTransition(.numericText())
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(LocalizedStringKey(label)).font(.caption).foregroundStyle(Theme.sub)
                .lineLimit(1).minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// The main action: the glacier pill.
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
            .shadow(color: color.opacity(0.3), radius: 12, x: 0, y: 6)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// The other actions: a quiet glass pill. In another color (red for what ends) the words take it.
struct SecondaryButtonStyle: ButtonStyle {
    var color: Color = Theme.text

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .padding(.horizontal, 16)
            .foregroundStyle(color)
            .background(Theme.input.opacity(configuration.isPressed ? 0.9 : 0.6), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
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
            .overlay(Theme.round.strokeBorder(Theme.bad.opacity(0.5), lineWidth: 1))
        }
    }
}
