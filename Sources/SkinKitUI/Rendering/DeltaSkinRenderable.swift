#if canImport(UIKit)
import UIKit
import SkinKitCore

/// A skin that can draw its own artwork.
///
/// `DeltaSkinProtocol` in SkinKitCore is data only. In Provenance, `image(for:)`,
/// `thumbnail(for:maxDimension:)` and `loadThumbstickImage(named:)` were `DeltaSkinProtocol`
/// requirements; they moved here as a refining protocol so calls through
/// `any DeltaSkinRenderable` still reach `DeltaSkin`'s cached implementations. (`loadThumbstickImage`
/// was a requirement on purpose, so extension methods would not do.) Method names are unchanged.
public protocol DeltaSkinRenderable: DeltaSkinProtocol {
    /// Get the skin image for given traits.
    func image(for traits: DeltaSkinTraits) async throws -> UIImage

    /// Get a small preview image whose longest side is about `maxDimension` points.
    func thumbnail(for traits: DeltaSkinTraits, maxDimension: CGFloat) async throws -> UIImage

    /// Thumbstick or button-art image from the skin's assets.
    func loadThumbstickImage(named: String) async throws -> UIImage
}

public extension DeltaSkinRenderable {
    /// Default: render the full-size image and scale it down. Conformers that can render
    /// directly at thumbnail size (``DeltaSkin``) override this to avoid the large intermediate.
    func thumbnail(for traits: DeltaSkinTraits, maxDimension: CGFloat) async throws -> UIImage {
        let image = try await image(for: traits)
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let size = CGSize(width: image.size.width * maxDimension / longest, height: image.size.height * maxDimension / longest)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Default: read the thumbstick art straight from the skin's assets (uncached).
    func loadThumbstickImage(named: String) async throws -> UIImage {
        // Load the asset data
        let assetData = try loadAssetData(named)

        // Create image from PDF data since thumbsticks are PDFs
        if named.hasSuffix(".pdf") {
            guard let image = UIImage(pdfData: assetData) else {
                throw DeltaSkinError.invalidPDF
            }
            return image
        } else {
            guard let image = UIImage(data: assetData) else {
                throw DeltaSkinError.invalidPNG
            }
            return image
        }
    }
}

public extension DeltaSkinProtocol {
    /// This skin as a ``DeltaSkinRenderable``, or `nil` when it cannot draw itself.
    ///
    /// SkinKitManager hands out `any DeltaSkinProtocol`; every skin it loads is a `DeltaSkin`,
    /// which is renderable.
    var renderable: (any DeltaSkinRenderable)? { self as? any DeltaSkinRenderable }
}

/// Hooks the rendering code needs from the host app.
public enum DeltaSkinRendering {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _defaultSkinProvider: @Sendable (DeltaSkinGameType) async -> (any DeltaSkinRenderable)? = { gameType in
        guard let skin = try? await DeltaSkinManager.shared.defaultSkin(for: gameType) else { return nil }
        return skin.renderable
    }

    /// Supplies the default skin for a game type. `DeltaSkin.image(for:)` falls back to it when the
    /// skin's own artwork cannot be loaded.
    ///
    /// The default asks `DeltaSkinManager.shared` for `defaultSkin(for:)` with no extra catalog
    /// system codes. Provenance sets this to its `SystemIdentifier`-based
    /// `DeltaSkinManager.defaultSkin(for:)`, which also passes `relatedSkinCatalogSystemCodes`, and
    /// returns `nil` for game types that have no `SystemIdentifier` (as before).
    /// Set it to `{ _ in nil }` to turn the fallback off.
    public static var defaultSkinProvider: @Sendable (DeltaSkinGameType) async -> (any DeltaSkinRenderable)? {
        get { lock.withLock { _defaultSkinProvider } }
        set { lock.withLock { _defaultSkinProvider = newValue } }
    }

    static func defaultSkin(for gameType: DeltaSkinGameType) async -> (any DeltaSkinRenderable)? {
        await defaultSkinProvider(gameType)
    }
}
#endif
