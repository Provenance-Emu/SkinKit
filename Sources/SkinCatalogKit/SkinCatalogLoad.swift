import Foundation

/// What `SkinCatalogService.load(forceRefresh:)` produced: the catalog, and
/// whether it is a cached copy standing in for a failed download.
public struct SkinCatalogLoad: Sendable {
    public var catalog: SkinCatalog
    /// Set when the network fetch failed and a cached catalog was returned
    /// instead. Nil for a fresh download or a cache still inside its TTL.
    public var networkError: String?

    public init(catalog: SkinCatalog, networkError: String? = nil) {
        self.catalog = catalog
        self.networkError = networkError
    }

    /// True when this is a cached copy because the download failed.
    public var isFallback: Bool {
        networkError != nil
    }
}
