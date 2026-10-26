import Foundation
import os

/// Severity of a message from SkinKitCore.
public enum SkinKitCoreLogLevel: Sendable {
    case debug
    case info
    case warning
    case error
}

/// Where SkinKitCore reports what it did. Provenance sent these to `PVLogging`
/// (`DLOG`/`ILOG`/`WLOG`/`ELOG`), iFly to its `logInfo`/`logWarning` and iCube to `NSLog`; each app
/// sets its own with `SkinKitCoreLog.logger`. The default writes to `os.Logger`.
public typealias SkinKitCoreLogger = @Sendable (SkinKitCoreLogLevel, String) -> Void

public enum SkinKitCoreLog {
    private static let osLogger = Logger(subsystem: "com.provenance-emu.SkinKit", category: "SkinKitCore")
    private static let lock = NSLock()
    private static var _logger: SkinKitCoreLogger = SkinKitCoreLog.osLog

    /// The default: `os.Logger`, subsystem `com.provenance-emu.SkinKit`.
    public static let osLog: SkinKitCoreLogger = { level, message in
        switch level {
        case .debug: osLogger.debug("\(message, privacy: .public)")
        case .info: osLogger.info("\(message, privacy: .public)")
        case .warning: osLogger.warning("\(message, privacy: .public)")
        case .error: osLogger.error("\(message, privacy: .public)")
        }
    }

    /// Drops everything.
    public static let silent: SkinKitCoreLogger = { _, _ in }

    /// Set once at launch. Applies to every type in this module.
    public static var logger: SkinKitCoreLogger {
        get { lock.withLock { _logger } }
        set { lock.withLock { _logger = newValue } }
    }

    static func log(_ level: SkinKitCoreLogLevel, _ message: String) {
        logger(level, message)
    }
}

// The names Provenance's skin code logs through, kept (module-internal) so the moved code is
// unchanged. Verbose and debug messages compile out of release builds, so their strings are never built.

@inline(__always)
func VLOG(_ message: @autoclosure () -> String) {
    #if DEBUG
    SkinKitCoreLog.log(.debug, message())
    #endif
}

@inline(__always)
func DLOG(_ message: @autoclosure () -> String) {
    #if DEBUG
    SkinKitCoreLog.log(.debug, message())
    #endif
}

func ILOG(_ message: @autoclosure () -> String) {
    SkinKitCoreLog.log(.info, message())
}

func WLOG(_ message: @autoclosure () -> String) {
    SkinKitCoreLog.log(.warning, message())
}

func ELOG(_ message: @autoclosure () -> String) {
    SkinKitCoreLog.log(.error, message())
}
