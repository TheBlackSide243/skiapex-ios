import Foundation
import UserNotifications

/// Tells you when a friend who shares where they are is close: a notification when one comes
/// within a few hundred meters, and one, once in a while, when one is skiing in the same area.
/// It works from the positions the friends share through the server, so it needs no Bluetooth and
/// reaches as far as the mobile network does.
enum Nearby {
    enum Range: Equatable {
        /// Close enough to meet: at the same lift, on the same piste.
        case close
        /// In the same ski area.
        case area
        case far
    }

    static let closeMeters = 300.0
    static let areaMeters = 6000.0
    /// A position older than this says little about where a friend is now.
    static let freshSeconds = 180.0

    private static var told: [String: Date] = [:]

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: Prefs.nearAlerts) as? Bool ?? true
    }

    static func range(_ meters: Double) -> Range {
        meters <= closeMeters ? .close : meters <= areaMeters ? .area : .far
    }

    /// How far a friend is from a place, in meters.
    static func distance(from lat: Double, _ lon: Double, to friend: LiveFriend) -> Double {
        Geo.distance(lat1: lat, lon1: lon, lat2: friend.lat, lon2: friend.lon)
    }

    /// What to say about the friends, given where you are: at most one notice a friend, the closer
    /// kind first. `told` is when each notice was last given; a friend met is not announced again
    /// for twenty minutes, one in the area not again for six hours.
    static func notices(lat: Double, lon: Double, friends: [LiveFriend], now: Date = Date(),
                        told: [String: Date]) -> [(key: String, friend: LiveFriend, range: Range, meters: Double)] {
        var out: [(key: String, friend: LiveFriend, range: Range, meters: Double)] = []
        for friend in friends where now.timeIntervalSince(friend.date) <= freshSeconds {
            let meters = distance(from: lat, lon, to: friend)
            let kind = range(meters)
            guard kind != .far else { continue }
            let key = friend.id + (kind == .close ? ":close" : ":area")
            let quiet: TimeInterval = kind == .close ? 20 * 60 : 6 * 3600
            if let last = told[key], now.timeIntervalSince(last) < quiet { continue }
            // Announced as close, a friend is not announced as "in the area" right after.
            if kind == .area, let last = told[friend.id + ":close"], now.timeIntervalSince(last) < 6 * 3600 { continue }
            out.append((key, friend, kind, meters))
        }
        return out
    }

    /// Looks at the friends from where you are and sends the notifications due.
    static func check(lat: Double, lon: Double, friends: [LiveFriend]) {
        guard enabled, !Demo.isOn else { return }
        for notice in notices(lat: lat, lon: lon, friends: friends, told: told) {
            told[notice.key] = Date()
            let content = UNMutableNotificationContent()
            let far = Fmt.distance(notice.meters)
            switch notice.range {
            case .close:
                content.title = String(localized: "\(notice.friend.name) è vicino a te")
                content.body = String(localized: "È a \(far) da te.")
            default:
                content.title = String(localized: "\(notice.friend.name) sta sciando nella tua zona")
                content.body = String(localized: "È a \(far) da te: lo trovi sulla mappa.")
            }
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: notice.key, content: content, trigger: nil))
        }
    }

    /// Asks to send notifications, the first time. True when they are allowed.
    static func allow() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }
}
