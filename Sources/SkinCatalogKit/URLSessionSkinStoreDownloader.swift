import Foundation

/// Downloads a skin with `URLSessionDownloadTask`, reporting progress.
///
/// Delegate-based rather than `URLSession.download(from:delegate:)`: the async
/// variant does not deliver `didWriteData`, so it has no progress.
public struct URLSessionSkinStoreDownloader: SkinStoreDownloading {
    /// A non-2xx answer. deltastyles.com serves an HTML page for a dead link,
    /// which would otherwise reach the importer as a "corrupt archive".
    public struct HTTPStatusError: LocalizedError {
        public var statusCode: Int

        public init(statusCode: Int) {
            self.statusCode = statusCode
        }

        public var errorDescription: String? {
            message(localizing: { $0 })
        }

        /// The description with the format string run through `localize` first (the English
        /// string is the key, as iCube's `L()` already uses).
        public func message(localizing localize: (String) -> String) -> String {
            String(format: localize("The skin's host answered with HTTP %d."), statusCode)
        }
    }

    public var timeout: TimeInterval
    /// Builds the session configuration for each download. Tests return one whose
    /// `protocolClasses` holds a mock `URLProtocol`.
    public var makeConfiguration: @Sendable () -> URLSessionConfiguration

    public init(
        timeout: TimeInterval = 60,
        makeConfiguration: @escaping @Sendable () -> URLSessionConfiguration = { .ephemeral }
    ) {
        self.timeout = timeout
        self.makeConfiguration = makeConfiguration
    }

    public func download(
        from url: URL,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let delegate = SkinStoreDownloadDelegate(destination: destination, progress: progress)
        let configuration = makeConfiguration()
        configuration.timeoutIntervalForRequest = timeout
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        // The session retains its delegate until invalidated; invalidate once
        // the continuation has resumed so neither leaks.
        defer { session.finishTasksAndInvalidate() }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                delegate.start(session.downloadTask(with: url), continuation: continuation)
            }
        } onCancel: {
            delegate.cancel()
        }
    }
}
