import Foundation

/// Fetches and caches the emuskins.com skin catalog.
///
/// Moved from iFly's `SkinCatalogService` (itself a port of Provenance's, with two behavioural fixes):
///
/// - **The TTL actually holds across launches.** Provenance stamped
///   `lastFetchDate = Date()` when it loaded the disk cache and then hit the
///   network anyway, so every cold launch refetched the ~1 MB feed. Here
///   freshness comes from the cache file's modification date.
/// - **The cache is the server's bytes, verbatim.** Nothing is re-encoded, so
///   the cached file decodes through exactly the same lossy path as a live one.
///
/// Failure order: network → in-memory copy (any age) → disk copy (any age) →
/// throw. An offline user with any previous fetch always gets a catalog.
public actor SkinCatalogService {
    public static let shared = SkinCatalogService()

    /// Primary first. The GitHub raw URL serves the same file from the
    /// repository the site is built from.
    public static let defaultCatalogURLs: [URL] = [
        URL(string: "https://emuskins.com/catalog.json"),
        URL(string: "https://raw.githubusercontent.com/Provenance-Emu/skins/main/catalog.json"),
    ].compactMap(\.self)

    public static let defaultTTL: TimeInterval = 24 * 60 * 60
    public static let cacheFileName = "skin_store_catalog.json"

    public typealias Fetch = @Sendable (URL) async throws -> (Data, URLResponse)

    private let catalogURLs: [URL]
    private let cacheURL: URL
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date
    private let fetch: Fetch
    private let log: SkinCatalogLogger

    private var memoryCatalog: SkinCatalog?
    /// When `memoryCatalog`'s bytes were fetched (the cache file's mtime when it
    /// came from disk), so a disk load never looks fresher than it is.
    private var memoryFetchedAt: Date?

    /// - Parameters:
    ///   - catalogURLs: tried in order; the first that answers 2xx with decodable bytes wins.
    ///   - cacheURL: where the server's bytes are cached (the file's mtime is the freshness clock).
    ///   - session: used by the default `fetch`. Tests pass one whose configuration has a mock
    ///     `URLProtocol`.
    ///   - fetch: replaces the whole transport (and ignores `session`) when set.
    ///   - log: receives one line per fetch attempt and per fallback. When `nil`, lines go to
    ///     ``SkinCatalogLog/logger`` (looked up when each line is logged).
    public init(
        catalogURLs: [URL] = SkinCatalogService.defaultCatalogURLs,
        cacheURL: URL = SkinCatalogService.defaultCacheURL,
        ttl: TimeInterval = SkinCatalogService.defaultTTL,
        now: @escaping @Sendable () -> Date = { Date() },
        session: URLSession = .shared,
        log: SkinCatalogLogger? = nil,
        fetch: Fetch? = nil
    ) {
        self.catalogURLs = catalogURLs
        self.cacheURL = cacheURL
        self.ttl = ttl
        self.now = now
        self.log = log ?? { SkinCatalogLog.log($0, $1) }
        self.fetch = fetch ?? { url in
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 30
            return try await session.data(for: request)
        }
    }

    public static var defaultCacheURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent(cacheFileName)
    }

    // MARK: - Public API

    /// The catalog, from cache when fresh (younger than the TTL), otherwise
    /// from the network with a cache fallback.
    ///
    /// - Parameter forceRefresh: skip the freshness check and go to the
    ///   network. A failed forced refresh still falls back to the cache.
    public func catalog(forceRefresh: Bool = false) async throws -> SkinCatalog {
        try await load(forceRefresh: forceRefresh).catalog
    }

    /// `catalog(forceRefresh:)`, plus whether the network failed and a cached
    /// copy was used instead — the store says so rather than passing an old
    /// catalog off as current.
    public func load(forceRefresh: Bool = false) async throws -> SkinCatalogLoad {
        if !forceRefresh, let fresh = freshCachedCatalog() {
            return SkinCatalogLoad(catalog: fresh, networkError: nil)
        }

        let networkError: Error
        do {
            return try await SkinCatalogLoad(catalog: fetchFromNetwork(), networkError: nil)
        } catch {
            networkError = error
        }

        if let memoryCatalog {
            log(.warning,
                "Skin catalog fetch failed (\(networkError.localizedDescription)); "
                    + "using in-memory copy (\(memoryCatalog.skins.count) skins)")
            return SkinCatalogLoad(catalog: memoryCatalog, error: networkError)
        }
        if let disk = loadDiskCache() {
            log(.warning,
                "Skin catalog fetch failed (\(networkError.localizedDescription)); "
                    + "using disk cache (\(disk.catalog.skins.count) skins, "
                    + "\(Int(now().timeIntervalSince(disk.modified)))s old)")
            memoryCatalog = disk.catalog
            memoryFetchedAt = disk.modified
            return SkinCatalogLoad(catalog: disk.catalog, error: networkError)
        }
        throw networkError
    }

    /// Whatever is cached, at any age, without touching the network. Lets a
    /// store screen paint immediately while `catalog()` refreshes.
    public func cachedCatalog() -> SkinCatalog? {
        if let memoryCatalog {
            return memoryCatalog
        }
        guard let disk = loadDiskCache() else { return nil }
        memoryCatalog = disk.catalog
        memoryFetchedAt = disk.modified
        return disk.catalog
    }

    /// Drop both caches. The next `catalog()` goes to the network.
    public func invalidateCache() {
        memoryCatalog = nil
        memoryFetchedAt = nil
        try? FileManager.default.removeItem(at: cacheURL)
    }

    /// `SkinCatalog.decode(_:)`, kept so iFly's call sites compile unchanged.
    public static func decode(_ data: Data) throws -> SkinCatalog {
        try SkinCatalog.decode(data)
    }

    // MARK: - Private

    private func freshCachedCatalog() -> SkinCatalog? {
        if let memoryCatalog, let memoryFetchedAt, now().timeIntervalSince(memoryFetchedAt) < ttl {
            return memoryCatalog
        }
        guard let disk = loadDiskCache(), now().timeIntervalSince(disk.modified) < ttl else {
            return nil
        }
        memoryCatalog = disk.catalog
        memoryFetchedAt = disk.modified
        return disk.catalog
    }

    private func fetchFromNetwork() async throws -> SkinCatalog {
        var lastError: Error = SkinCatalogError.network("no catalog URL configured")
        for url in catalogURLs {
            do {
                let (data, response) = try await fetch(url)
                if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
                    throw SkinCatalogError.httpStatus(http.statusCode)
                }
                let catalog = try SkinCatalog.decode(data)
                storeDiskCache(data)
                memoryCatalog = catalog
                memoryFetchedAt = now()
                log(.info,
                    "Fetched skin catalog from \(url.host ?? url.absoluteString): \(catalog.skins.count) skins"
                        + (catalog.droppedEntryCount > 0 ? ", \(catalog.droppedEntryCount) undecodable" : ""))
                return catalog
            } catch {
                log(.warning,
                    "Skin catalog fetch from \(url.absoluteString) failed: \(error.localizedDescription)")
                lastError = error
            }
        }
        if lastError is SkinCatalogError {
            throw lastError
        }
        throw SkinCatalogError.network(lastError.localizedDescription)
    }

    private func loadDiskCache() -> (catalog: SkinCatalog, modified: Date)? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: cacheURL.path)
        let modified = (attributes?[.modificationDate] as? Date) ?? .distantPast
        do {
            return try (SkinCatalog.decode(data), modified)
        } catch {
            log(.warning, "Discarding unreadable skin catalog cache: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: cacheURL)
            return nil
        }
    }

    private func storeDiskCache(_ data: Data) {
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: cacheURL, options: .atomic)
            // `.atomic` writes a new file, so its mtime is "now" by the file
            // system's clock. Stamp it from the injected clock so the TTL check
            // and the write agree (and tests can drive time).
            try FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: cacheURL.path)
        } catch {
            log(.warning, "Could not write skin catalog cache: \(error.localizedDescription)")
        }
    }
}
