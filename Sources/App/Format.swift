import Foundation
import MapKit
import SwiftUI

enum Units: String, CaseIterable, Identifiable {
    case metric, imperial
    var id: String { rawValue }
    var label: String { self == .metric ? "km · m" : "mi · ft" }

    static var current: Units {
        Units(rawValue: UserDefaults.standard.string(forKey: Prefs.units) ?? "") ?? .metric
    }
}

/// The map under the tracks.
enum MapLook: String, CaseIterable, Identifiable {
    case standard, satellite
    var id: String { rawValue }
    var label: String { self == .standard ? "Mappa" : "Satellite" }
    var symbol: String { self == .standard ? "map" : "globe.europe.africa" }

    var style: MapStyle {
        switch self {
        case .standard: .standard(elevation: .realistic, pointsOfInterest: .excludingAll)
        case .satellite: .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll)
        }
    }
}

/// Numbers as they are shown, in the units chosen in Settings.
enum Fmt {
    private static var metric: Bool { Units.current == .metric }

    private static func number(_ x: Double, decimals: Int = 0) -> String {
        x.formatted(.number.precision(.fractionLength(decimals)))
    }

    /// The number alone, for the big speed on screen.
    static func speedValue(_ ms: Double) -> String { number(max(0, ms) * (metric ? 3.6 : 2.236_94)) }
    static var speedUnit: String { metric ? "km/h" : "mph" }
    static func speed(_ ms: Double) -> String { "\(speedValue(ms)) \(speedUnit)" }

    static func distance(_ m: Double) -> String {
        if metric {
            return m < 1000 ? "\(number(m)) m" : "\(number(m / 1000, decimals: m < 100_000 ? 1 : 0)) km"
        }
        let miles = m / 1609.344
        return miles < 0.2 ? "\(number(m * 3.280_84)) ft" : "\(number(miles, decimals: miles < 100 ? 1 : 0)) mi"
    }

    /// Heights and drops.
    static func height(_ m: Double) -> String {
        metric ? "\(number(m)) m" : "\(number(m * 3.280_84)) ft"
    }

    /// "2 h 14 min", "14 min", "45 s".
    static func duration(_ s: TimeInterval) -> String {
        let total = Int(max(0, s).rounded())
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return "\(h) h \(String(format: "%02d", m)) min" }
        if m > 0 { return "\(m) min" }
        return "\(total) s"
    }

    /// "1:04:32" for the clock of the day under way.
    static func clock(_ s: TimeInterval) -> String {
        let total = Int(max(0, s))
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    static func percent(_ x: Double) -> String { "\(number(x)) %" }

    static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }

    static func day(_ d: Date) -> String { d.formatted(.dateTime.weekday(.wide).day().month(.wide)) }

    static func dayShort(_ d: Date) -> String { d.formatted(.dateTime.day().month(.abbreviated).year()) }

    /// From degrees Celsius.
    static func temperature(_ c: Double) -> String {
        metric ? "\(number(c))°" : "\(number(c * 9 / 5 + 32))°F"
    }

    /// Fresh snow, from centimeters.
    static func snow(_ cm: Double) -> String {
        metric ? "\(number(cm)) cm" : "\(number(cm / 2.54, decimals: 1)) in"
    }

    /// Wind, from km/h.
    static func wind(_ kmh: Double) -> String {
        metric ? "\(number(kmh)) km/h" : "\(number(kmh / 1.609_344)) mph"
    }
}
