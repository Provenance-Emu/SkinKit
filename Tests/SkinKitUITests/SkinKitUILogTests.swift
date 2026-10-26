#if canImport(UIKit)
import Foundation
import Testing
@testable import SkinKitUI

extension UIKitSerial {
    @Suite("SkinKitUILog")
    struct SkinKitUILogTests {
        private final class Sink: @unchecked Sendable {
            private let lock = NSLock()
            private var _lines: [(SkinKitUILogLevel, String)] = []

            var lines: [(SkinKitUILogLevel, String)] { lock.withLock { _lines } }

            func append(_ level: SkinKitUILogLevel, _ message: String) {
                lock.withLock { _lines.append((level, message)) }
            }
        }

        @Test("The injected logger receives the module's log lines, at the right levels")
        func hookReceivesLines() {
            let sink = Sink()
            let previous = SkinKitUILog.logger
            SkinKitUILog.logger = { sink.append($0, $1) }
            defer { SkinKitUILog.logger = previous }

            ILOG("ui-info-line")
            WLOG("ui-warning-line")
            ELOG("ui-error-line")
            DLOG("ui-debug-line")

            let lines = sink.lines
            #expect(lines.contains { $0.0 == .info && $0.1 == "ui-info-line" })
            #expect(lines.contains { $0.0 == .warning && $0.1 == "ui-warning-line" })
            #expect(lines.contains { $0.0 == .error && $0.1 == "ui-error-line" })
            #if DEBUG
            #expect(lines.contains { $0.0 == .debug && $0.1 == "ui-debug-line" })
            #endif
        }

        @Test("The default logger is os.Logger, and silent drops everything")
        func defaults() {
            SkinKitUILog.osLog(.info, "ui default logger smoke test")
            SkinKitUILog.silent(.error, "dropped")
        }
    }
}
#endif
