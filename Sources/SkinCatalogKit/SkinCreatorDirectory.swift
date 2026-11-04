import Foundation

/// Fetches and caches the emuskins.com creator directory (`creators.json`), and answers the
/// "who made this skin" questions the store UI asks (creator profiles spec §7).
///
/// Follows ``SkinCatalogService``'s rules, so the two behave alike offline:
///
/// - Freshness comes from the cache file's modification date, so the TTL holds across launches.
/// - The cache is the server's bytes, verbatim.
/// - Failure order: network (emuskins.com, then raw GitHub) → in-memory copy → disk copy → throw.
///
/// The convenience lookups never throw. With no directory at all they resolve against
/// ``SkinCreatorIndex/empty``, which still gives every authored entry a minimal profile from the
/// local slug, so the profile sheet works against any catalog.
public actor SkinCreatorDirectory {
    public static let shared = SkinCreatorDirectory()

    /// Primary first. The GitHub raw URL serves the same file from the repository the site is built
    /// from (the build writes `docs/creators.json`).
    public static let defaultDirectoryURLs: [URL] = [
        URL(string: "https://emuskins.com/creators.json"),
        URL(string: "https://raw.githubusercontent.com/Provenance-Emu/skins/main/docs/creators.json"),
    ].compactMap(\.self)

    public static let defaultTTL: TimeInterval = SkinCatalogService.defaultTTL
    public static let cacheFileName = "skin_store_creators.json"

    private let directoryURLs: [URL]
    private let cacheURL: URL
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date
    private let fetch: SkinCatalogService.Fetch
    private let log: SkinCatalogLogger

    private var memoryIndex: SkinCreatorIndex?
    private var memoryFetchedAt: Date?

    /// - Parameters:
    ///   - directoryURLs: tried in order; the first that answers 2xx with decodable bytes wins.
    ///   - cacheURL: where the server's bytes are cached (the file's mtime is the freshness clock).
    ///   - session: used by the default `fetch`.
    ///   - fetch: replaces the whole transport (and ignores `session`) when set.
    ///   - log: one line per fetch attempt and per fallback; defaults to ``SkinCatalogLog/logger``.
    public init(
        directoryURLs: [URL] = SkinCreatorDirectory.defaultDirectoryURLs,
        cacheURL: URL = SkinCreatorDirectory.defaultCacheURL,
        ttl: TimeInterval = SkinCreatorDirectory.defaultTTL,
        now: @escaping @Sendable () -> Date = { Date() },
        session: URLSession = .shared,
        log: SkinCatalogLogger? = nil,
        fetch: SkinCatalogService.Fetch? = nil
    ) {
        self.directoryURLs = directoryURLs
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

    // MARK: - Directory

    /// The directory, from cache when fresh, otherwise from the network with a cache fallback.
    /// Pass `forceRefresh: true` when the catalog was force-refreshed, so the two stay in step.
    public func index(forceRefresh: Bool = false) async throws -> SkinCreatorIndex {
        if !forceRefresh, let fresh = freshCachedIndex() {
            return fresh
        }

        let networkError: Error
        do {
            return try await fetchFromNetwork()
        } catch {
            networkError = error
        }

        if let memoryIndex {
            log(.warning,
                "Creator directory fetch failed (\(networkError.localizedDescription)); "
                    + "using in-memory copy (\(memoryIndex.creators.count) creators)")
            return memoryIndex
        }
        if let disk = loadDiskCache() {
            log(.warning,
                "Creator directory fetch failed (\(networkError.localizedDescription)); "
                    + "using disk cache (\(disk.index.creators.count) creators)")
            memoryIndex = disk.index
            memoryFetchedAt = disk.modified
            return disk.index
        }
        throw networkError
    }

    /// Whatever is cached, at any age, without touching the network.
    public func cachedIndex() -> SkinCreatorIndex? {
        if let memoryIndex {
            return memoryIndex
        }
        guard let disk = loadDiskCache() else { return nil }
        memoryIndex = disk.index
        memoryFetchedAt = disk.modified
        return disk.index
    }

    /// Drop both caches. The next `index()` goes to the network.
    public func invalidateCache() {
        memoryIndex = nil
        memoryFetchedAt = nil
        try? FileManager.default.removeItem(at: cacheURL)
    }

    // MARK: - Lookups

    /// The directory's record for `slug`, or nil when there is none (or no directory).
    public func creator(for slug: String) async -> SkinCreator? {
        await resolvedIndex().creator(for: slug)
    }

    /// The creator an entry belongs to; see `SkinCreatorIndex.creator(for:)`. Resolves
    /// even with no network and no cache, as a minimal profile.
    public func creator(for entry: SkinCatalogEntry) async -> SkinCreator? {
        await resolvedIndex().creator(for: entry)
    }

    /// The entries of `catalog` that belong to `creator`, in catalog order.
    public func skins(by creator: SkinCreator, in catalog: SkinCatalog) async -> [SkinCatalogEntry] {
        await resolvedIndex().skins(by: creator, in: catalog)
    }

    private func resolvedIndex() async -> SkinCreatorIndex {
        if let index = try? await index() {
            return index
        }
        return cachedIndex() ?? .empty
    }

    // MARK: - Private

    private func freshCachedIndex() -> SkinCreatorIndex? {
        if let memoryIndex, let memoryFetchedAt, now().timeIntervalSince(memoryFetchedAt) < ttl {
            return memoryIndex
        }
        guard let disk = loadDiskCache(), now().timeIntervalSince(disk.modified) < ttl else {
            return nil
        }
        memoryIndex = disk.index
        memoryFetchedAt = disk.modified
        return disk.index
    }

    private func fetchFromNetwork() async throws -> SkinCreatorIndex {
        var lastError: Error = SkinCatalogError.network("no creator directory URL configured")
        for url in directoryURLs {
            do {
                let (data, response) = try await fetch(url)
                if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
                    throw SkinCatalogError.httpStatus(http.statusCode)
                }
                let index = try SkinCreatorIndex.decode(data)
                storeDiskCache(data)
                memoryIndex = index
                memoryFetchedAt = now()
                log(.info,
                    "Fetched creator directory from \(url.host ?? url.absoluteString): \(index.creators.count) creators"
                        + (index.droppedCreatorCount > 0 ? ", \(index.droppedCreatorCount) undecodable" : ""))
                return index
            } catch {
                log(.warning,
                    "Creator directory fetch from \(url.absoluteString) failed: \(error.localizedDescription)")
                lastError = error
            }
        }
        if lastError is SkinCatalogError {
            throw lastError
        }
        throw SkinCatalogError.network(lastError.localizedDescription)
    }

    private func loadDiskCache() -> (index: SkinCreatorIndex, modified: Date)? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: cacheURL.path)
        let modified = (attributes?[.modificationDate] as? Date) ?? .distantPast
        do {
            return try (SkinCreatorIndex.decode(data), modified)
        } catch {
            log(.warning, "Discarding unreadable creator directory cache: \(error.localizedDescription)")
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
            try FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: cacheURL.path)
        } catch {
            log(.warning, "Could not write creator directory cache: \(error.localizedDescription)")
        }
    }
}
