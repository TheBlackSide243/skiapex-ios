import CoreLocation
import Foundation
import Observation
import Security
import UIKit

/// A secret kept in the keychain of the iPhone: the token of the friends' account.
enum Keychain {
    private static let service = "skiapex.friends"

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        guard let value else { return }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }
}

struct SocialAccount: Codable, Hashable {
    var id: String
    var name: String
    /// When the profile picture was set, in milliseconds since 1970: it tells one picture from
    /// the next. nil or 0 when there is none.
    var photo: Double?
    /// How one signs in: password, apple or google.
    var kind: String?
}

struct Friend: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var photo: Double?
}

/// One person in a leaderboard: the totals of a season.
struct BoardRow: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var me: Bool
    var days: Int
    var vertical: Double
    var runs: Int
    var distance: Double
    var time: Double
    var maxSpeed: Double
    var photo: Double?
}

/// A friend who is skiing now and shares where: the last position the server heard of.
struct LiveFriend: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var lat: Double
    var lon: Double
    var alt: Double
    /// m/s.
    var speed: Double
    /// run, lift or idle.
    var phase: String
    /// When it was sent, in milliseconds since 1970.
    var at: Double
    var photo: Double?

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    var date: Date { Date(timeIntervalSince1970: at / 1000) }

    var phaseLabel: String {
        switch phase {
        case "run": "In pista"
        case "lift": "In risalita"
        default: "Fermo"
        }
    }

    /// One or two letters for the pin on the map.
    var initials: String { Avatars.initials(of: name) }
}

/// One person on a piste: the best time down the whole of it.
struct PisteRow: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var photo: Double?
    var me: Bool
    /// Seconds.
    var best: Double
    /// m/s, the top speed on it.
    var speed: Double
    var runs: Int
    /// The day of the best time, "2026-11-20".
    var date: String
}

/// What a friend said to a place to meet of yours.
struct MeetingAnswer: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var photo: Double?
    /// "yes", "no", or nil while they have not answered.
    var answer: String?
}

/// A place to meet, set by you or by a friend: a hut, the top of a lift, a point of a piste. The
/// friends say whether they are coming; only who set it sees who said what.
struct Meeting: Codable, Identifiable, Hashable {
    /// Whose it is.
    var id: String
    var name: String
    var photo: Double?
    var mine: Bool
    var lat: Double
    var lon: Double
    /// What the place is called.
    var label: String
    /// At what time, in milliseconds since 1970, when one was given.
    var when: Double?
    /// When it is over, and when it was set.
    var until: Double
    var at: Double
    /// To a friend's: what you said, "yes" or "no"; nil until you answer.
    var answer: String? = nil
    /// To yours: every friend, with what each said.
    var answers: [MeetingAnswer]? = nil

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    var time: Date? { when.map { Date(timeIntervalSince1970: $0 / 1000) } }
    /// A friend's, still waiting for your answer.
    var asks: Bool { !mine && answer == nil }

    /// "Rifugio Teodulo · 12:30", or the place alone.
    var title: String {
        let place = label.isEmpty ? String(localized: "Punto d'incontro") : label
        guard let time else { return place }
        return "\(place) · \(Fmt.time(time))"
    }
}

/// Where you are skiing today, to the kilometer, told to the server while a day is recorded: a
/// place to meet reaches only the friends skiing around it that day. Said again every few
/// minutes, which is also when the places to meet are heard of with the iPhone in a pocket.
enum Presence {
    static let every = 300.0
    private static var last = Date.distantPast

    static var isOn: Bool { UserDefaults.standard.object(forKey: Prefs.presence) as? Bool ?? true }

    /// Whether it is time to say it again.
    static func due(last: Date, now: Date) -> Bool { now.timeIntervalSince(last) >= every }

    static func update(recording: Bool, point: TrackPoint?, social: Social) {
        guard recording, isOn, social.signedIn, let point, Date().timeIntervalSince(point.t) < 120,
              due(last: last, now: Date()) else { return }
        last = Date()
        Task { await social.sendPresence(point) }
    }

    /// Turned off, or signed out: the next day says it at once.
    static func reset() { last = .distantPast }
}

/// Your position to your friends while a day is recorded, if you turned it on: sent every half
/// minute at most, and taken back when the recording pauses or ends, or when you turn it off.
enum LiveShare {
    private static var lastSent = Date.distantPast
    private static var active = false

    static func update(state: Recorder.State, point: TrackPoint?, phase: SegmentKind) {
        let social = Shared.social
        // The friends a few steps away, over Bluetooth: with or without signal.
        Proximity.shared.update(recording: state == .recording)
        // In which area the day is, for the places to meet of the friends skiing there.
        Presence.update(recording: state == .recording, point: point, social: social)
        let on = UserDefaults.standard.bool(forKey: Prefs.shareLive) && social.signedIn
        if on, state == .recording, let point, Date().timeIntervalSince(point.t) < 90 {
            guard Date().timeIntervalSince(lastSent) >= 25 else { return }
            lastSent = Date()
            active = true
            Task { await social.sendPosition(point, phase: phase.rawValue) }
        } else if active {
            active = false
            lastSent = .distantPast
            Task { await social.stopSharing() }
        }
    }
}

/// What a leaderboard is sorted by.
enum BoardMetric: String, CaseIterable, Identifiable {
    case days, vertical, distance, runs, maxSpeed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .days: "Giorni sulla neve"
        case .vertical: "Dislivello"
        case .distance: "Chilometri"
        case .runs: "Discese"
        case .maxSpeed: "Velocità max"
        }
    }

    func value(_ row: BoardRow) -> Double {
        switch self {
        case .days: Double(row.days)
        case .vertical: row.vertical
        case .distance: row.distance
        case .runs: Double(row.runs)
        case .maxSpeed: row.maxSpeed
        }
    }

    func text(_ row: BoardRow) -> String {
        switch self {
        case .days: "\(row.days)"
        case .vertical: Fmt.height(row.vertical)
        case .distance: Fmt.distance(row.distance)
        case .runs: "\(row.runs)"
        case .maxSpeed: Fmt.speed(row.maxSpeed)
        }
    }

    /// The rows from the best down, each with its place: the same number, the same place.
    func ranked(_ rows: [BoardRow]) -> [(place: Int, row: BoardRow)] {
        let sorted = rows.sorted {
            value($0) != value($1) ? value($0) > value($1) : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        var out: [(place: Int, row: BoardRow)] = []
        for (i, row) in sorted.enumerated() {
            let place = i > 0 && value(sorted[i - 1]) == value(row) ? out[i - 1].place : i + 1
            out.append((place, row))
        }
        return out
    }
}

enum SocialError: LocalizedError {
    case server(String)
    case offline

    var errorDescription: String? {
        switch self {
        case .offline:
            return String(localized: "Non riesco a raggiungere il server degli amici. Controlla la connessione e riprova.")
        case .server(let code):
            switch code {
            case "bad username": return String(localized: "Il nome deve avere da 3 a 20 caratteri: lettere, cifre, punto, trattino.")
            case "password too short": return String(localized: "La password deve avere almeno 8 caratteri.")
            case "username taken": return String(localized: "Questo nome è già preso: scegline un altro.")
            case "wrong username or password": return String(localized: "Nome o password sbagliati.")
            case "wrong password": return String(localized: "Password sbagliata.")
            case "too many attempts", "too many accounts": return String(localized: "Troppi tentativi: riprova tra un quarto d'ora.")
            case "no such invitation": return String(localized: "Questo invito non è valido o è scaduto.")
            case "that is you": return String(localized: "Questo è il tuo invito: mandalo a un amico.")
            case "too many friends": return String(localized: "Uno dei due ha già troppi amici.")
            case "signed out": return String(localized: "Devi accedere di nuovo.")
            case "bad token": return String(localized: "L'accesso non è riuscito. Riprova.")
            case "not set up": return String(localized: "Questo modo di accedere non è ancora attivo.")
            case "photo too big", "bad photo": return String(localized: "Non riesco a usare questa foto: provane un'altra.")
            default: return String(localized: "Il server degli amici ha risposto con un errore. Riprova tra poco.")
            }
        }
    }
}

/// Friends and leaderboards: an account on the Ski Apex server (a name and a password, nothing
/// else), friends made with an invitation link, and for each season the totals of the days, sent
/// when the leaderboard is opened. Tracks, places and positions never leave the iPhone.
@Observable final class Social {
    private(set) var account: SocialAccount?
    private(set) var friends: [Friend] = []
    private(set) var rows: [BoardRow] = []
    /// The friends skiing now who share where they are.
    private(set) var live: [LiveFriend] = []
    /// The places to meet set by you and by your friends, not over yet.
    private(set) var meetings: [Meeting] = []
    private(set) var busy = false
    /// The code of the invitation link, once asked for.
    private(set) var inviteCode: String?
    /// An invitation opened from a link, waiting to be accepted.
    var pendingCode: String?
    var error: String?

    let server: URL
    @ObservationIgnored private var token: String?
    @ObservationIgnored private let demo: Bool

    private static let accountKey = "socialAccount"
    private static let friendsKey = "socialFriends"

    /// The friends as last read from the server: to know them where there is no signal.
    static func keptFriends() -> [Friend] {
        guard let data = UserDefaults.standard.data(forKey: friendsKey) else { return [] }
        return (try? JSONDecoder().decode([Friend].self, from: data)) ?? []
    }

    private func keepFriends() {
        if let data = try? JSONEncoder().encode(friends) { UserDefaults.standard.set(data, forKey: Self.friendsKey) }
    }

    init(demo: Bool = false) {
        self.demo = demo
        // `-server <url>` for a server of one's own, or a test one.
        let args = ProcessInfo.processInfo.arguments
        let custom = args.firstIndex(of: "-server").flatMap { $0 + 1 < args.count ? URL(string: args[$0 + 1]) : nil }
        server = custom ?? URL(string: "https://skiapex.tbsgaming.win")!
        if demo {
            account = SocialAccount(id: "me", name: "Marco")
            friends = [Friend(id: "a", name: "Giulia"), Friend(id: "b", name: "Luca"), Friend(id: "c", name: "Sara")]
            rows = [
                BoardRow(id: "me", name: "Marco", me: true, days: 9, vertical: 41_200, runs: 96, distance: 182_000, time: 61_000, maxSpeed: 20.4),
                BoardRow(id: "a", name: "Giulia", me: false, days: 12, vertical: 38_900, runs: 121, distance: 201_000, time: 70_000, maxSpeed: 18.9),
                BoardRow(id: "b", name: "Luca", me: false, days: 6, vertical: 29_500, runs: 58, distance: 119_000, time: 39_000, maxSpeed: 23.1),
                BoardRow(id: "c", name: "Sara", me: false, days: 4, vertical: 12_300, runs: 31, distance: 54_000, time: 21_000, maxSpeed: 16.2),
            ]
            let now = Date().timeIntervalSince1970 * 1000
            live = [
                LiveFriend(id: "a", name: "Giulia", lat: 45.9418, lon: 7.6392, alt: 2610, speed: 11.4, phase: "run", at: now - 20_000),
                LiveFriend(id: "b", name: "Luca", lat: 45.9372, lon: 7.6318, alt: 2240, speed: 4.8, phase: "lift", at: now - 45_000),
            ]
            meetings = [Meeting(id: "a", name: "Giulia", photo: nil, mine: false, lat: 45.9345, lon: 7.6262, label: "Baita del Sole",
                                when: now + 40 * 60_000, until: now + 100 * 60_000, at: now - 5 * 60_000)]
            return
        }
        if let data = UserDefaults.standard.data(forKey: Self.accountKey),
           let saved = try? JSONDecoder().decode(SocialAccount.self, from: data), let token = Keychain.get("token") {
            account = saved
            self.token = token
        }
    }

    var signedIn: Bool { account != nil }

    /// The link to send to a friend.
    var inviteLink: URL? {
        inviteCode.map { server.appendingPathComponent("f").appendingPathComponent($0) }
    }

    // MARK: Account

    @MainActor func enter(name: String, password: String, new: Bool) async {
        await run {
            let data = try await self.call("POST", new ? "/v1/accounts" : "/v1/sessions", ["username": name, "password": password], signed: false)
            struct Answer: Decodable { let token: String; let account: SocialAccount }
            let answer = try JSONDecoder().decode(Answer.self, from: data)
            self.remember(answer.account, token: answer.token)
        }
    }

    /// In with Apple or with Google: the token they gave the iPhone goes to the server, which
    /// checks it and finds the account, or makes it with the name given the first time.
    @MainActor func enter(with provider: String, token: String, name: String?) async {
        await run {
            var body: [String: Any] = ["token": token]
            if let name, !name.isEmpty { body["name"] = name }
            let data = try await self.call("POST", "/v1/sessions/\(provider)", body, signed: false)
            struct Answer: Decodable { let token: String; let account: SocialAccount }
            let answer = try JSONDecoder().decode(Answer.self, from: data)
            self.remember(answer.account, token: answer.token)
        }
    }

    @MainActor func signOut() async {
        _ = try? await call("DELETE", "/v1/sessions")
        forget()
    }

    /// Deletes the account and everything it shared. True when done. The password, for the
    /// accounts that have one; nil for the ones made with Apple or Google.
    @MainActor func deleteAccount(password: String?) async -> Bool {
        var done = false
        await run {
            _ = try await self.call("DELETE", "/v1/me", password.map { ["password": $0] } ?? ["confirm": true])
            self.forget()
            done = true
        }
        return done
    }

    private func remember(_ account: SocialAccount, token: String) {
        self.account = account
        self.token = token
        Keychain.set(token, for: "token")
        if let data = try? JSONEncoder().encode(account) { UserDefaults.standard.set(data, forKey: Self.accountKey) }
    }

    private func forget() {
        account = nil
        token = nil
        friends = []
        rows = []
        live = []
        meetings = []
        inviteCode = nil
        Keychain.set(nil, for: "token")
        UserDefaults.standard.removeObject(forKey: Self.accountKey)
        UserDefaults.standard.removeObject(forKey: Self.friendsKey)
    }

    // MARK: Profile pictures

    /// Sets your picture: a small JPEG (see `Avatars.prepare`), seen by you and by your friends.
    @MainActor func setPhoto(_ jpeg: Data) async {
        await run {
            let data = try await self.call("PUT", "/v1/me/photo", raw: jpeg)
            let account = try JSONDecoder().decode(SocialAccount.self, from: data)
            Avatars.keep(jpeg, id: account.id, version: account.photo ?? 0)
            if let token = self.token { self.remember(account, token: token) }
        }
    }

    @MainActor func removePhoto() async {
        await run {
            let data = try await self.call("DELETE", "/v1/me/photo")
            let account = try JSONDecoder().decode(SocialAccount.self, from: data)
            if let token = self.token { self.remember(account, token: token) }
        }
    }

    /// The picture of an account, yours or a friend's: from the iPhone when it was seen before,
    /// from the server the first time.
    func photo(of id: String, version: Double) async -> UIImage? {
        guard version > 0 else { return nil }
        if let kept = Avatars.image(id: id, version: version) { return kept }
        guard !demo, let data = try? await call("GET", "/v1/photos/\(id)?v=\(Int(version))") else { return nil }
        return Avatars.keep(data, id: id, version: version)
    }

    // MARK: Friends

    @MainActor func makeInvite(renew: Bool = false) async {
        await run {
            let data = try await self.call("POST", "/v1/me/invite", ["renew": renew])
            struct Answer: Decodable { let code: String }
            self.inviteCode = try JSONDecoder().decode(Answer.self, from: data).code
        }
    }

    /// Accepts an invitation by its code, typed or from a link. True when you are friends now.
    @MainActor func accept(_ raw: String) async -> Bool {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        var done = false
        await run {
            _ = try await self.call("POST", "/v1/friends", ["code": code])
            done = true
        }
        return done
    }

    @MainActor func remove(_ friend: Friend) async {
        await run {
            _ = try await self.call("DELETE", "/v1/friends/\(friend.id)")
            self.friends.removeAll { $0.id == friend.id }
            self.keepFriends()
            self.rows.removeAll { $0.id == friend.id }
        }
    }

    // MARK: Ski areas

    /// Tells who skis there about a day: where it was (to the kilometer), how the snow was, its
    /// numbers for the averages, and whether your friends may see you were there. Only what the
    /// switches of the question allow. Silent: a day is not worth an error.
    @MainActor func tell(_ day: DaySummary, snow: Snow?, numbers: Bool, friends: Bool) async -> Bool {
        guard signedIn, !demo, let lat = day.lat, let lon = day.lon else { return false }
        var body: [String: Any] = ["date": PlaceInfo.dayFormat.string(from: day.start), "lat": lat, "lon": lon, "friends": friends]
        if let snow { body["snow"] = snow.rawValue }
        if numbers, day.manual != true {
            body["stats"] = ["vertical": day.stats.vertical, "distance": day.stats.runDistance, "runTime": day.stats.runTime,
                             "liftTime": day.stats.liftTime, "avgSpeed": day.stats.avgRunSpeed, "runs": day.stats.runs]
        }
        return (try? await call("PUT", "/v1/places/visits", body)) != nil
    }

    /// Takes back what was told of a day.
    @MainActor func untell(_ day: DaySummary) async {
        guard signedIn, !demo else { return }
        _ = try? await call("DELETE", "/v1/places/visits", ["date": PlaceInfo.dayFormat.string(from: day.start)])
    }

    /// What is known of a ski area: the snow as people found it, the average day, the friends.
    func place(lat: Double, lon: Double) async -> PlaceInfo? {
        if demo { return Self.demoPlace }
        guard signedIn, let data = try? await call("GET", String(format: "/v1/places?lat=%.4f&lon=%.4f", lat, lon)) else { return nil }
        return try? JSONDecoder().decode(PlaceInfo.self, from: data)
    }

    /// For the pictures.
    private static var demoPlace: PlaceInfo {
        let today = PlaceInfo.dayFormat.string(from: Date())
        return PlaceInfo(snow: [.init(kind: "powder", count: 5), .init(kind: "wind", count: 2)],
                         latest: .init(kind: "powder", date: today), reports: 7,
                         averages: .init(days: 38, vertical: 4360, distance: 25_200, runTime: 4920, liftTime: 4260, avgSpeed: 9.97, runs: 9),
                         friends: [.init(id: "a", name: "Giulia", photo: nil, days: 3, last: today),
                                   .init(id: "b", name: "Luca", photo: nil, days: 1, last: today)], mine: 2)
    }

    // MARK: Leaderboards

    /// What is sent of a day: when, and its numbers. Not where.
    static func shared(_ day: DaySummary) -> [String: Any] {
        let format = DateFormatter()
        format.calendar = Calendar(identifier: .gregorian)
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd"
        return ["date": format.string(from: day.start), "vertical": day.stats.vertical, "runs": day.stats.runs,
                "distance": day.stats.runDistance, "time": day.stats.runTime > 0 ? day.stats.runTime : day.stats.totalTime,
                "maxSpeed": day.stats.maxSpeed]
    }

    /// Sends the days of a season, then reads the friends and the leaderboard of that season.
    @MainActor func refresh(season: Season, days: [DaySummary]) async {
        guard signedIn, !demo else { return }
        await run {
            let mine = days.filter { $0.season == season }.prefix(400).map { Self.shared($0) }
            _ = try await self.call("PUT", "/v1/me/seasons/\(season.year)", ["days": Array(mine)])
            struct Friends: Decodable { let friends: [Friend] }
            let friendsData = try await self.call("GET", "/v1/friends")
            self.friends = try JSONDecoder().decode(Friends.self, from: friendsData).friends
            self.keepFriends()
            struct Board: Decodable { let rows: [BoardRow] }
            let boardData = try await self.call("GET", "/v1/board?season=\(season.year)")
            self.rows = try JSONDecoder().decode(Board.self, from: boardData).rows
        }
        await sharePistes(days)
        await loadLive()
    }

    // MARK: The challenge on the pistes

    /// Whether the best times on the pistes go to the friends: off unless turned on.
    static var sharesPistes: Bool { UserDefaults.standard.bool(forKey: Prefs.sharePistes) }

    /// Sends the pistes skied with the best time on each, if the challenge is on. Silent.
    @MainActor func sharePistes(_ days: [DaySummary]) async {
        guard signedIn, !demo, Self.sharesPistes else { return }
        let pistes = PisteBook.entries(days).compactMap { PisteBook.shared($0) }.prefix(300)
        _ = try? await call("PUT", "/v1/me/pistes", ["pistes": Array(pistes)])
    }

    /// Takes the pistes back from the server: the challenge was turned off.
    @MainActor func stopPistes() async {
        guard signedIn, !demo else { return }
        _ = try? await call("DELETE", "/v1/me/pistes")
    }

    /// Who among you and your friends skied a piste, the fastest first. nil when it cannot be asked.
    func pisteBoard(_ entry: PisteEntry) async -> [PisteRow]? {
        if demo { return Self.demoBoard(entry) }
        guard signedIn, Self.sharesPistes else { return nil }
        var parts = URLComponents()
        parts.queryItems = [URLQueryItem(name: "name", value: entry.name), URLQueryItem(name: "lat", value: String(format: "%.2f", entry.lat)),
                            URLQueryItem(name: "lon", value: String(format: "%.2f", entry.lon))]
        struct Answer: Decodable { let rows: [PisteRow] }
        guard let query = parts.percentEncodedQuery, let data = try? await call("GET", "/v1/pistes?" + query),
              let answer = try? JSONDecoder().decode(Answer.self, from: data) else { return nil }
        return answer.rows
    }

    /// For the pictures: you between two friends.
    private static func demoBoard(_ entry: PisteEntry) -> [PisteRow] {
        guard let best = entry.best else { return [] }
        let day = PlaceInfo.dayFormat.string(from: best.date)
        return [PisteRow(id: "b", name: "Luca", photo: nil, me: false, best: best.seconds * 0.93, speed: entry.topSpeed * 1.08, runs: 4, date: day),
                PisteRow(id: "me", name: "Marco", photo: nil, me: true, best: best.seconds, speed: entry.topSpeed, runs: entry.count, date: day),
                PisteRow(id: "a", name: "Giulia", photo: nil, me: false, best: best.seconds * 1.12, speed: entry.topSpeed * 0.94, runs: 7, date: day)]
    }

    // MARK: Meeting points

    /// Sets where to meet, for your friends: it replaces the one you had. True when done.
    @MainActor func setMeeting(lat: Double, lon: Double, label: String, when: Date?) async -> Bool {
        if demo {
            let now = Date().timeIntervalSince1970 * 1000
            meetings.removeAll { $0.mine }
            meetings.insert(Meeting(id: "me", name: "Marco", photo: nil, mine: true, lat: lat, lon: lon, label: label,
                                    when: when.map { $0.timeIntervalSince1970 * 1000 }, until: now + 3_600_000, at: now,
                                    answers: Self.demoAnswers), at: 0)
            return true
        }
        var done = false
        await run {
            var body: [String: Any] = ["lat": lat, "lon": lon, "label": label]
            if let when { body["when"] = (when.timeIntervalSince1970 * 1000).rounded() }
            let data = try await self.call("PUT", "/v1/me/meeting", body)
            struct Answer: Decodable { let meetings: [Meeting] }
            self.take(try JSONDecoder().decode(Answer.self, from: data).meetings)
            done = true
        }
        return done
    }

    /// Tells the server in which area you are skiing, to the kilometer; the answer has the places
    /// to meet you are asked to. Silent: a recording must not show errors for this.
    @MainActor func sendPresence(_ point: TrackPoint) async {
        guard signedIn, !demo else { return }
        struct Answer: Decodable { let meetings: [Meeting] }
        let body = ["lat": (point.lat * 100).rounded() / 100, "lon": (point.lon * 100).rounded() / 100]
        guard let data = try? await call("PUT", "/v1/me/presence", body),
              let answer = try? JSONDecoder().decode(Answer.self, from: data) else { return }
        take(answer.meetings)
    }

    /// Takes back from the server where you are skiing: the invitations no longer arrive.
    @MainActor func stopPresence() async {
        Presence.reset()
        guard signedIn, !demo else { return }
        struct Answer: Decodable { let meetings: [Meeting] }
        guard let data = try? await call("DELETE", "/v1/me/presence"),
              let answer = try? JSONDecoder().decode(Answer.self, from: data) else { return }
        take(answer.meetings)
    }

    /// Says to a friend whether you are coming to the place they set. It can be said again.
    @MainActor func answer(_ meeting: Meeting, coming: Bool) async {
        if demo {
            if let i = meetings.firstIndex(where: { $0.id == meeting.id }) { meetings[i].answer = coming ? "yes" : "no" }
            return
        }
        await run {
            let data = try await self.call("PUT", "/v1/meetings/\(meeting.id)/answer", ["coming": coming])
            struct Answer: Decodable { let meetings: [Meeting] }
            self.take(try JSONDecoder().decode(Answer.self, from: data).meetings)
        }
    }

    /// The places to meet as the server has them now: kept, and what is new in them is said with
    /// a notification (a friend asks, a friend answered).
    private func take(_ new: [Meeting]) {
        meetings = new
        MeetingNews.tell(new)
    }

    /// For the pictures: one friend coming, one not, one who has not answered.
    private static let demoAnswers = [MeetingAnswer(id: "a", name: "Giulia", photo: nil, answer: "yes"),
                                      MeetingAnswer(id: "b", name: "Luca", photo: nil, answer: "no"),
                                      MeetingAnswer(id: "c", name: "Sara", photo: nil, answer: nil)]

    /// Takes your meeting point back.
    @MainActor func clearMeeting() async {
        if demo {
            meetings.removeAll { $0.mine }
            return
        }
        await run {
            let data = try await self.call("DELETE", "/v1/me/meeting")
            struct Answer: Decodable { let meetings: [Meeting] }
            self.take(try JSONDecoder().decode(Answer.self, from: data).meetings)
        }
    }

    // MARK: Live positions

    /// Tells the friends where you are. Silent: a recording must not show errors for this.
    @MainActor func sendPosition(_ point: TrackPoint, phase: String) async {
        guard signedIn, !demo else { return }
        struct Answer: Decodable { let friends: [LiveFriend]; let meetings: [Meeting]? }
        // The answer has the friends who share: with the iPhone in a pocket this is the only
        // moment they are asked for, and the moment to say that one is close.
        guard let data = try? await call("PUT", "/v1/me/position", ["lat": point.lat, "lon": point.lon, "alt": point.alt,
                                                                      "speed": max(0, point.speed), "phase": phase]),
              let answer = try? JSONDecoder().decode(Answer.self, from: data) else { return }
        live = answer.friends
        if let meetings = answer.meetings { take(meetings) }
        Nearby.check(lat: point.lat, lon: point.lon, friends: live)
    }

    /// Takes your position back from the server.
    @MainActor func stopSharing() async {
        guard signedIn, !demo else { return }
        _ = try? await call("DELETE", "/v1/me/position")
    }

    /// Where the friends who share are now. Silent too: it is asked again in half a minute.
    @MainActor func loadLive() async {
        guard signedIn, !demo else { return }
        struct Answer: Decodable { let friends: [LiveFriend]; let meetings: [Meeting]? }
        guard let data = try? await call("GET", "/v1/friends/positions"),
              let answer = try? JSONDecoder().decode(Answer.self, from: data) else { return }
        live = answer.friends
        if let meetings = answer.meetings { take(meetings) }
        // While a day is recorded: is anyone close?
        let recorder = Shared.recorder
        if recorder.state == .recording, let me = recorder.lastPoint, Date().timeIntervalSince(me.t) < 120 {
            Nearby.check(lat: me.lat, lon: me.lon, friends: live)
        }
    }

    // MARK: The server

    /// Runs a piece of work with the server, showing that it is busy and what went wrong.
    @MainActor private func run(_ work: @MainActor () async throws -> Void) async {
        guard !demo else { return }
        busy = true
        defer { busy = false }
        do {
            try await work()
            error = nil
        } catch {
            if let failure = error as? SocialError, case .server("signed out") = failure { forget() }
            if let words = Self.words(for: error) { self.error = words }
        }
    }

    /// What to say of something that went wrong with the server. Nothing when the request was
    /// only interrupted: the screen that asked was left, or asked again. That is not the server
    /// out of reach.
    static func words(for failure: Error) -> String? {
        if failure is CancellationError { return nil }
        if let url = failure as? URLError, url.code == .cancelled { return nil }
        if let known = failure as? SocialError { return known.localizedDescription }
        return SocialError.offline.localizedDescription
    }

    private func call(_ method: String, _ path: String, _ body: [String: Any]? = nil, signed: Bool = true, raw: Data? = nil) async throws -> Data {
        guard let url = URL(string: path, relativeTo: server) else { throw SocialError.offline }
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.httpMethod = method
        request.setValue("SkiApex iOS app", forHTTPHeaderField: "User-Agent")
        if signed, let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else if let raw {
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            request.httpBody = raw
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let failure as URLError where failure.code == .networkConnectionLost && method != "POST" {
            // The connection kept from before was gone (the app was away, the network changed):
            // once more, on a new one.
            (data, response) = try await URLSession.shared.data(for: request)
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw SocialError.offline }
        if (200..<300).contains(status) { return data }
        let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
        throw SocialError.server(code ?? "status \(status)")
    }
}
