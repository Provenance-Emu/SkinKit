#if canImport(UIKit)
import UIKit
import ZIPFoundation
import SkinKitCore

// Image rendering for `DeltaSkin`: PDF/SVG/PNG rasterization, the in-memory image cache, the
// on-disk raster cache, thumbnails and thumbstick art. Moved out of Provenance's
// `Models/DeltaSkin.swift`; SkinKitCore keeps the model and decoding only.
//
// Cache keys, the disk-cache directory (`DeltaSkinImageCache`), the raster revision and the
// filename hash are unchanged, so rasters already on a device stay valid.

extension DeltaSkin: DeltaSkinRenderable {

    /// Asset names to try for `traits`, best first: a selected theme's artwork for these traits,
    /// then the skin's own artwork for `rep`.
    func assetCandidates(for rep: DeltaSkin.RepresentationInfo, traits: DeltaSkinTraits) -> [String] {
        if let themeId = selectedThemeId,
           let theme = availableThemes.first(where: { $0.id == themeId }),
           let themeAsset = theme.assets?[traits.device.rawValue]?[traits.displayType.rawValue]?[traits.orientation.rawValue] {
            // Prepend theme candidates so they are tried first, falling back to base skin
            ILOG("skins: Theme '\(themeId)' override candidates: \(themeAsset.candidates())")
            return themeAsset.candidates() + rep.assets.candidates()
        }
        return rep.assets.candidates()
    }

    /// Cache for decoded images keyed by skin identifier + traits + asset filename.
    ///
    /// Skin assets are rendered full-screen and drive hit-testing geometry, so
    /// they must stay at full resolution — but the cache itself needs a byte
    /// budget. It was previously a plain `Dictionary` capped at 50 entries by
    /// count, trimmed via `keys.prefix(10)` (unordered, so not FIFO despite the
    /// comment) and never purged on memory pressure.
    private static let imageCache = SkinImageMemoryCache(
        name: "DeltaSkinImageCache",
        totalCostLimit: SkinImageCacheBudget.skinAssets,
        countLimit: SkinImageCacheBudget.defaultCountLimit
    )

    // MARK: - Disk cache (rasterized PDF/SVG skin assets)
    // Persistent tier under the in-memory cache so the expensive PDF/SVG rasterization
    // (UIGraphicsImageRenderer at UIScreen scale) doesn't repeat on every cold launch —
    // that re-rasterization is the multi-second skin-load cost. Disk I/O happens outside
    // `imageCache`, which holds only the in-memory tier.

    /// On-disk PNG cache dir. Re-created on access since the OS may purge Library/Caches.
    private static var diskCacheDirectory: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = caches.appendingPathComponent("DeltaSkinImageCache", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Stable (NOT seed-randomized) FNV-1a hash for cache filenames. Swift's `hashValue`
    /// is per-launch seeded and would make the disk cache never hit across launches.
    private static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return String(format: "%016llx", hash)
    }

    /// Bumped when rasterization changes so previously cached blank pages are not reused.
    private static let rasterCacheRevision = "r2"

    /// Content-aware disk-cache filename: skin id + asset + traits + size + screen scale +
    /// the skin file's mod-date (so updating a skin invalidates stale rasters).
    private func diskCacheURL(assetName: String, traits: DeltaSkinTraits, renderSize: CGSize?) -> URL? {
        guard let dir = Self.diskCacheDirectory else { return nil }
        let modStamp = ((try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate)
            .map { String(Int($0.timeIntervalSince1970)) } ?? "0"
        let sizeStamp = renderSize.map { "\(Int($0.width))x\(Int($0.height))" } ?? "native"
        let raw = "\(Self.rasterCacheRevision)|\(identifier)|\(assetName)|\(traits.device.rawValue)|\(traits.displayType.rawValue)|\(traits.orientation.rawValue)|\(sizeStamp)|@\(UIScreen.main.scale)|\(modStamp)"
        return dir.appendingPathComponent(Self.stableHash(raw)).appendingPathExtension("png")
    }

    /// Load a rasterized image at its logical scale; full-size artwork uses the display scale.
    ///
    /// Fully transparent rasters are treated as misses and deleted. Those were written when a PDF
    /// page's media box origin pushed the artwork off the canvas.
    private func loadFromDiskCache(_ url: URL?, scale: CGFloat? = nil) -> UIImage? {
        guard let url, let data = try? Data(contentsOf: url), let image = UIImage(data: data, scale: scale ?? UIScreen.main.scale) else { return nil }
        guard image.hasVisibleContent else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return image
    }

    /// Write a rasterized image to disk as PNG (atomic, best-effort). Triggers a one-shot prune.
    /// Transparent pages are not stored; those were the blank placeholders served on the next launch.
    private static func writeToDiskCache(_ image: UIImage, to url: URL?) {
        guard let url, image.hasVisibleContent, let png = image.pngData() else { return }
        try? png.write(to: url, options: .atomic)
        pruneDiskCacheOnce()
    }

    private static var didPruneDiskCache = false
    private static let diskPruneQueue = DispatchQueue(label: "com.provenance.deltaskin.diskprune", qos: .utility)

    /// Prune the disk cache once per launch (background): drop entries older than 30 days,
    /// then evict oldest until under 100 MB.
    private static func pruneDiskCacheOnce() {
        diskPruneQueue.async {
            guard !didPruneDiskCache else { return }
            didPruneDiskCache = true
            guard let dir = diskCacheDirectory else { return }
            let maxBytes: UInt64 = 100 * 1024 * 1024
            let maxAge: TimeInterval = 30 * 24 * 60 * 60
            let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
            guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys) else { return }
            let now = Date()
            var entries: [(url: URL, date: Date, size: UInt64)] = []
            for u in urls {
                let v = try? u.resourceValues(forKeys: Set(keys))
                let date = v?.contentModificationDate ?? .distantPast
                let size = UInt64(v?.fileSize ?? 0)
                if now.timeIntervalSince(date) > maxAge {
                    try? FileManager.default.removeItem(at: u)
                } else {
                    entries.append((u, date, size))
                }
            }
            var total = entries.reduce(UInt64(0)) { $0 + $1.size }
            if total > maxBytes {
                for e in entries.sorted(by: { $0.date < $1.date }) {
                    if total <= maxBytes { break }
                    try? FileManager.default.removeItem(at: e.url)
                    total = total >= e.size ? total - e.size : 0
                }
            }
        }
    }

    /// Pixel density of list/grid thumbnails (independent of the screen scale, to bound memory).
    private static let thumbnailPixelScale: CGFloat = 2

    /// Renders a small preview of the skin directly at thumbnail size, so no full-size
    /// intermediate raster is created. Vector assets draw natively into the smaller context and
    /// bitmap assets are drawn scaled. Results are stored as PNGs in the skin disk cache, keyed by
    /// skin id + asset + traits + thumbnail size + the skin file's mod-date.
    /// - Parameter maxDimension: Longest side of the result in points (at ``thumbnailPixelScale``).
    public func thumbnail(for traits: DeltaSkinTraits, maxDimension: CGFloat) async throws -> UIImage {
        guard let rep = representation(for: traits) else { throw DeltaSkinError.unsupportedTraits }
        let source = rep.mappingSize.width > 0 && rep.mappingSize.height > 0 ? rep.mappingSize : CGSize(width: 1, height: 1)
        let fit = min(maxDimension / max(source.width, source.height), 1)
        let thumbSize = CGSize(width: max(1, (source.width * fit).rounded()), height: max(1, (source.height * fit).rounded()))
        // Canvas size in points such that pixels = thumbSize * thumbnailPixelScale at the screen scale.
        let canvas = CGSize(
            width: thumbSize.width * Self.thumbnailPixelScale / UIScreen.main.scale,
            height: thumbSize.height * Self.thumbnailPixelScale / UIScreen.main.scale
        )

        let candidates = assetCandidates(for: rep, traits: traits)

        var lastError: Error = DeltaSkinError.unsupportedTraits
        for name in candidates {
            try Task.checkCancellation()
            let diskURL = diskCacheURL(assetName: "thumbnail-\(name)", traits: traits, renderSize: thumbSize)
            if let cached = loadFromDiskCache(diskURL, scale: Self.thumbnailPixelScale) { return cached }
            do {
                let data = try loadAssetData(name)
                let lower = name.lowercased()
                let rendered: UIImage?
                if lower.hasSuffix(".pdf") {
                    rendered = UIImage(pdfData: data, preserveTransparency: true, size: canvas)
                } else if lower.hasSuffix(".svg") {
                    rendered = UIImage(svgData: data, size: canvas)
                } else if let full = UIImage(data: data) {
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = UIScreen.main.scale
                    rendered = UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
                        full.draw(in: CGRect(origin: .zero, size: canvas))
                    }
                } else {
                    rendered = nil
                }
                guard let rendered, rendered.hasVisibleContent, let pixels = rendered.cgImage else {
                    lastError = DeltaSkinError.invalidPNG
                    continue
                }
                // The rasterizers use the display scale, but thumbnail pixels always
                // represent two pixels per logical point, including on 1× TVs and 3× phones.
                let thumbnail = UIImage(cgImage: pixels, scale: Self.thumbnailPixelScale, orientation: rendered.imageOrientation)
                Self.writeToDiskCache(thumbnail, to: diskURL)
                return thumbnail
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Loads the primary skin artwork for the given traits; decoded rasters are memoized in an in-memory LRU cache on this type. Prefer calling from an `async` context so PDF/PNG work can run without blocking synchronous UI callbacks.
    public func image(for traits: DeltaSkinTraits) async throws -> UIImage {
        ILOG("skins: image(for:) called - device: \(traits.device.rawValue), displayType: \(traits.displayType.rawValue), orientation: \(traits.orientation.rawValue)")
        // Get the representation for these traits
        guard let rep = representation(for: traits) else {
            ELOG("skins: ERROR - image(for:) failed: representation returned nil for traits: \(traits.description)")
            throw DeltaSkinError.unsupportedTraits
        }
        ILOG("skins: Got representation, attempting to load image")

        // Check if a theme overrides the asset for this device/displayType/orientation
        let candidates = assetCandidates(for: rep, traits: traits)
        ILOG("skins: Image candidates: \(candidates)")
        var lastError: Error?
        for name in candidates {
            // Check cache first
            let cacheKey = "\(identifier)-\(traits.device.rawValue)-\(traits.displayType.rawValue)-\(traits.orientation.rawValue)-\(name)"
            // Only renders with visible content are stored, so a hit needs no second full-size sample.
            if let cachedImage = Self.imageCache.image(forKey: cacheKey) {
                DLOG("skins: Found cached image: \(name)")
                return cachedImage
            }

            ILOG("skins: Attempting to load image asset: \(name)")
            do {
                let lower = name.lowercased()
                let isVectorAsset = lower.hasSuffix(".pdf") || lower.hasSuffix(".svg")
                let renderSize: CGSize? = rep.mappingSize.width > 0 && rep.mappingSize.height > 0 ? rep.mappingSize : nil
                // Disk-cache tier (PDF/SVG only): a hit skips the slow rasterize entirely.
                let diskURL: URL? = isVectorAsset ? diskCacheURL(assetName: name, traits: traits, renderSize: renderSize) : nil
                if isVectorAsset, let diskImage = loadFromDiskCache(diskURL) {
                    ILOG("skins: Disk-cache hit for \(name)")
                    Self.imageCache.setImage(diskImage, forKey: cacheKey)
                    return diskImage
                }

                let data = try loadAssetData(name)
                let decodedImage: UIImage?
                if lower.hasSuffix(".pdf") {
                    // Always preserve transparency for PDF skin assets — `translucent` controls
                    // runtime overlay opacity, not PDF alpha-channel rendering.
                    decodedImage = UIImage(pdfData: data, preserveTransparency: true, size: renderSize)
                    if decodedImage == nil {
                        lastError = DeltaSkinError.invalidPDF
                        continue
                    }
                } else if lower.hasSuffix(".svg") {
                    decodedImage = UIImage(svgData: data, size: renderSize)
                    if decodedImage == nil {
                        lastError = DeltaSkinError.invalidSVG
                        continue
                    }
                } else {
                    decodedImage = UIImage(data: data, scale: UIScreen.main.scale)
                    if decodedImage == nil {
                        lastError = DeltaSkinError.invalidPNG
                        continue
                    }
                }

                // Cache the decoded image (disk first so future launches skip the rasterize, then memory).
                // A decoded image is still returned when the visibility sample misses, so the picker can show it.
                if let imageToCache = decodedImage {
                    ILOG("skins: Successfully loaded and decoded image: \(name), size: \(imageToCache.size)")
                    if imageToCache.hasVisibleContent {
                        if isVectorAsset { Self.writeToDiskCache(imageToCache, to: diskURL) }
                        Self.imageCache.setImage(imageToCache, forKey: cacheKey)
                    }
                    return imageToCache
                }
            } catch {
                ELOG("skins: Failed to load asset candidate: \(name) — \(error)")
                lastError = error
                continue
            }
        }

        ELOG("skins: ERROR - Failed to load image after trying all candidates. Last error: \(lastError?.localizedDescription ?? "unknown")")

        // Fallback: try the original filename property (legacy behavior)
        let fallbackName = rep.assets.filename
        let fallbackCacheKey = "\(identifier)-\(traits.device.rawValue)-\(traits.displayType.rawValue)-\(traits.orientation.rawValue)-\(fallbackName)"
        if let cachedImage = Self.imageCache.image(forKey: fallbackCacheKey) {
            return cachedImage
        }

        do {
            let lower = fallbackName.lowercased()
            let fbIsVector = lower.hasSuffix(".pdf") || lower.hasSuffix(".svg")
            let renderSize: CGSize? = rep.mappingSize.width > 0 && rep.mappingSize.height > 0 ? rep.mappingSize : nil
            // Disk-cache tier (PDF/SVG only): a hit skips the slow rasterize.
            let fbDiskURL: URL? = fbIsVector ? diskCacheURL(assetName: fallbackName, traits: traits, renderSize: renderSize) : nil
            if fbIsVector, let diskImage = loadFromDiskCache(fbDiskURL) {
                Self.imageCache.setImage(diskImage, forKey: fallbackCacheKey)
                return diskImage
            }

            let assetData = try loadAssetData(fallbackName)
            let decodedImage: UIImage?
            if lower.hasSuffix(".pdf") {
                // Always preserve transparency for PDF skin assets — `translucent` controls
                // runtime overlay opacity, not PDF alpha-channel rendering.
                decodedImage = UIImage(pdfData: assetData, preserveTransparency: true, size: renderSize)
                guard decodedImage != nil else {
                    throw DeltaSkinError.invalidPDF
                }
            } else if lower.hasSuffix(".svg") {
                decodedImage = UIImage(svgData: assetData, size: renderSize)
                guard decodedImage != nil else {
                    throw DeltaSkinError.invalidSVG
                }
            } else {
                decodedImage = UIImage(data: assetData, scale: UIScreen.main.scale)
                guard decodedImage != nil else {
                    throw DeltaSkinError.invalidPNG
                }
            }

            // Cache the decoded image (disk + memory). Return it even when the sample finds no pixels.
            if let imageToCache = decodedImage {
                if imageToCache.hasVisibleContent {
                    if fbIsVector { Self.writeToDiskCache(imageToCache, to: fbDiskURL) }
                    Self.imageCache.setImage(imageToCache, forKey: fallbackCacheKey)
                }
                return imageToCache
            }

            throw lastError ?? DeltaSkinError.invalidPNG
        } catch {
            // Final fallback: if current skin failed, try the default skin for this system
            if let fallbackSkin = await DeltaSkinRendering.defaultSkin(for: gameType),
               fallbackSkin.identifier != identifier,
               fallbackSkin.supports(traits) {
                WLOG("skins: Primary skin \(identifier) failed to load asset \(fallbackName); falling back to default skin \(fallbackSkin.identifier)")
                return try await fallbackSkin.image(for: traits)
            }
            throw lastError ?? error
        }
    }

    /// Cache for thumbstick images keyed by skin identifier + filename
    private static var thumbstickImageCache: [String: UIImage] = [:]
    private static let thumbstickCacheQueue = DispatchQueue(label: "com.provenance.deltaskin.thumbstickcache", attributes: .concurrent)

    /// Load the thumbstick image
    public func loadThumbstickImage(named: String) async throws -> UIImage {
        // Check cache first
        let cacheKey = "\(identifier)-thumbstick-\(named)"
        if let cachedImage = Self.thumbstickCacheQueue.sync(execute: { Self.thumbstickImageCache[cacheKey] }) {
            return cachedImage
        }

        // Disk-cache tier (PDF thumbsticks only; PNGs go through imageWithAlpha() and are cheap).
        let tsDiskURL: URL? = {
            guard named.hasSuffix(".pdf"), let dir = Self.diskCacheDirectory else { return nil }
            let modStamp = ((try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate)
                .map { String(Int($0.timeIntervalSince1970)) } ?? "0"
            let raw = "\(identifier)|thumbstick|\(named)|@\(UIScreen.main.scale)|\(modStamp)"
            return dir.appendingPathComponent(Self.stableHash(raw)).appendingPathExtension("png")
        }()
        if let diskImage = loadFromDiskCache(tsDiskURL) {
            Self.thumbstickCacheQueue.async(flags: .barrier) { Self.thumbstickImageCache[cacheKey] = diskImage }
            return diskImage
        }

        // Load the asset data
        let assetData = try loadAssetData(named)

        // Create image from PDF data since thumbsticks are PDFs
        let decodedImage: UIImage?
        if named.hasSuffix(".pdf") {
            decodedImage = UIImage(pdfData: assetData, preserveTransparency: true)
            guard decodedImage != nil else {
                throw DeltaSkinError.invalidPDF
            }
        } else {
            // For PNG thumbsticks, ensure we preserve alpha channel
            decodedImage = UIImage(data: assetData)?.imageWithAlpha()
            guard decodedImage != nil else {
                throw DeltaSkinError.invalidPNG
            }
        }

        // Cache the decoded image (disk + memory)
        if let imageToCache = decodedImage {
            if named.hasSuffix(".pdf") { Self.writeToDiskCache(imageToCache, to: tsDiskURL) }
            Self.thumbstickCacheQueue.async(flags: .barrier) {
                Self.thumbstickImageCache[cacheKey] = imageToCache
                // Limit cache size to ~20MB (approximately 40 thumbstick images)
                if Self.thumbstickImageCache.count > 40 {
                    let keysToRemove = Array(Self.thumbstickImageCache.keys.prefix(10))
                    keysToRemove.forEach { Self.thumbstickImageCache.removeValue(forKey: $0) }
                }
            }
            return imageToCache
        }

        throw DeltaSkinError.invalidPNG
    }


}
#endif
