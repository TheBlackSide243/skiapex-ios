import SwiftUI

/// The sheet behind every screen: night blue at the top, fading into the page.
struct Ground: View {
    var body: some View {
        LinearGradient(stops: [.init(color: Theme.sky, location: 0), .init(color: Theme.bg, location: 0.45)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

/// A value as it is shown everywhere: the numbers bold, the units small and in capitals beside
/// them ("5074 M", "1 H 54 MIN", "72 KM/H").
struct FigureText: View {
    let value: String
    var big: Font
    var small: Font

    init(_ value: String, big: Font = .system(.title2, design: .default, weight: .bold),
         small: Font = .system(.footnote, design: .default, weight: .bold)) {
        self.value = value
        self.big = big
        self.small = small
    }

    var body: some View {
        Text(Self.styled(value, big: big, small: small)).monospacedDigit()
    }

    /// One piece of a value: a number, or the unit after it.
    struct Piece: Equatable {
        let text: String
        let number: Bool
    }

    /// "1 h 54 min" in its pieces: what begins with a digit (or a sign before one) is a number,
    /// the rest a unit, in capitals. A value with no number in it stays whole, as it is.
    static func pieces(_ value: String) -> [Piece] {
        let tokens = value.split(separator: " ").map(String.init)
        guard tokens.contains(where: isNumber) else { return [Piece(text: value, number: true)] }
        return tokens.map { isNumber($0) ? Piece(text: $0, number: true) : Piece(text: $0.uppercased(), number: false) }
    }

    static func isNumber(_ token: String) -> Bool {
        guard let first = token.first else { return false }
        if first.isNumber { return true }
        guard "-−±+".contains(first), let second = token.dropFirst().first else { return false }
        return second.isNumber
    }

    static func styled(_ value: String, big: Font, small: Font) -> AttributedString {
        var out = AttributedString()
        for (i, piece) in pieces(value).enumerated() {
            var part = AttributedString((i == 0 ? "" : " ") + piece.text)
            part.font = piece.number ? big : small
            out += part
        }
        return out
    }
}

/// The numbers of something, two by two in one card.
struct StatGrid<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 22) {
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// The title of a part of a screen: heavy, on the sheet itself.
struct SectionTitle: View {
    let title: String
    var detail: String?

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(LocalizedStringKey(title)).font(.title2.weight(.heavy)).foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail).font(.subheadline).foregroundStyle(Theme.sub).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
    }
}

/// One of a few things to choose from: a pill, full when chosen and faint when not.
struct ChoicePill: View {
    let title: String
    var symbol: String?
    let on: Bool
    /// As wide as the room it is given, for pills side by side of one width.
    var wide = false

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).font(.footnote.weight(.semibold)) }
            Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: wide ? .infinity : nil)
        .foregroundStyle(on ? Theme.onAccent : Theme.accent)
        .background(on ? Theme.accent : Theme.accent.opacity(0.18), in: Capsule())
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
