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

    init(_ value: String, big: Font = .system(.title2, design: .rounded, weight: .bold),
         small: Font = .system(.footnote, design: .rounded, weight: .bold)) {
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

/// The profile of a day: up with the lifts, thin and grey, and down each piste in the color of
/// its signs. Small in the list of the days, big on the page of one.
struct DayProfile: View {
    let legs: [Leg]
    var lineWidth: CGFloat = 2

    /// The lowest and the highest altitude of the day.
    static func range(_ legs: [Leg]) -> (low: Double, high: Double)? {
        let all = legs.flatMap { [$0.a, $0.b] }
        guard let low = all.min(), let high = all.max(), high > low else { return nil }
        return (low, high)
    }

    var body: some View {
        Canvas { context, size in
            let total = legs.reduce(0.0) { $0 + max(1, $1.s) }
            guard total > 0, let range = Self.range(legs) else { return }
            let pad = lineWidth + 1
            func y(_ alt: Double) -> CGFloat {
                size.height - pad - CGFloat((alt - range.low) / (range.high - range.low)) * (size.height - pad * 2)
            }
            // Where each stretch begins and ends.
            var spans: [(leg: Leg, from: CGPoint, to: CGPoint)] = []
            var x: CGFloat = 0
            for leg in legs {
                let width = CGFloat(max(1, leg.s) / total) * size.width
                spans.append((leg, CGPoint(x: x, y: y(leg.a)), CGPoint(x: x + width, y: y(leg.b))))
                x += width
            }
            var ground = Path()
            ground.move(to: CGPoint(x: 0, y: size.height))
            for span in spans {
                ground.addLine(to: span.from)
                ground.addLine(to: span.to)
            }
            ground.addLine(to: CGPoint(x: size.width, y: size.height))
            ground.closeSubpath()
            context.fill(ground, with: .color(Theme.text.opacity(0.06)))
            // The lifts and the stops first, the runs over them.
            for span in spans where span.leg.k != 0 {
                var line = Path()
                line.move(to: span.from)
                line.addLine(to: span.to)
                context.stroke(line, with: .color(Theme.sub.opacity(span.leg.k == 1 ? 0.7 : 0.35)),
                               style: StrokeStyle(lineWidth: lineWidth * 0.55, lineCap: .round))
            }
            for span in spans where span.leg.k == 0 {
                var line = Path()
                line.move(to: span.from)
                line.addLine(to: span.to)
                let dark = ["advanced", "expert"].contains(span.leg.d ?? "")
                // A black piste is seen by a light edge around it.
                if dark {
                    context.stroke(line, with: .color(Theme.text.opacity(0.8)), style: StrokeStyle(lineWidth: lineWidth + 2, lineCap: .round))
                }
                context.stroke(line, with: .color(Theme.difficultyColor(span.leg.d) ?? Theme.accent),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A piste as on its signs: a disc in the color of its difficulty, with its number when it has
/// one. Grey, with a skier, for a piste not known.
struct PisteBadge: View {
    let difficulty: String?
    var ref: String?
    var size: CGFloat = 26

    var body: some View {
        let color = Theme.difficultyColor(difficulty) ?? Theme.input
        let dark = ["advanced", "expert"].contains(difficulty ?? "")
        let ink: Color = ["freeride", "extreme"].contains(difficulty ?? "") ? Color(hex: 0x1a1500) : .white
        ZStack {
            Circle().fill(color)
            if let ref, !ref.isEmpty, ref.count <= 3 {
                Text(ref).font(.system(size: size * 0.46, weight: .bold, design: .rounded)).foregroundStyle(ink)
                    .minimumScaleFactor(0.6).lineLimit(1).padding(.horizontal, 2)
            } else {
                Image(systemName: "figure.skiing.downhill").font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(ink)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(Color.white.opacity(dark ? 0.75 : 0.22), lineWidth: dark ? 1.5 : 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(Theme.difficultyLabel(difficulty) ?? "Pista")))
    }
}
