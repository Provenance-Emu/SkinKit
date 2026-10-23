import Foundation
import os

public enum SkinCatalogLogLevel: Sendable {
    case info
    case warning
}

/// Where the catalog service reports what it did. iFly sent these to its logger and iCube to
/// `NSLog`; each app injects its own, and the default writes to `os.Logger`.
public typealias SkinCatalogLogger = @Sendable (SkinCatalogLogLevel, String) -> Void

public enum SkinCatalogLog {
    private static let logger = Logger(subsystem: "com.provenance-emu.SkinKit", category: "SkinCatalog")

    /// The default: `os.Logger`, subsystem `com.provenance-emu.SkinKit`.
    public static let osLog: SkinCatalogLogger = { level, message in
        switch level {
        case .info: logger.info("\(message, privacy: .public)")
        case .warning: logger.warning("\(message, privacy: .public)")
        }
    }

    /// Drops everything.
    public static let silent: SkinCatalogLogger = { _, _ in }
}
