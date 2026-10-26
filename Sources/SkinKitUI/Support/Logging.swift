import Foundation
import os

/// Severity of a message from SkinKitUI.
public enum SkinKitUILogLevel: Sendable {
    case debug
    case info
    case warning
    case error
}

/// Where SkinKitUI reports what it did. Provenance sent these to `PVLogging`
/// (`DLOG`/`ILOG`/`WLOG`/`ELOG`), iFly to its `logInfo`/`logWarning` and iCube to `NSLog`; each app
/// sets its own with `SkinKitUILog.logger`. The default writes to `os.Logger`.
public typealias SkinKitUILogger = @Sendable (SkinKitUILogLevel, String) -> Void

public enum SkinKitUILog {
    private static let osLogger = Logger(subsystem: "com.provenance-emu.SkinKit", category: "SkinKitUI")
    private static let lock = NSLock()
    private static var _logger: SkinKitUILogger = SkinKitUILog.osLog

    /// The default: `os.Logger`, subsystem `com.provenance-emu.SkinKit`.
    public static let osLog: SkinKitUILogger = { level, message in
        switch level {
        case .debug: osLogger.debug("\(message, privacy: .public)")
        case .info: osLogger.info("\(message, privacy: .public)")
        case .warning: osLogger.warning("\(message, privacy: .public)")
        case .error: osLogger.error("\(message, privacy: .public)")
        }
    }

    /// Drops everything.
    public static let silent: SkinKitUILogger = { _, _ in }

    /// Set once at launch. Applies to every type in this module.
    public static var logger: SkinKitUILogger {
        get { lock.withLock { _logger } }
        set { lock.withLock { _logger = newValue } }
    }

    static func log(_ level: SkinKitUILogLevel, _ message: String) {
        logger(level, message)
    }
}

// The names Provenance's skin code logs through, kept (module-internal) so the moved code is
// unchanged. Verbose and debug messages compile out of release builds, so their strings are never built.

@inline(__always)
func VLOG(_ message: @autoclosure () -> String) {
    #if DEBUG
    SkinKitUILog.log(.debug, message())
    #endif
}

@inline(__always)
func DLOG(_ message: @autoclosure () -> String) {
    #if DEBUG
    SkinKitUILog.log(.debug, message())
    #endif
}

func ILOG(_ message: @autoclosure () -> String) {
    SkinKitUILog.log(.info, message())
}

func WLOG(_ message: @autoclosure () -> String) {
    SkinKitUILog.log(.warning, message())
}

func ELOG(_ message: @autoclosure () -> String) {
    SkinKitUILog.log(.error, message())
}
