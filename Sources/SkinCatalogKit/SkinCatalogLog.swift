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
    private static let osLogger = Logger(subsystem: "com.provenance-emu.SkinKit", category: "SkinCatalog")
    private static let lock = NSLock()
    private static var _logger: SkinCatalogLogger = SkinCatalogLog.osLog

    /// The default: `os.Logger`, subsystem `com.provenance-emu.SkinKit`.
    public static let osLog: SkinCatalogLogger = { level, message in
        switch level {
        case .info: osLogger.info("\(message, privacy: .public)")
        case .warning: osLogger.warning("\(message, privacy: .public)")
        }
    }

    /// Drops everything.
    public static let silent: SkinCatalogLogger = { _, _ in }

    /// Set once at launch. Used by every ``SkinCatalogService`` that wasn't given its own `log:`,
    /// including ``SkinCatalogService/shared``.
    public static var logger: SkinCatalogLogger {
        get { lock.withLock { _logger } }
        set { lock.withLock { _logger = newValue } }
    }

    static func log(_ level: SkinCatalogLogLevel, _ message: String) {
        logger(level, message)
    }
}
