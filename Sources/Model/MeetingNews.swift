import Foundation
import UserNotifications

/// What is new about the places to meet, said with a notification: a friend asks you to meet
/// somewhere, or a friend answered the place you set. Each is said once, also across launches.
/// The app learns of them when it asks the server: while it is open, and every half minute while
/// a day is recorded.
enum MeetingNews {
    struct Notice: Equatable {
        /// What it is about: said once for each key.
        let key: String
        let title: String
        let body: String
    }

    private static let toldKey = "meetingTold"

    /// What there is to say, given what was said already.
    static func notices(_ meetings: [Meeting], told: Set<String>) -> [Notice] {
        var out: [Notice] = []
        for meeting in meetings {
            let stamp = Int(meeting.at)
            if meeting.mine {
                for one in meeting.answers ?? [] {
                    guard let answer = one.answer else { continue }
                    let key = "answer:\(one.id):\(stamp):\(answer)"
                    guard !told.contains(key) else { continue }
                    let title = answer == "yes" ? String(localized: "\(one.name) ci sarà") : String(localized: "\(one.name) non viene")
                    out.append(Notice(key: key, title: title, body: meeting.title))
                }
            } else if meeting.asks {
                let key = "ask:\(meeting.id):\(stamp)"
                guard !told.contains(key) else { continue }
                out.append(Notice(key: key, title: String(localized: "\(meeting.name) propone di trovarvi"),
                                  body: String(localized: "\(meeting.title). Apri Ski Apex per dire se ci sei.")))
            }
        }
        return out
    }

    /// Sends the notifications due, and remembers them.
    static func tell(_ meetings: [Meeting]) {
        guard !Demo.isOn else { return }
        let defaults = UserDefaults.standard
        var told = defaults.stringArray(forKey: toldKey) ?? []
        let due = notices(meetings, told: Set(told))
        guard !due.isEmpty else { return }
        for notice in due {
            let content = UNMutableNotificationContent()
            content.title = notice.title
            content.body = notice.body
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: notice.key, content: content, trigger: nil))
            told.append(notice.key)
        }
        // The last hundred are enough: a place to meet lasts a day at most.
        defaults.set(Array(told.suffix(100)), forKey: toldKey)
    }
}
