#if canImport(UIKit)
import Foundation
import SkinKitCore
import Testing
// Deliberately not `@testable`: these check what an app can see.
import SkinKitUI

extension UIKitSerial {
    @Suite("Public API for apps")
    struct PublicInitTests {
        @Test("StickyButtonManager has a public init")
        func stickyManagerInit() {
            let manager = StickyButtonManager()
            #expect(manager.stickyButtons.isEmpty)
        }

        @Test("A system with no catalog code has a nil code, not an empty string")
        func systemWithoutCatalogCode() {
            let system = DeltaSkinSystem(id: SkinSystemID("CPS1"), fullName: "Capcom Play System", gameType: nil)
            #expect(system.skinCatalogSystemCode == nil)
            #expect(system.relatedSkinCatalogSystemCodes.isEmpty)
        }

        @Test("A system with a catalog code keeps it")
        func systemWithCatalogCode() {
            let system = DeltaSkinSystem(id: SkinSystemID("GBA"), fullName: "Game Boy Advance", gameType: nil,
                                         skinCatalogSystemCode: "gba")
            #expect(system.skinCatalogSystemCode == "gba")
        }
    }
}
#endif
