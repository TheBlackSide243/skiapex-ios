import Foundation
import Observation

/// A copy of the days in iCloud, in the app's own folder there: every day saved on this iPhone
/// goes up, every day saved on another one comes down, and a day deleted on one is deleted on
/// the others. Only in the builds signed with iCloud (the one from TestFlight); in the others it
/// says that it cannot, and nothing leaves the iPhone.
@Observable final class CloudCopy {
    static let shared = CloudCopy()

    enum State: Equatable {
        /// Not turned on.
        case off
        /// This build has no iCloud, or the iPhone is not signed in to it.
        case unavailable
        case working
        case done
        case failed(String)
    }

    private(set) var state = State.off
    private(set) var last: Date?
    /// What the last pass found and did.
    private(set) var outcome = Outcome()

    /// What a pass did: days copied up and down, days deleted on each side, days still on their
    /// way down from iCloud, and how many days are in iCloud now.
    struct Outcome: Equatable {
        var up = 0
        var down = 0
        var removedThere = 0
        var removedHere = 0
        var waiting = 0
        var inCloud = 0

        /// The days of this iPhone are not what they were: the list is to be read again.
        var changedHere: Bool { down > 0 || removedHere > 0 }
    }

    /// The file, in both folders, with the days deleted on purpose and when.
    static let deletedFile = "cancellate.json"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: Prefs.cloud) }

    /// The folder of the days in iCloud. nil when this build has no iCloud or the iPhone is not
    /// signed in. Asked away from the main thread, as Apple wants.
    static func folder() async -> URL? {
        await Task.detached(priority: .utility) {
            FileManager.default.url(forUbiquityContainerIdentifier: nil)?
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("Giornate", isDirectory: true)
        }.value
    }

    /// Brings the days of this iPhone and the ones in iCloud level, if the copy is on.
    @MainActor func sync(_ library: Library) async {
        guard Self.isOn, !Demo.isOn else {
            state = .off
            return
        }
        guard state != .working else { return }
        state = .working
        guard let cloud = await Self.folder() else {
            state = .unavailable
            return
        }
        let local = library.folder
        do {
            let result = try await Task.detached(priority: .utility) { try CloudCopy.level(local: local, cloud: cloud) }.value
            if result.changedHere { library.reload() }
            outcome = result
            last = Date()
            state = .done
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Turned off: nothing is asked any more. What is in iCloud stays there.
    @MainActor func stop() {
        state = .off
    }

    // MARK: Two folders brought level

    /// The identifier of the day a file holds, when its name is one.
    static func dayID(_ url: URL) -> String? {
        guard url.pathExtension == "json" else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        return UUID(uuidString: name) == nil ? nil : name
    }

    /// The days deleted on purpose, as a folder remembers them: identifier and when, in seconds.
    static func deleted(in dir: URL) -> [String: Double] {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(deletedFile)) else { return [:] }
        return (try? JSONDecoder().decode([String: Double].self, from: data)) ?? [:]
    }

    private static func write(_ deleted: [String: Double], in dir: URL) {
        // Kept for a year and a bit: an iPhone not opened for longer brings its days back.
        let old = Date().timeIntervalSince1970 - 400 * 86_400
        let kept = deleted.filter { $0.value > old }
        guard kept != Self.deleted(in: dir) else { return }
        if let data = try? JSONEncoder().encode(kept) { try? data.write(to: dir.appendingPathComponent(deletedFile), options: .atomic) }
    }

    /// Remembers that a day was deleted on purpose, so that a copy elsewhere does not bring it back.
    static func bury(_ id: UUID, in dir: URL, at date: Date = Date()) {
        var all = deleted(in: dir)
        all[id.uuidString] = date.timeIntervalSince1970
        write(all, in: dir)
    }

    /// Whether a file of iCloud is here in full and can be read without waiting.
    static func ready(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
              values.isUbiquitousItem == true else { return true }
        if values.ubiquitousItemDownloadingStatus == .current { return true }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        return false
    }

    /// Every day in one folder and not in the other is copied across; of a day in both, the one
    /// changed last wins; a day deleted on purpose goes from both, unless it was saved again
    /// after. `ready` tells whether a file of the second folder can be read now.
    static func level(local: URL, cloud: URL, ready: (URL) -> Bool = CloudCopy.ready) throws -> Outcome {
        let fm = FileManager.default
        try fm.createDirectory(at: cloud, withIntermediateDirectories: true)
        var out = Outcome()

        func modified(_ url: URL) -> Double {
            ((try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        }
        func days(in dir: URL) -> [String: URL] {
            var found: [String: URL] = [:]
            for url in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                if let id = dayID(url) { found[id] = url }
            }
            return found
        }
        /// One file over another, keeping the date it was changed: the two stay the same.
        func put(_ source: URL, over target: URL) throws {
            let data = try Data(contentsOf: source)
            try data.write(to: target, options: .atomic)
            let date = Date(timeIntervalSince1970: modified(source))
            try? fm.setAttributes([.modificationDate: date], ofItemAtPath: target.path)
        }

        // The days of iCloud not downloaded yet: asked for, and counted as on their way.
        for url in (try? fm.contentsOfDirectory(at: cloud, includingPropertiesForKeys: nil, options: [])) ?? [] {
            let name = url.lastPathComponent
            guard name.hasPrefix("."), name.hasSuffix(".icloud") else { continue }
            let real = cloud.appendingPathComponent(String(name.dropFirst().dropLast(7)))
            guard dayID(real) != nil else { continue }
            try? fm.startDownloadingUbiquitousItem(at: real)
            out.waiting += 1
        }

        var here = days(in: local)
        var there = days(in: cloud)

        // Deleted on purpose, on this iPhone or on another one.
        var gone = deleted(in: local).merging(deleted(in: cloud)) { max($0, $1) }
        for (id, at) in gone {
            let copies = [here[id], there[id]].compactMap { $0 }
            if copies.contains(where: { modified($0) > at + 1 }) {
                // Saved again after: it is back.
                gone[id] = nil
                continue
            }
            if let file = here[id] {
                try? fm.removeItem(at: file)
                here[id] = nil
                out.removedHere += 1
            }
            if let file = there[id] {
                try? fm.removeItem(at: file)
                there[id] = nil
                out.removedThere += 1
            }
        }

        for (id, mine) in here {
            guard let theirs = there[id] else {
                try put(mine, over: cloud.appendingPathComponent(mine.lastPathComponent))
                out.up += 1
                continue
            }
            guard ready(theirs) else {
                out.waiting += 1
                continue
            }
            let a = modified(mine), b = modified(theirs)
            guard abs(a - b) > 2 else { continue }
            // Changed on one side: unless the two are the same anyway.
            if let x = try? Data(contentsOf: mine), let y = try? Data(contentsOf: theirs), x == y { continue }
            if a > b {
                try put(mine, over: theirs)
                out.up += 1
            } else {
                try put(theirs, over: mine)
                out.down += 1
            }
        }
        for (id, theirs) in there where here[id] == nil {
            guard ready(theirs) else {
                out.waiting += 1
                continue
            }
            try put(theirs, over: local.appendingPathComponent(theirs.lastPathComponent))
            out.down += 1
        }

        write(gone, in: local)
        write(gone, in: cloud)
        out.inCloud = days(in: cloud).count
        return out
    }
}
