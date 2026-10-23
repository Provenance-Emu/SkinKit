import XCTest
@testable import SkinKitManager

final class SkinKitManagerTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertFalse(SkinKitManager.version.isEmpty)
    }
}
