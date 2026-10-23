import Foundation
import SkinCatalogKit
import SkinKitCore
import Testing
@testable import SkinKitManager

@Suite("SkinStorePolicy install helpers")
struct SkinStorePolicyInstallTests {
    /// iFly's `SkinCompatibility.retargetedIdentifier`: add the target's suffix once.
    private func iFlyIdentifier(_ original: String, target: String) -> String {
        let suffix = target == "arcade" ? ".arcade" : ".dreamcast"
        let base = original.isEmpty ? "imported.skin" : original
        return base.hasSuffix(suffix) ? base : base + suffix
    }

    @Test("installedIdentifier is the skin's own id as-is, and the app's retargeted id otherwise")
    func installedIdentifier() {
        let policy = SkinStorePolicy.iFly
        #expect(policy.installedIdentifier(for: "com.x.skin", target: nil, retargetedIdentifier: iFlyIdentifier) == "com.x.skin")
        #expect(policy.installedIdentifier(for: "com.x.skin", target: "dreamcast", retargetedIdentifier: iFlyIdentifier) == "com.x.skin.dreamcast")
        #expect(policy.installedIdentifier(for: "com.x.skin.arcade", target: "arcade", retargetedIdentifier: iFlyIdentifier) == "com.x.skin.arcade")
        #expect(policy.installedIdentifier(for: "", target: "dreamcast", retargetedIdentifier: iFlyIdentifier) == "imported.skin.dreamcast")
    }

    @Test("iFly routing: Dreamcast keeps supported skins, arcade and other systems always retarget")
    func iFlyRetargeting() {
        let policy = SkinStorePolicy.iFly
        // iFly accepts Dreamcast, Naomi, Naomi 2 and Atomiswave; SkinKitCore has no Naomi cases yet, so
        // the arcade stand-in here is MAME.
        let accepted: Set<DeltaSkinGameType> = [.dreamcast, .mame]

        #expect(policy.retarget(for: .dreamcast, skinGameType: .dreamcast, acceptedGameTypes: accepted) == nil)
        #expect(policy.retarget(for: .dreamcast, skinGameType: .gba, acceptedGameTypes: accepted) == "dreamcast")
        #expect(policy.retarget(for: .dreamcast, skinGameType: nil, acceptedGameTypes: accepted) == "dreamcast")
        #expect(policy.retarget(for: .arcade, skinGameType: .mame, acceptedGameTypes: accepted) == "arcade")
        #expect(policy.retarget(for: .otherSystems, skinGameType: .n64, acceptedGameTypes: accepted) == "dreamcast")
    }

    @Test("iCube routing: only the N64 shelf retargets, to the GameCube pad")
    func iCubeRetargeting() {
        let policy = SkinStorePolicy.iCube
        #expect(policy.retarget(for: .gameCube, skinGameType: .n64, acceptedGameTypes: []) == nil)
        #expect(policy.retarget(for: .wii, skinGameType: nil, acceptedGameTypes: []) == nil)
        #expect(policy.retarget(for: .nintendo64, skinGameType: .n64, acceptedGameTypes: []) == "gamecube")
    }
}
