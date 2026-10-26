import Foundation
import Testing
@testable import SkinKitCore

@Suite("SkinKitCoreLog", .serialized)
struct SkinKitCoreLogTests {
    private final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var _lines: [(SkinKitCoreLogLevel, String)] = []

        var lines: [(SkinKitCoreLogLevel, String)] { lock.withLock { _lines } }

        func append(_ level: SkinKitCoreLogLevel, _ message: String) {
            lock.withLock { _lines.append((level, message)) }
        }
    }

    @Test("The injected logger receives the module's log lines, at the right levels")
    func hookReceivesLines() {
        let sink = Sink()
        let previous = SkinKitCoreLog.logger
        SkinKitCoreLog.logger = { sink.append($0, $1) }
        defer { SkinKitCoreLog.logger = previous }

        ILOG("core-info-line")
        WLOG("core-warning-line")
        ELOG("core-error-line")

        let lines = sink.lines
        #expect(lines.contains { $0.0 == .info && $0.1 == "core-info-line" })
        #expect(lines.contains { $0.0 == .warning && $0.1 == "core-warning-line" })
        #expect(lines.contains { $0.0 == .error && $0.1 == "core-error-line" })
    }

    @Test("Debug lines reach the hook in debug builds and are compiled out of release")
    func debugLines() {
        let sink = Sink()
        let previous = SkinKitCoreLog.logger
        SkinKitCoreLog.logger = { sink.append($0, $1) }
        defer { SkinKitCoreLog.logger = previous }

        DLOG("core-debug-line")
        VLOG("core-verbose-line")

        #if DEBUG
        #expect(sink.lines.filter { $0.0 == .debug && $0.1.hasPrefix("core-") }.count == 2)
        #else
        #expect(sink.lines.isEmpty)
        #endif
    }

    @Test("The default logger is os.Logger, and silent drops everything")
    func defaults() {
        SkinKitCoreLog.osLog(.info, "core default logger smoke test")
        SkinKitCoreLog.silent(.error, "dropped")
    }
}
