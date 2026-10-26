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
