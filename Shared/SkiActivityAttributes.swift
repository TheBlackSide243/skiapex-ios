import ActivityKit
import Foundation
import SwiftUI

/// The day under way as the lock screen and the Dynamic Island show it. This file is in the app,
/// which writes it, and in the extension, which draws it.
struct SkiActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// run, lift, idle or paused.
        var phase: String
        var runs: Int
        /// Meters skied down so far.
        var vertical: Double
        /// m/s.
        var maxSpeed: Double
        /// km and meters, or miles and feet.
        var metric: Bool

        var label: LocalizedStringKey {
            switch phase {
            case "run": "In pista"
            case "lift": "In risalita"
            case "paused": "In pausa"
            default: "Fermo"
            }
        }

        var symbol: String {
            switch phase {
            case "run": "figure.skiing.downhill"
            case "lift": "cablecar"
            case "paused": "pause.fill"
            default: "mountain.2"
            }
        }

        var verticalText: String {
            metric ? "\(Int(vertical.rounded())) m" : "\(Int((vertical * 3.280_84).rounded())) ft"
        }

        var maxSpeedText: String {
            metric ? "\(Int((maxSpeed * 3.6).rounded())) km/h" : "\(Int((maxSpeed * 2.236_94).rounded())) mph"
        }
    }

    /// When the day began: the clock on the lock screen counts from here.
    var start: Date
}
