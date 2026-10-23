import Foundation
import os

/// Severity of a message from SkinKitManager.
public enum SkinManagerLogLevel: Sendable {
    case debug
    case info
    case warning
    case error
}

/// Where SkinKitManager reports what it did. Provenance sent these to `PVLogging`
/// (`DLOG`/`ILOG`/`WLOG`/`ELOG`), iFly to its `logInfo`/`logWarning` and iCube to `NSLog`; each app
/// sets its own with `SkinManagerLog.logger`. The default writes to `os.Logger`.
public typealias SkinManagerLogger = @Sendable (SkinManagerLogLevel, String) -> Void

public enum SkinManagerLog {
    private static let osLogger = Logger(subsystem: "com.provenance-emu.SkinKit", category: "SkinKitManager")
    private static let lock = NSLock()
    private static var _logger: SkinManagerLogger = SkinManagerLog.osLog

    /// The default: `os.Logger`, subsystem `com.provenance-emu.SkinKit`.
    public static let osLog: SkinManagerLogger = { level, message in
        switch level {
        case .debug: osLogger.debug("\(message, privacy: .public)")
        case .info: osLogger.info("\(message, privacy: .public)")
        case .warning: osLogger.warning("\(message, privacy: .public)")
        case .error: osLogger.error("\(message, privacy: .public)")
        }
    }

    /// Drops everything.
    public static let silent: SkinManagerLogger = { _, _ in }

    /// Set once at launch. Applies to every type in this module.
    public static var logger: SkinManagerLogger {
        get { lock.withLock { _logger } }
        set { lock.withLock { _logger = newValue } }
    }

    static func log(_ level: SkinManagerLogLevel, _ message: String) {
        logger(level, message)
    }
}

// The names Provenance's skin code logs through, kept (module-internal) so the moved code is
// unchanged. Debug messages compile out of release builds, so their strings are never built.

@inline(__always)
func DLOG(_ message: @autoclosure () -> String) {
    #if DEBUG
    SkinManagerLog.log(.debug, message())
    #endif
}

func ILOG(_ message: @autoclosure () -> String) {
    SkinManagerLog.log(.info, message())
}

func WLOG(_ message: @autoclosure () -> String) {
    SkinManagerLog.log(.warning, message())
}

func ELOG(_ message: @autoclosure () -> String) {
    SkinManagerLog.log(.error, message())
}
