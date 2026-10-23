import XCTest
@testable import SkinCatalogKit

final class SkinCatalogKitTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertFalse(SkinCatalogKit.version.isEmpty)
    }
}
