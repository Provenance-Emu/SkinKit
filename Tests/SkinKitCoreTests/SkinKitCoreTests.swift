import XCTest
@testable import SkinKitCore

final class SkinKitCoreTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertFalse(SkinKitCore.version.isEmpty)
    }
}
