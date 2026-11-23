import Photos
import SwiftUI
import UIKit

/// The pictures taken during a day, from the photo library: found by their time, never copied or
/// sent anywhere.
enum DayPhotos {
    static var allowed: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    static var canAsk: Bool { PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined }

    static func ask() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// The pictures and videos between two moments, oldest first, at most `limit`.
    static func assets(from start: Date, to end: Date, limit: Int = 60) -> [PHAsset] {
        guard allowed else { return [] }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@", start as NSDate, end as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.fetchLimit = limit
        var out: [PHAsset] = []
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in out.append(asset) }
        return out
    }

    static func image(_ asset: PHAsset, side: CGFloat) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            // One answer only, so that the continuation is resumed once.
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.resizeMode = .fast
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: side, height: side),
                                                  contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

/// One picture of the day, square, loaded when it comes on screen.
struct PhotoThumb: View {
    let asset: PHAsset
    var side: CGFloat = 96
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Theme.deep
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
            if asset.mediaType == .video {
                Image(systemName: "play.fill").font(.caption).foregroundStyle(.white).shadow(radius: 3)
            }
        }
        .frame(width: side, height: side)
        .clipShape(Theme.roundSmall)
        .overlay(Theme.roundSmall.strokeBorder(Theme.line, lineWidth: 1))
        .task(id: asset.localIdentifier) {
            image = await DayPhotos.image(asset, side: side * UIScreen.main.scale)
        }
        .accessibilityLabel(Text("Foto delle \(Fmt.time(asset.creationDate ?? Date()))"))
    }
}

/// A picture of the day, as big as the screen.
struct PhotoViewer: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.5), in: Circle())
            }
            .padding(16)
            .accessibilityLabel(Text("Chiudi"))
        }
        .task {
            image = await DayPhotos.image(asset, side: 2048)
        }
    }
}
