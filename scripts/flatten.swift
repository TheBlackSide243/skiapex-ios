// Takes the alpha channel off pictures, in place: the App Store wants the icon of an app without
// one, and going through JPEG, as before, left a noise in them that made the app much heavier.
// Usage: swift scripts/flatten.swift <picture.png>...
import CoreGraphics
import Foundation
import ImageIO

for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        FileHandle.standardError.write(Data("cannot read \(path)\n".utf8))
        exit(1)
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let flat = context.makeImage(),
          let out = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { exit(1) }
    CGImageDestinationAddImage(out, flat, nil)
    guard CGImageDestinationFinalize(out) else { exit(1) }
}
