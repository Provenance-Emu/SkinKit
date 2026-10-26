import Foundation
import SkinKitCore
import Testing
@testable import SkinKitManager

/// iFly's `effectiveSkinIdentifier` checked the system session pick before the game session pick;
/// Provenance's checks the game pick first. `sessionPickOrder` keeps both.
@Suite("DeltaSkinSelectionManager.sessionPickOrder", .serialized)
@MainActor
final class DeltaSkinSessionPickOrderTests {
    private let system = SkinSystemID("Dreamcast")
    private let gameId = "game-1"

    private let cleanup: () -> Void
    private let prefs: DeltaSkinPreferences
    private let manager: DeltaSkinSelectionManager

    init() {
        let (defaults, cleanup) = TestSupport.makeDefaults()
        self.cleanup = cleanup
        prefs = DeltaSkinPreferences(defaults: defaults)
        manager = DeltaSkinSelectionManager(preferences: prefs)
    }

    deinit { cleanup() }

    private func setBothSessionPicks() {
        manager.setSkin("system-pick", for: system, gameId: nil, orientation: .portrait, scope: .session)
        manager.setSkin("game-pick", for: system, gameId: gameId, orientation: .portrait, scope: .session)
    }

    @Test func defaultsToGameFirst() {
        #expect(manager.sessionPickOrder == .gameFirst)
        setBothSessionPicks()
        #expect(manager.effectiveSkinIdentifier(for: system, gameId: gameId, orientation: .portrait) == "game-pick")
    }

    @Test func systemFirstChecksTheSystemPickFirst() {
        manager.sessionPickOrder = .systemFirst
        setBothSessionPicks()
        #expect(manager.effectiveSkinIdentifier(for: system, gameId: gameId, orientation: .portrait) == "system-pick")
    }

    @Test func effectiveGameSkinIdentifierIsGameFirstWhateverTheOption() {
        manager.sessionPickOrder = .systemFirst
        setBothSessionPicks()
        #expect(manager.effectiveGameSkinIdentifier(for: system, gameId: gameId, orientation: .portrait) == "game-pick")
    }

    @Test func systemFirstFallsBackToTheGamePickWhenThereIsNoSystemPick() {
        manager.sessionPickOrder = .systemFirst
        manager.setSkin("game-pick", for: system, gameId: gameId, orientation: .portrait, scope: .session)
        #expect(manager.effectiveSkinIdentifier(for: system, gameId: gameId, orientation: .portrait) == "game-pick")
    }

    @Test func persistedPicksStillRankGameOverSystemInEitherOrder() {
        prefs.setSelectedSkin("system-pref", for: system, orientation: .portrait)
        prefs.setSelectedSkin("game-pref", for: gameId, orientation: .portrait)
        for order in [DeltaSkinSelectionManager.SessionPickOrder.gameFirst, .systemFirst] {
            manager.sessionPickOrder = order
            #expect(manager.effectiveSkinIdentifier(for: system, gameId: gameId, orientation: .portrait) == "game-pref")
        }
    }

    @Test func aSessionPickOutranksPersistedPicksInEitherOrder() {
        prefs.setSelectedSkin("game-pref", for: gameId, orientation: .portrait)
        manager.setSkin("system-pick", for: system, gameId: nil, orientation: .portrait, scope: .session)
        for order in [DeltaSkinSelectionManager.SessionPickOrder.gameFirst, .systemFirst] {
            manager.sessionPickOrder = order
            #expect(manager.effectiveSkinIdentifier(for: system, gameId: gameId, orientation: .portrait) == "system-pick")
        }
    }

    @Test func theBuiltInTokenStillStopsTheLookup() {
        prefs.setSelectedSkin("system-pref", for: system, orientation: .portrait)
        manager.sessionPickOrder = .systemFirst
        manager.setSkin(
            DeltaSkinSelectionManager.builtInSkinPreferenceToken,
            for: system, gameId: nil, orientation: .portrait, scope: .session
        )
        #expect(manager.effectiveSkinIdentifier(for: system, gameId: gameId, orientation: .portrait) == nil)
    }
}

/// `prefersBuiltInControllerSkin(for:gameId:orientation:)` must answer from the same chain, in the same
/// order, as `effectiveSkinIdentifier`: when one says "built-in", the other must not hand out a
/// packaged skin.
@Suite("DeltaSkinSelectionManager built-in check follows sessionPickOrder", .serialized)
@MainActor
final class DeltaSkinBuiltInPickOrderTests {
    private let system = SkinSystemID("Dreamcast")
    private let gameId = "game-1"
    private let token = DeltaSkinSelectionManager.builtInSkinPreferenceToken

    private let cleanup: () -> Void
    private let manager: DeltaSkinSelectionManager

    init() {
        let (defaults, cleanup) = TestSupport.makeDefaults()
        self.cleanup = cleanup
        manager = DeltaSkinSelectionManager(preferences: DeltaSkinPreferences(defaults: defaults))
    }

    deinit { cleanup() }

    private func setPicks(system systemPick: String, game gamePick: String) {
        manager.setSkin(systemPick, for: system, gameId: nil, orientation: .portrait, scope: .session)
        manager.setSkin(gamePick, for: system, gameId: gameId, orientation: .portrait, scope: .session)
    }

    private func answers() -> (effective: String?, builtIn: Bool) {
        (
            manager.effectiveSkinIdentifier(for: system, gameId: gameId, orientation: .portrait),
            manager.prefersBuiltInControllerSkin(for: system, gameId: gameId, orientation: .portrait)
        )
    }

    @Test func systemBuiltInWithGameSkin_gameFirst() {
        setPicks(system: token, game: "game-skin")
        let a = answers()
        #expect(a.effective == "game-skin")
        #expect(a.builtIn == false)
    }

    @Test func systemBuiltInWithGameSkin_systemFirst() {
        manager.sessionPickOrder = .systemFirst
        setPicks(system: token, game: "game-skin")
        let a = answers()
        #expect(a.effective == nil)
        #expect(a.builtIn == true)
    }

    @Test func systemSkinWithGameBuiltIn_gameFirst() {
        setPicks(system: "system-skin", game: token)
        let a = answers()
        #expect(a.effective == nil)
        #expect(a.builtIn == true)
    }

    @Test func systemSkinWithGameBuiltIn_systemFirst() {
        manager.sessionPickOrder = .systemFirst
        setPicks(system: "system-skin", game: token)
        let a = answers()
        #expect(a.effective == "system-skin")
        #expect(a.builtIn == false)
    }

    @Test func noPicksPrefersNothing() {
        for order in [DeltaSkinSelectionManager.SessionPickOrder.gameFirst, .systemFirst] {
            manager.sessionPickOrder = order
            let a = answers()
            #expect(a.effective == nil)
            #expect(a.builtIn == false)
        }
    }

    @Test func multiKeyVariantStaysGameFirst() {
        manager.sessionPickOrder = .systemFirst
        setPicks(system: token, game: "game-skin")
        #expect(manager.prefersBuiltInControllerSkin(for: system, gameIds: [gameId], orientation: .portrait) == false)
    }
}
