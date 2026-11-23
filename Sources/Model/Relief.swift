import MapKit
import UIKit

/// The mountain in winter, drawn here: the snow lit from the north-west, blue in the shade, rock
/// where it is steep, firs low in the valley and a line every fifty meters. Made from the open
/// heights of the Earth (the "terrarium" tiles of Mapzen, kept by AWS as open data), one square
/// of the map at a time.
enum Relief {
    /// The heights of a square, in meters, row by row from the top-left.
    struct Heights {
        let values: [Float]
        let side: Int
    }

    /// A terrarium picture into heights: red × 256 + green + blue / 256, less 32768.
    static func heights(png: Data) -> Heights? {
        guard let image = UIImage(data: png)?.cgImage else { return nil }
        let w = image.width, h = image.height
        guard w == h, w > 1 else { return nil }
        // In the picture's own colors, so that no number is changed on the way.
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = context.data else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var values = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            values[i] = Float(bytes[i * 4]) * 256 + Float(bytes[i * 4 + 1]) + Float(bytes[i * 4 + 2]) / 256 - 32768
        }
        return Heights(values: values, side: w)
    }

    /// Meters across one point of a square of the map, at its latitude.
    static func metersPerPixel(z: Int, y: Int, side: Int) -> Double {
        let n = Double.pi - 2 * Double.pi * (Double(y) + 0.5) / pow(2, Double(z))
        let lat = atan(sinh(n))
        return 40_075_016.7 * cos(lat) / pow(2, Double(z)) / Double(side)
    }

    private static func mix(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * min(1, max(0, t)) }

    /// The colors of a square, four bytes a point (red, green, blue, 255).
    static func shade(_ heights: Heights, metersPerPixel: Double) -> [UInt8] {
        let side = heights.side, h = heights.values, mpp = Float(metersPerPixel)
        var out = [UInt8](repeating: 255, count: side * side * 4)
        let exaggeration: Float = 1.25
        for j in 0..<side {
            for i in 0..<side {
                let a = j * side + i
                let left = i > 0 ? a - 1 : a, right = i < side - 1 ? a + 1 : a
                let up = j > 0 ? a - side : a, down = j < side - 1 ? a + side : a
                // At the edges the slope is measured over one point, not two.
                let gx = (h[right] - h[left]) / (Float(right - left) * mpp)
                let gy = (h[down] - h[up]) / (Float((down - up) / side) * mpp)
                let slope = (gx * gx + gy * gy).squareRoot()
                let steep = exaggeration * slope
                let light = (exaggeration * gx * 0.55 + exaggeration * gy * 0.55 + 0.63) / (steep * steep + 1).squareRoot()
                let t = (light - 0.2) / 0.62
                var r = mix(128, 255, t), g = mix(158, 255, t), b = mix(206, 255, t)
                let rock = (slope - 0.78) / 0.5 * 0.62
                r = mix(r, 104, rock); g = mix(g, 110, rock); b = mix(b, 126, rock)
                let low = min(1, max(0, (2150 - h[a]) / 250))
                let speck: Float = (i * 7 + j * 13) % 11 < 5 ? 0.5 : 0.32
                let tree = low * speck * (slope < 0.9 ? 1 : 0.3)
                r = mix(r, 70, tree); g = mix(g, 98, tree); b = mix(b, 96, tree)
                // A line every fifty meters, a stronger one every two hundred and fifty.
                let level = (h[a] / 50).rounded()
                let near = abs(h[a] - level * 50) / (slope * mpp + 0.000_001)
                if near < 0.75 {
                    let strong = Int(level) % 5 == 0
                    let alpha = (strong ? 0.34 : 0.15) * (1 - near / 0.75)
                    r = mix(r, 58, alpha); g = mix(g, 88, alpha); b = mix(b, 146, alpha)
                }
                out[a * 4] = UInt8(min(255, max(0, r)))
                out[a * 4 + 1] = UInt8(min(255, max(0, g)))
                out[a * 4 + 2] = UInt8(min(255, max(0, b)))
            }
        }
        return out
    }

    /// The colors as a picture, to give to the map.
    static func png(_ colors: [UInt8], side: Int) -> Data? {
        guard colors.count == side * side * 4,
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let data = context.data else { return nil }
        colors.withUnsafeBytes { data.copyMemory(from: $0.baseAddress!, byteCount: colors.count) }
        guard let image = context.makeImage() else { return nil }
        return UIImage(cgImage: image).pngData()
    }

    /// A square of heights as it came from the internet into a square of the winter map.
    static func tile(from terrarium: Data, z: Int, y: Int) -> Data? {
        guard let heights = heights(png: terrarium) else { return nil }
        return png(shade(heights, metersPerPixel: metersPerPixel(z: z, y: y, side: heights.side)), side: heights.side)
    }
}

/// The winter map over Apple's: from the zoom of a valley in, each square is asked for as heights
/// and drawn by `Relief`. Farther out, and where a square does not arrive, Apple's map shows.
final class ReliefOverlay: MKTileOverlay {
    /// The squares already drawn, kept while the app is open.
    private static let drawn: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 400
        return cache
    }()

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 120 << 20)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    init() {
        super.init(urlTemplate: nil)
        canReplaceMapContent = false
        minimumZ = 10
        maximumZ = 14
        tileSize = CGSize(width: 256, height: 256)
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let key = "\(path.z)/\(path.x)/\(path.y)" as NSString
        if let kept = Self.drawn.object(forKey: key) {
            result(kept as Data, nil)
            return
        }
        guard let url = URL(string: "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/\(path.z)/\(path.x)/\(path.y).png") else {
            result(nil, URLError(.badURL))
            return
        }
        Self.session.dataTask(with: url) { data, _, error in
            guard let data, let tile = Relief.tile(from: data, z: path.z, y: path.y) else {
                result(nil, error ?? URLError(.cannotDecodeContentData))
                return
            }
            Self.drawn.setObject(tile as NSData, forKey: key)
            result(tile, nil)
        }.resume()
    }
}
