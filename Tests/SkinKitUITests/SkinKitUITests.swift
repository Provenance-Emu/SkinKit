import XCTest
@testable import SkinKitUI

final class SkinKitUITests: XCTestCase {
    func testModuleLoads() {
        XCTAssertFalse(SkinKitUI.version.isEmpty)
    }
}
