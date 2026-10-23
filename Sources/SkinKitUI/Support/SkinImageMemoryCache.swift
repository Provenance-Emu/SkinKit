#if canImport(UIKit)
import UIKit

/// An `NSCache` of images with a real byte budget that is purged on memory warnings.
///
/// Moved from Provenance's `PVMediaCache.ImageMemoryCache` (SkinKitUI cannot depend on the
/// app). Costs are the decoded byte size of each image, so `totalCostLimit` is resident memory.
final class SkinImageMemoryCache: @unchecked Sendable {
    private let cache = NSCache<NSString, UIImage>()
    private var memoryWarningObserver: NSObjectProtocol?

    init(name: String, totalCostLimit: Int, countLimit: Int) {
        cache.name = name
        cache.totalCostLimit = totalCostLimit
        cache.countLimit = countLimit
        #if !os(watchOS)
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.removeAll()
        }
        #endif
    }

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func setImage(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString, cost: Self.decodedByteCost(of: image))
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    /// `ArtworkDownsampler.decodedByteCost(of:)`.
    static func decodedByteCost(of image: UIImage) -> Int {
        let bytesPerPixel = 4
        if let cgImage = image.cgImage {
            return cgImage.width * cgImage.height * bytesPerPixel
        }
        return Int(image.size.width * image.size.height) * bytesPerPixel
    }
}

/// Byte budgets for the skin image caches (values from Provenance's `ImageCacheBudget`).
enum SkinImageCacheBudget {
    private static let megabyte = 1024 * 1024

    /// Controller-skin preview renders.
    static let skinPreviews = 24 * megabyte

    /// Decoded controller-skin assets.
    static let skinAssets = 32 * megabyte

    static let defaultCountLimit = 100
}
#endif
