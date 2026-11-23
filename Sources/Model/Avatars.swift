import Foundation
import UIKit

/// The profile pictures: made small before they are sent, and kept on the iPhone once seen, so
/// that each is asked to the server only once.
enum Avatars {
    /// The side of the square sent to the server, in pixels.
    static let side: CGFloat = 320
    /// The server takes pictures up to 100 KB.
    static let maxBytes = 95 * 1024

    private static let memory = NSCache<NSString, UIImage>()

    private static var folder: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static func name(_ id: String, _ version: Double) -> String {
        // Only letters and digits of the id: it becomes the name of a file.
        "\(id.filter { $0.isLetter || $0.isNumber || $0 == "-" })-\(Int(version))"
    }

    /// One or two letters of a name, for who has no picture.
    static func initials(of name: String) -> String {
        let words = name.split(whereSeparator: { " ._-".contains($0) })
        let letters = words.count > 1 ? words.prefix(2).compactMap(\.first) : Array(name.prefix(2))
        return String(letters).uppercased()
    }

    /// A picture as the server wants it: the square in its middle, 320 pixels wide, as a JPEG
    /// light enough to be taken.
    static func prepare(_ image: UIImage) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = side / min(size.width, size.height)
        let drawn = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let square = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2, width: drawn.width, height: drawn.height))
        }
        for quality in [0.82, 0.7, 0.55, 0.4] {
            if let data = square.jpegData(compressionQuality: quality), data.count <= maxBytes { return data }
        }
        return nil
    }

    /// The picture of an account, if it was seen before.
    static func image(id: String, version: Double) -> UIImage? {
        let key = name(id, version)
        if let kept = memory.object(forKey: key as NSString) { return kept }
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(key + ".jpg")), let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: key as NSString)
        return image
    }

    /// Keeps a picture that came from the server, or that was just sent to it.
    @discardableResult static func keep(_ data: Data, id: String, version: Double) -> UIImage? {
        guard version > 0, let image = UIImage(data: data) else { return nil }
        let key = name(id, version)
        memory.setObject(image, forKey: key as NSString)
        try? data.write(to: folder.appendingPathComponent(key + ".jpg"), options: .atomic)
        return image
    }
}
