import AVFoundation
import MapKit
import SwiftUI
import UIKit

/// A short film of a day, to send or to post: the track draws itself on the map from the first
/// lift to the last run, each run in the color of its piste, while the numbers of the day count
/// up. Upright, 720 by 1280, made on the iPhone frame by frame.
enum DayFilm {
    static let size = CGSize(width: 720, height: 1280)
    static let fps: Int32 = 30
    /// Seconds the track takes to draw itself, and seconds the finished picture stays.
    static let drawing = 7.0
    static let holding = 1.8

    static var frames: Int { Int(((drawing + holding) * Double(fps)).rounded()) }

    enum Failure: Error { case noTrack, writer }

    /// One stretch of the day, already placed on the frame.
    struct Line {
        let points: [CGPoint]
        let run: Bool
        let color: UIColor
    }

    /// What is written on the frames.
    struct Words {
        let title: String
        let date: String
        let vertical: Double
        let distance: Double
        let runs: Int
        let maxSpeed: Double
    }

    /// How much of the track is drawn at a frame: slow at the two ends, then all of it.
    static func progress(at frame: Int) -> Double {
        let t = min(1, max(0, Double(frame) / (drawing * Double(fps))))
        return t * t * (3 - 2 * t)
    }

    /// Where the points of the tracks fall in a rectangle: north up, the same scale across and down.
    static func fit(_ tracks: [MapTrack], in rect: CGRect) -> (CLLocationCoordinate2D) -> CGPoint {
        let all = tracks.flatMap(\.coordinates)
        let minLat = all.map(\.latitude).min() ?? 0, maxLat = all.map(\.latitude).max() ?? 1
        let minLon = all.map(\.longitude).min() ?? 0, maxLon = all.map(\.longitude).max() ?? 1
        let kx = cos((minLat + maxLat) / 2 * .pi / 180)
        let width = max(1e-9, (maxLon - minLon) * kx), height = max(1e-9, maxLat - minLat)
        let scale = min(Double(rect.width) / width, Double(rect.height) / height)
        let dx = Double(rect.midX) - width * scale / 2, dy = Double(rect.midY) - height * scale / 2
        return { c in CGPoint(x: dx + (c.longitude - minLon) * kx * scale, y: dy + (maxLat - c.latitude) * scale) }
    }

    /// The map under the track, when Apple's maps answer in time: the place seen from above,
    /// with the track in its middle band. nil with no network.
    static func backdrop(for tracks: [MapTrack]) async -> MKMapSnapshotter.Snapshot? {
        let all = tracks.flatMap(\.coordinates)
        guard let minLat = all.map(\.latitude).min(), let maxLat = all.map(\.latitude).max(),
              let minLon = all.map(\.longitude).min(), let maxLon = all.map(\.longitude).max() else { return nil }
        let options = MKMapSnapshotter.Options()
        // Room above for the name and below for the numbers.
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max(0.004, (maxLat - minLat) * 2.1), longitudeDelta: max(0.004, (maxLon - minLon) * 1.35)))
        options.size = size
        options.traitCollection = UITraitCollection(displayScale: 1)
        options.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .realistic)
        let snapshotter = MKMapSnapshotter(options: options)
        return await withTaskGroup(of: MKMapSnapshotter.Snapshot?.self) { group in
            group.addTask { try? await snapshotter.start() }
            group.addTask {
                try? await Task.sleep(for: .seconds(8))
                snapshotter.cancel()
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Draws one frame, with the top left corner at the origin.
    static func draw(_ lines: [Line], progress: Double, words: Words, backdrop: UIImage?, in context: CGContext) {
        let frame = CGRect(origin: .zero, size: size)
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        let space = CGColorSpaceCreateDeviceRGB()
        func shade(_ colors: [UIColor], from: CGFloat, to: CGFloat) {
            guard let gradient = CGGradient(colorsSpace: space, colors: colors.map(\.cgColor) as CFArray, locations: nil) else { return }
            context.saveGState()
            context.clip(to: CGRect(x: 0, y: min(from, to), width: size.width, height: abs(to - from)))
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: from), end: CGPoint(x: 0, y: to), options: [])
            context.restoreGState()
        }
        if let backdrop {
            backdrop.draw(in: frame)
            context.setFillColor(UIColor.black.withAlphaComponent(0.22).cgColor)
            context.fill(frame)
            shade([UIColor.black.withAlphaComponent(0.72), .clear], from: 0, to: 330)
            shade([.clear, UIColor.black.withAlphaComponent(0.82)], from: size.height - 470, to: size.height)
        } else {
            shade([UIColor(red: 0.07, green: 0.13, blue: 0.21, alpha: 1), UIColor(red: 0.03, green: 0.05, blue: 0.09, alpha: 1)], from: 0, to: size.height)
        }

        // The track, as far as it got.
        let total = lines.reduce(0) { $0 + $1.points.count }
        var left = Int((Double(total) * min(1, max(0, progress))).rounded())
        var head: CGPoint?
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for line in lines {
            guard left > 0 else { break }
            let shown = Array(line.points.prefix(left))
            left -= shown.count
            guard let first = shown.first else { continue }
            head = shown.last
            guard shown.count > 1 else { continue }
            let path = CGMutablePath()
            path.move(to: first)
            for point in shown.dropFirst() { path.addLine(to: point) }
            if line.run {
                context.addPath(path)
                context.setStrokeColor(UIColor.white.withAlphaComponent(0.95).cgColor)
                context.setLineWidth(8)
                context.setLineDash(phase: 0, lengths: [])
                context.strokePath()
                context.addPath(path)
                context.setStrokeColor(line.color.cgColor)
                context.setLineWidth(4.6)
                context.strokePath()
            } else {
                context.addPath(path)
                context.setStrokeColor(UIColor.white.withAlphaComponent(0.6).cgColor)
                context.setLineWidth(2.4)
                context.setLineDash(phase: 0, lengths: [7, 7])
                context.strokePath()
                context.setLineDash(phase: 0, lengths: [])
            }
        }
        if let head, progress < 1 {
            context.setFillColor(UIColor.white.cgColor)
            context.fillEllipse(in: CGRect(x: head.x - 11, y: head.y - 11, width: 22, height: 22))
            context.setFillColor(UIColor(red: 0.96, green: 0.27, blue: 0.22, alpha: 1).cgColor)
            context.fillEllipse(in: CGRect(x: head.x - 7, y: head.y - 7, width: 14, height: 14))
        }

        // The words: where and when above, the numbers counting up below.
        func write(_ text: String, at point: CGPoint, size: CGFloat, weight: UIFont.Weight, color: UIColor = .white, width: CGFloat? = nil,
                   centered: Bool = false) {
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingTail
            style.alignment = centered ? .center : .left
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style,
            ]
            let box = CGRect(x: point.x, y: point.y, width: width ?? DayFilm.size.width - point.x - 40, height: size * 1.4)
            (text as NSString).draw(with: box, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes, context: nil)
        }
        write(words.title, at: CGPoint(x: 44, y: 96), size: 50, weight: .heavy)
        write(words.date, at: CGPoint(x: 46, y: 164), size: 26, weight: .medium, color: UIColor.white.withAlphaComponent(0.82))

        let p = min(1, max(0, progress))
        let figures: [(value: String, label: String)] = [
            (Fmt.height(words.vertical * p), String(localized: "Dislivello")),
            (Fmt.distance(words.distance * p), String(localized: "Sciati")),
            ("\(Int((Double(words.runs) * p).rounded()))", String(localized: "Discese")),
            (Fmt.speed(words.maxSpeed * p), String(localized: "Velocità max")),
        ]
        let column = (size.width - 60) / CGFloat(figures.count)
        for (i, figure) in figures.enumerated() {
            let x = 30 + CGFloat(i) * column
            write(figure.value, at: CGPoint(x: x, y: size.height - 232), size: 33, weight: .heavy, width: column, centered: true)
            write(figure.label.uppercased(), at: CGPoint(x: x, y: size.height - 184), size: 17, weight: .semibold,
                  color: UIColor.white.withAlphaComponent(0.72), width: column, centered: true)
        }
        write("SKI APEX", at: CGPoint(x: 0, y: size.height - 96), size: 20, weight: .heavy, color: UIColor.white.withAlphaComponent(0.6),
              width: size.width, centered: true)
    }

    /// The stretches of a day, lifts and runs in the order they happened, placed on the frame.
    static func lines(_ tracks: [MapTrack], place: (CLLocationCoordinate2D) -> CGPoint) -> [Line] {
        tracks.filter { $0.kind != .idle }.map { track in
            Line(points: track.coordinates.map(place), run: track.kind == .run,
                 color: UIColor(Theme.difficultyColor(track.difficulty) ?? Theme.track))
        }
    }

    /// Makes the film of a day and gives back its file. `mapped`: with the map under the track,
    /// when it can be had. `told`: how far along it is, from 0 to 1.
    static func make(_ day: SkiDay, mapped: Bool = true, told: @escaping (Double) -> Void = { _ in }) async throws -> URL {
        let tracks = MapTrack.build(points: day.points, segments: day.segments, maxPoints: 160).filter { $0.kind != .idle }
        guard tracks.contains(where: { $0.coordinates.count > 1 }) else { throw Failure.noTrack }
        let snapshot = mapped ? await backdrop(for: tracks) : nil
        let drawn: [Line]
        if let snapshot {
            drawn = lines(tracks) { snapshot.point(for: $0) }
        } else {
            drawn = lines(tracks, place: fit(tracks, in: CGRect(x: 70, y: 280, width: size.width - 140, height: size.height - 600)))
        }
        let words = Words(title: day.title ?? String(localized: "Giornata sulla neve"), date: Fmt.day(day.start),
                          vertical: day.stats.vertical, distance: day.stats.runDistance, runs: day.stats.runs, maxSpeed: day.stats.maxSpeed)

        let name = DateFormatter()
        name.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ski Apex \(name.string(from: day.start)).mp4")
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        guard writer.canAdd(input) else { throw Failure.writer }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? Failure.writer }
        writer.startSession(atSourceTime: .zero)

        let count = frames
        for frame in 0..<count {
            try Task.checkCancellation()
            var waited = 0
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(10))
                waited += 1
                if waited > 1000 { throw Failure.writer }
            }
            guard let pool = adaptor.pixelBufferPool else { throw Failure.writer }
            var made: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
            guard let buffer = made else { throw Failure.writer }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
                                       bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                       space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                // The top left corner at the origin, as the drawing wants it.
                context.translateBy(x: 0, y: size.height)
                context.scaleBy(x: 1, y: -1)
                draw(drawn, progress: progress(at: frame), words: words, backdrop: snapshot?.image, in: context)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps)) else {
                throw writer.error ?? Failure.writer
            }
            if frame % 6 == 0 { told(Double(frame) / Double(count)) }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(count), timescale: fps))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? Failure.writer }
        told(1)
        return url
    }
}
