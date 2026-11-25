import Foundation
import UIKit
import UserNotifications

/// Notifications sent by the server of the friends through Apple, which arrive with the app
/// closed too: a friend asks to meet, a friend answered your place, an invitation was accepted.
/// Only the build from TestFlight is signed to receive them; in the others Apple gives no token
/// and the app goes on saying these things by itself, when it is open or recording.
enum Push {
    private static let tokenKey = "pushToken"
    private static let activeKey = "pushActive"

    /// The token Apple gave this iPhone for the app, as the server wants it.
    static var token: String? {
        get { UserDefaults.standard.string(forKey: tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: tokenKey) }
    }

    /// Whether the server took the token and can send: then it says which things it sent, and
    /// the app does not say them again.
    static var active: Bool {
        get { UserDefaults.standard.bool(forKey: activeKey) }
        set { UserDefaults.standard.set(newValue, forKey: activeKey) }
    }

    /// The token as text: two letters for each byte.
    static func text(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }

    /// With an account, asks Apple for the token: when notifications are allowed already, or
    /// after asking to send them (`asking`), which iOS shows once.
    @MainActor static func register(asking: Bool = false) async {
        guard !Demo.isOn, Shared.social.signedIn else { return }
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined, asking {
            _ = await Nearby.allow()
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Apple gave the token: the server is told, for the account signed in here.
    @MainActor static func took(_ data: Data) {
        let text = text(data)
        token = text
        Task { await Shared.social.sendDevice(text) }
    }
}
