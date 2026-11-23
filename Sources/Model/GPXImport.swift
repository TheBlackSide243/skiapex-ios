import Foundation

/// Reads the track of a GPX file, from this app or from another one: every point with its time.
/// GPX has no speed, so it is worked out from the distance over a few seconds.
final class GPXImport: NSObject, XMLParserDelegate {
    private var points: [TrackPoint] = []
    private var lat: Double?
    private var lon: Double?
    private var ele: Double?
    private var time: Date?
    private var text = ""
    private var inPoint = false
    private let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let plain = ISO8601DateFormatter()

    static func points(from data: Data) -> [TrackPoint] {
        let reader = GPXImport()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.parse()
        return reader.finished()
    }

    private func finished() -> [TrackPoint] {
        var sorted = points.sorted { $0.t < $1.t }
        let n = sorted.count
        guard n > 1 else { return sorted }
        // The path between two points before and two after, over the time it took.
        var along = [Double](repeating: 0, count: n)
        for i in 1..<n { along[i] = along[i - 1] + Geo.distance(sorted[i - 1], sorted[i]) }
        for i in 0..<n {
            let a = max(0, i - 2), b = min(n - 1, i + 2)
            let dt = sorted[b].t.timeIntervalSince(sorted[a].t)
            sorted[i].speed = dt > 0 && dt <= 30 ? (along[b] - along[a]) / dt : 0
        }
        return sorted
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        text = ""
        if name == "trkpt" {
            inPoint = true
            lat = Double(attributes["lat"] ?? "")
            lon = Double(attributes["lon"] ?? "")
            ele = nil
            time = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inPoint { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard inPoint else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "ele":
            ele = Double(value)
        case "time":
            time = withFraction.date(from: value) ?? plain.date(from: value)
        case "trkpt":
            if let lat, let lon, let time {
                points.append(TrackPoint(t: time, lat: lat, lon: lon, alt: ele ?? 0, speed: 0, hAcc: 10, sAcc: -1))
            }
            inPoint = false
        default:
            break
        }
        text = ""
    }
}

enum ImportError: LocalizedError {
    case empty
    case duplicate

    var errorDescription: String? {
        switch self {
        case .empty: String(localized: "Nel file non c'è una traccia con gli orari: non posso ricavarne una giornata.")
        case .duplicate: String(localized: "Questa giornata c'è già.")
        }
    }
}
