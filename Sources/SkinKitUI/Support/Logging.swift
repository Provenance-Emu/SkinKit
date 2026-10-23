import os

/// Minimal logging shim for SkinKitUI.
///
/// Provenance's skin code logged through `PVLogging` (`VLOG`/`DLOG`/`ILOG`/`WLOG`/`ELOG`). Those
/// names are kept here, internal to this module, so the moved code is unchanged. They write to
/// `os.Logger` under the subsystem below. Verbose and debug messages are compiled out of release
/// builds, so their message strings are never built.
enum SkinKitLog {
    static let logger = Logger(subsystem: "com.provenance-emu.SkinKit", category: "SkinKitUI")
}

@inline(__always)
func VLOG(_ message: @autoclosure () -> String) {
    #if DEBUG
    let text = message()
    SkinKitLog.logger.debug("\(text, privacy: .public)")
    #endif
}

@inline(__always)
func DLOG(_ message: @autoclosure () -> String) {
    #if DEBUG
    let text = message()
    SkinKitLog.logger.debug("\(text, privacy: .public)")
    #endif
}

func ILOG(_ message: @autoclosure () -> String) {
    let text = message()
    SkinKitLog.logger.info("\(text, privacy: .public)")
}

func WLOG(_ message: @autoclosure () -> String) {
    let text = message()
    SkinKitLog.logger.warning("\(text, privacy: .public)")
}

func ELOG(_ message: @autoclosure () -> String) {
    let text = message()
    SkinKitLog.logger.error("\(text, privacy: .public)")
}
