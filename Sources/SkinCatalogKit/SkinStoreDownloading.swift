import Foundation

/// Fetches a skin file to a local path. Abstracted so an installer's state
/// machine can be tested without the network.
public protocol SkinStoreDownloading: Sendable {
    /// Download `url` to `destination` (overwriting it), reporting progress in
    /// 0...1. Throws on transport failure, a non-2xx status, or cancellation.
    func download(
        from url: URL,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws
}
