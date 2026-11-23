import MapKit
import UIKit

/// The map of the app, drawn here one square at a time from the open heights of the Earth (the
/// "terrarium" tiles of Mapzen, kept by AWS as open data). Up close the mountain in winter: the
/// snow lit from the north-west, blue in the shade, rock where it is steep, firs low in the
/// valley and a line every fifty meters. From far away the mountains at night.
enum Relief {
    /// The heights of a square, in meters, row by row from the top-left.
    struct Heights {
        let values: [Float]
        let side: Int
    }

    /// From this zoom in the map is snow; farther out, the mountains at night.
    static let snowFrom = 10
    /// From this zoom in a square is drawn on twice the points, for the screens of today.
    static let fineFrom = 12

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
        let values = [Float](unsafeUninitializedCapacity: w * h) { buffer, count in
            let out = buffer.baseAddress!
            for i in 0..<(w * h) {
                out[i] = Float(bytes[i * 4]) * 256 + Float(bytes[i * 4 + 1]) + Float(bytes[i * 4 + 2]) / 256 - 32768
            }
            count = w * h
        }
        return Heights(values: values, side: w)
    }

    /// Meters across one point of a square of the map, at its latitude.
    static func metersPerPixel(z: Int, y: Int, side: Int) -> Double {
        let n = Double.pi - 2 * Double.pi * (Double(y) + 0.5) / pow(2, Double(z))
        let lat = atan(sinh(n))
        return 40_075_016.7 * cos(lat) / pow(2, Double(z)) / Double(side)
    }

    @inline(__always) private static func mix(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * min(1, max(0, t)) }
    @inline(__always) private static func byte(_ x: Float) -> UInt8 { UInt8(min(255, max(0, x))) }

    /// The same heights on twice as many points a side, each between its neighbors and a little
    /// smoothed: the lines every fifty meters come out thin, and the steps of the heights do not show.
    static func doubled(_ heights: Heights) -> Heights {
        let side = heights.side, wide = side * 2
        let values = heights.values.withUnsafeBufferPointer { source -> [Float] in
            let h = source.baseAddress!
            return [Float](unsafeUninitializedCapacity: wide * wide) { buffer, count in
                let out = buffer.baseAddress!
                for j in 0..<wide {
                    let y = min(Float(side - 1), max(0, (Float(j) + 0.5) / 2 - 0.5))
                    let y0 = Int(y), y1 = min(side - 1, y0 + 1), fy = y - Float(y0)
                    for i in 0..<wide {
                        let x = min(Float(side - 1), max(0, (Float(i) + 0.5) / 2 - 0.5))
                        let x0 = Int(x), x1 = min(side - 1, x0 + 1), fx = x - Float(x0)
                        let top = h[y0 * side + x0] * (1 - fx) + h[y0 * side + x1] * fx
                        let bottom = h[y1 * side + x0] * (1 - fx) + h[y1 * side + x1] * fx
                        out[j * wide + i] = top * (1 - fy) + bottom * fy
                    }
                }
                count = wide * wide
            }
        }
        return Heights(values: values, side: wide)
    }

    /// Each height with its eight neighbors, where it has them: what is left of the steps of the
    /// heights, when a square is looked at from very close, goes away.
    static func smoothed(_ heights: Heights) -> Heights {
        let side = heights.side
        let values = heights.values.withUnsafeBufferPointer { source -> [Float] in
            let h = source.baseAddress!
            return [Float](unsafeUninitializedCapacity: side * side) { buffer, count in
                let out = buffer.baseAddress!
                for j in 0..<side {
                    let j0 = max(0, j - 1), j1 = min(side - 1, j + 1)
                    for i in 0..<side {
                        let i0 = max(0, i - 1), i1 = min(side - 1, i + 1)
                        var sum: Float = 0
                        for y in j0...j1 { for x in i0...i1 { sum += h[y * side + x] } }
                        out[j * side + i] = sum / Float((j1 - j0 + 1) * (i1 - i0 + 1))
                    }
                }
                count = side * side
            }
        }
        return Heights(values: values, side: side)
    }

    /// The mountains from far away, at night: dark blue, lighter where they face the north-west
    /// and where they are high, the sea darker still. Four bytes a point (red, green, blue, 255).
    static func night(_ heights: Heights, metersPerPixel: Double) -> [UInt8] {
        let side = heights.side, mpp = Float(metersPerPixel)
        // The farther away, the more the mountains are raised to be seen.
        let exaggeration = min(12, max(1.5, mpp / 85))
        return heights.values.withUnsafeBufferPointer { source -> [UInt8] in
            let h = source.baseAddress!
            return [UInt8](unsafeUninitializedCapacity: side * side * 4) { buffer, count in
                let out = buffer.baseAddress!
                for j in 0..<side {
                    for i in 0..<side {
                        let a = j * side + i
                        let left = i > 0 ? a - 1 : a, right = i < side - 1 ? a + 1 : a
                        let up = j > 0 ? a - side : a, down = j < side - 1 ? a + side : a
                        let gx = (h[right] - h[left]) / (Float(right - left) * mpp) * exaggeration
                        let gy = (h[down] - h[up]) / (Float((down - up) / side) * mpp) * exaggeration
                        let light = (gx * 0.55 + gy * 0.55 + 0.63) / (gx * gx + gy * gy + 1).squareRoot()
                        let t = (light - 0.25) / 0.6, high = max(0, (h[a] - 400) / 3200)
                        var r = mix(20, 54, t) + 14 * high, g = mix(27, 70, t) + 16 * high, b = mix(50, 108, t) + 20 * high
                        if h[a] <= 0.5 { r = 13; g = 18; b = 36 }
                        out[a * 4] = byte(r)
                        out[a * 4 + 1] = byte(g)
                        out[a * 4 + 2] = byte(b)
                        out[a * 4 + 3] = 255
                    }
                }
                count = side * side * 4
            }
        }
    }

    /// The colors of a square of snow, four bytes a point (red, green, blue, 255).
    static func shade(_ heights: Heights, metersPerPixel: Double) -> [UInt8] {
        let side = heights.side, mpp = Float(metersPerPixel)
        let exaggeration: Float = 1.25
        return heights.values.withUnsafeBufferPointer { source -> [UInt8] in
            let h = source.baseAddress!
            return [UInt8](unsafeUninitializedCapacity: side * side * 4) { buffer, count in
                let out = buffer.baseAddress!
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
                        out[a * 4] = byte(r)
                        out[a * 4 + 1] = byte(g)
                        out[a * 4 + 2] = byte(b)
                        out[a * 4 + 3] = 255
                    }
                }
                count = side * side * 4
            }
        }
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

    /// A square of heights as it came from the internet into a square of the map.
    static func tile(from terrarium: Data, z: Int, y: Int) -> Data? {
        guard var heights = heights(png: terrarium) else { return nil }
        if z < snowFrom {
            return png(night(heights, metersPerPixel: metersPerPixel(z: z, y: y, side: heights.side)), side: heights.side)
        }
        if z >= fineFrom { heights = doubled(heights) }
        if z >= 14 { heights = smoothed(heights) }
        return png(shade(heights, metersPerPixel: metersPerPixel(z: z, y: y, side: heights.side)), side: heights.side)
    }
}

/// The map of the app over Apple's: each square is asked for as heights and drawn by `Relief`,
/// as snow from the zoom of a valley in and as mountains at night farther out. The names stay
/// Apple's, and where a square does not arrive Apple's map shows.
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
        config.httpMaximumConnectionsPerHost = 8
        return URLSession(configuration: config)
    }()

    init() {
        super.init(urlTemplate: nil)
        canReplaceMapContent = false
        minimumZ = 4
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
            // Drawn away from the queue of the answers, several squares at a time.
            DispatchQueue.global(qos: .userInitiated).async {
                guard let data, let tile = Relief.tile(from: data, z: path.z, y: path.y) else {
                    result(nil, error ?? URLError(.cannotDecodeContentData))
                    return
                }
                Self.drawn.setObject(tile as NSData, forKey: key)
                result(tile, nil)
            }
        }.resume()
    }
}
