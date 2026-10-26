import Foundation

/// What `SkinCatalogService.load(forceRefresh:)` produced: the catalog, and
/// whether it is a cached copy standing in for a failed download.
public struct SkinCatalogLoad: Sendable {
    public var catalog: SkinCatalog
    /// Set when the network fetch failed and a cached catalog was returned
    /// instead. Nil for a fresh download or a cache still inside its TTL.
    ///
    /// This is the error's `localizedDescription` (English for `SkinCatalogError`). An app
    /// that localizes reads ``error`` instead.
    public var networkError: String?
    /// The failure behind ``networkError`` (a ``SkinCatalogError`` or a transport error), so an app can
    /// localize it with `SkinCatalogError.message(localizing:)`. Nil whenever `networkError` is nil, and
    /// for a load built from text alone.
    public var error: (any Error)?

    public init(catalog: SkinCatalog, networkError: String? = nil) {
        self.catalog = catalog
        self.networkError = networkError
    }

    /// A cached copy standing in for a download that failed with `error`.
    public init(catalog: SkinCatalog, error: any Error) {
        self.catalog = catalog
        self.networkError = error.localizedDescription
        self.error = error
    }

    /// True when this is a cached copy because the download failed.
    public var isFallback: Bool {
        networkError != nil
    }
}
