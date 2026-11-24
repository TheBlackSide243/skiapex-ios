import SwiftUI

/// A value as the widgets and the watch show it: the number bold, its unit small and in capitals
/// beside it ("1240 M", "72 KM/H"), as in the app. This file is in the app, in its extension and
/// in the watch app.
enum UnitText {
    /// What begins with a digit, or with a sign before one, is a number; the rest is a unit.
    static func isNumber(_ token: Substring) -> Bool {
        guard let first = token.first else { return false }
        if first.isNumber { return true }
        guard "-−±+".contains(first), let second = token.dropFirst().first else { return false }
        return second.isNumber
    }

    static func styled(_ value: String, big: Font, small: Font) -> AttributedString {
        let tokens = value.split(separator: " ")
        // A value with no number in it ("–") stays whole, as it is.
        guard tokens.contains(where: isNumber) else {
            var whole = AttributedString(value)
            whole.font = big
            return whole
        }
        var out = AttributedString()
        for (i, token) in tokens.enumerated() {
            let number = isNumber(token)
            var part = AttributedString((i == 0 ? "" : " ") + (number ? String(token) : token.uppercased()))
            part.font = number ? big : small
            out += part
        }
        return out
    }
}
