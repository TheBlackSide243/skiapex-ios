import Foundation
import Observation
import Security

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
}

struct Friend: Codable, Identifiable, Hashable {
    var id: String
    var name: String
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

    @MainActor func signOut() async {
        _ = try? await call("DELETE", "/v1/sessions")
        forget()
    }

    /// Deletes the account and everything it shared. True when done.
    @MainActor func deleteAccount(password: String) async -> Bool {
        var done = false
        await run {
            _ = try await self.call("DELETE", "/v1/me", ["password": password])
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
        inviteCode = nil
        Keychain.set(nil, for: "token")
        UserDefaults.standard.removeObject(forKey: Self.accountKey)
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
            self.rows.removeAll { $0.id == friend.id }
        }
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
            struct Board: Decodable { let rows: [BoardRow] }
            let boardData = try await self.call("GET", "/v1/board?season=\(season.year)")
            self.rows = try JSONDecoder().decode(Board.self, from: boardData).rows
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
        } catch let failure as SocialError {
            if case .server("signed out") = failure { forget() }
            error = failure.localizedDescription
        } catch {
            self.error = SocialError.offline.localizedDescription
        }
    }

    private func call(_ method: String, _ path: String, _ body: [String: Any]? = nil, signed: Bool = true) async throws -> Data {
        guard let url = URL(string: path, relativeTo: server) else { throw SocialError.offline }
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.httpMethod = method
        request.setValue("SkiApex iOS app", forHTTPHeaderField: "User-Agent")
        if signed, let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw SocialError.offline }
        if (200..<300).contains(status) { return data }
        let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
        throw SocialError.server(code ?? "status \(status)")
    }
}
