import Foundation
import SkinKitCore
import Testing
@testable import SkinKitManager

/// Ported from Provenance's `DeltaSkinSelectionManagerTests`. Provenance's tests used the shared
/// singletons and cleaned up after themselves; these use fresh instances over an isolated
/// `UserDefaults` suite. The test that sets the global companion-skin matcher restores it, and the
/// suite is serialized so nothing else reads it meanwhile.
@Suite("DeltaSkinSelectionManager", .serialized)
@MainActor
final class DeltaSkinSelectionManagerTests {
    private let testSystem = SkinSystemID("com.provenance.nes")
    private let testGameId = "pvui-delta-skin-selection-manager-tests-game"
    /// Second key for the same game (pickers store games under `PVGame.id` or `md5Hash`).
    private let testGameAltId = "pvui-delta-skin-selection-manager-tests-game-md5"

    private let defaults: UserDefaults
    private let cleanup: () -> Void
    private let prefs: DeltaSkinPreferences
    private let manager: DeltaSkinSelectionManager

    init() {
        (defaults, cleanup) = TestSupport.makeDefaults()
        prefs = DeltaSkinPreferences(defaults: defaults)
        manager = DeltaSkinSelectionManager(preferences: prefs)
    }

    deinit {
        cleanup()
    }

    @Test func gameScopedBuiltInTokenDoesNotFallThroughToSystemPreference() {
        prefs.setSelectedSkin("fake-system-only-skin-id", for: testSystem, orientation: .portrait)
        manager.setSkin(
            DeltaSkinSelectionManager.builtInSkinPreferenceToken,
            for: testSystem,
            gameId: testGameId,
            orientation: .portrait,
            scope: .game
        )

        let effective = manager.effectiveGameSkinIdentifier(for: testSystem, gameId: testGameId, orientation: .portrait)
        #expect(effective == nil)
    }

    @Test func sessionBuiltInTokenDoesNotFallThroughToSystemPreference() {
        prefs.setSelectedSkin("fake-system-only-skin-id", for: testSystem, orientation: .landscape)
        manager.setSkin(
            DeltaSkinSelectionManager.builtInSkinPreferenceToken,
            for: testSystem,
            gameId: testGameId,
            orientation: .landscape,
            scope: .session
        )

        let effective = manager.effectiveGameSkinIdentifier(for: testSystem, gameId: testGameId, orientation: .landscape)
        #expect(effective == nil)
    }

    @Test func prefersBuiltInWhenGamePreferenceIsToken() {
        manager.setSkin(
            DeltaSkinSelectionManager.builtInSkinPreferenceToken,
            for: testSystem,
            gameId: testGameId,
            orientation: .portrait,
            scope: .game
        )
        #expect(manager.prefersBuiltInControllerSkin(for: testSystem, gameId: testGameId, orientation: .portrait))
    }

    @Test func prefersBuiltInFalseWhenSessionOverridesWithRealSkin() {
        manager.setSkin(
            DeltaSkinSelectionManager.builtInSkinPreferenceToken,
            for: testSystem,
            gameId: testGameId,
            orientation: .portrait,
            scope: .game
        )
        manager.setSkin("com.example.real-skin", for: testSystem, gameId: testGameId, orientation: .portrait, scope: .session)
        #expect(!manager.prefersBuiltInControllerSkin(for: testSystem, gameId: testGameId, orientation: .portrait))
    }

    @Test func prefersBuiltInFalseWhenNoToken() {
        #expect(!manager.prefersBuiltInControllerSkin(for: testSystem, gameId: testGameId, orientation: .portrait))
    }

    // MARK: - hasExplicitPackagedSkinSelection

    @Test func explicitSelectionFalseWithoutAnySelection() {
        let gameIds = [testGameId, testGameAltId]
        #expect(!manager.hasExplicitPackagedSkinSelection(for: testSystem, gameIds: gameIds))
    }

    @Test func effectiveIdentifierFindsPickStoredUnderADifferentGameKey() {
        prefs.setSelectedSkin("skin-from-boot", for: testSystem, orientation: .portrait)
        manager.setSkin("skin-picked-live", for: testSystem, gameId: testGameId, orientation: .portrait, scope: .session)

        let resolved = manager.effectiveSkinIdentifier(
            for: testSystem,
            gameIds: [testGameId, testGameAltId],
            orientation: .portrait
        )
        #expect(resolved == "skin-picked-live")
        #expect(manager.effectiveSkinIdentifier(for: testSystem, gameIds: [testGameAltId], orientation: .portrait) == "skin-from-boot")
    }

    @Test func explicitSelectionTrueForGameSkinInEitherOrientationOrKey() {
        // Landscape-only pick, stored under the second game key.
        manager.setSkin("com.example.gc-skin", for: testSystem, gameId: testGameAltId, orientation: .landscape, scope: .game)
        #expect(manager.hasExplicitPackagedSkinSelection(for: testSystem, gameIds: [testGameId, testGameAltId]))
        #expect(!manager.hasExplicitPackagedSkinSelection(for: testSystem, gameIds: [testGameId]))
    }

    @Test func explicitSelectionTrueForSystemSkin() {
        manager.setSkin("com.example.gc-skin", for: testSystem, gameId: nil, orientation: .portrait, scope: .system)
        #expect(manager.hasExplicitPackagedSkinSelection(for: testSystem, gameIds: [testGameId]))
    }

    @Test func explicitSelectionFalseForBuiltInToken() {
        for orientation in SkinOrientation.allCases {
            manager.setSkin(DeltaSkinSelectionManager.builtInSkinPreferenceToken, for: testSystem, gameId: testGameId, orientation: orientation, scope: .game)
        }
        #expect(!manager.hasExplicitPackagedSkinSelection(for: testSystem, gameIds: [testGameId]))
    }

    @Test func gameBuiltInTokenMasksSystemSkin() {
        for orientation in SkinOrientation.allCases {
            prefs.setSelectedSkin("com.example.gc-skin", for: testSystem, orientation: orientation)
            manager.setSkin(DeltaSkinSelectionManager.builtInSkinPreferenceToken, for: testSystem, gameId: testGameId, orientation: orientation, scope: .game)
        }
        #expect(!manager.hasExplicitPackagedSkinSelection(for: testSystem, gameIds: [testGameAltId, testGameId]))
    }

    /// Provenance's test read an id out of `CaseControllerDetector.knownLayouts`; the detector is the
    /// app's, so the app's matcher is stood in for here.
    @Test func caseCompanionSessionSkinIsNotAnExplicitSelection() {
        let caseSkinId = "com.example.case-companion-skin"
        let previous = DeltaSkinCompanionSkinDetection.matcher
        DeltaSkinCompanionSkinDetection.matcher = { $0 == caseSkinId }
        defer { DeltaSkinCompanionSkinDetection.matcher = previous }

        // What CaseControllerSkinCoordinator writes when a case is detected.
        manager.setSkin(caseSkinId, for: testSystem, gameId: nil, orientation: .portrait, scope: .session)
        #expect(!manager.hasExplicitPackagedSkinSelection(for: testSystem, gameIds: [testGameId]))

        // A real pick next to it still counts.
        manager.setSkin("com.example.real", for: testSystem, gameId: nil, orientation: .landscape, scope: .system)
        #expect(manager.hasExplicitPackagedSkinSelection(for: testSystem, gameIds: [testGameId]))
    }

    @Test func systemPickClearsSessionEntryAndPreferenceIsEffective() {
        manager.setSkin("com.example.game-session", for: testSystem, gameId: testGameId, orientation: .portrait, scope: .session)
        manager.setSkin("com.example.system-pick", for: testSystem, gameId: testGameId, orientation: .portrait, scope: .system)

        #expect(manager.getSessionSkin(for: testSystem, gameId: testGameId, orientation: .portrait) == nil)
        #expect(manager.getSessionSkin(for: testSystem, gameId: nil, orientation: .portrait) == nil)
        #expect(manager.effectiveSkinIdentifier(for: testSystem, gameId: testGameId, orientation: .portrait) == "com.example.system-pick")
    }

    /// The pause-menu picker opens on System; a pick there must beat an older pick for the running game.
    @Test func systemPickWithGameReplacesThatGamesOverride() {
        manager.setSkin("com.example.old-game-pick", for: testSystem, gameId: testGameId, orientation: .portrait, scope: .game)
        manager.setSkin("com.example.system-pick", for: testSystem, gameId: testGameId, orientation: .portrait, scope: .system)

        #expect(manager.storedSkinIdentifier(for: testSystem, gameId: testGameId, orientation: .portrait, scope: .game) == nil)
        #expect(manager.effectiveSkinIdentifier(for: testSystem, gameId: testGameId, orientation: .portrait) == "com.example.system-pick")
    }

    /// The classic menu stored game picks under md5; rotation still reads that key.
    @Test func systemPickClearsTheGamesOverrideUnderItsOtherKeys() {
        manager.setSkin("com.example.md5-game-pick", for: testSystem, gameId: testGameAltId, orientation: .portrait, scope: .game)
        manager.setSkin("com.example.system-pick", for: testSystem, gameId: testGameId, otherGameKeys: [testGameAltId],
                        orientation: .portrait, scope: .system)

        #expect(manager.effectiveSkinIdentifier(for: testSystem, gameIds: [testGameId, testGameAltId], orientation: .portrait)
            == "com.example.system-pick")
    }

    @Test func systemPickKeepsOtherGamesOverrides() {
        manager.setSkin("com.example.other-game-pick", for: testSystem, gameId: testGameAltId, orientation: .portrait, scope: .game)
        manager.setSkin("com.example.system-pick", for: testSystem, gameId: testGameId, orientation: .portrait, scope: .system)

        #expect(manager.effectiveSkinIdentifier(for: testSystem, gameId: testGameAltId, orientation: .portrait)
            == "com.example.other-game-pick")
    }

    @Test func gamePickClearsSessionEntryAndPreferenceIsEffective() {
        manager.setSkin("com.example.game-session", for: testSystem, gameId: testGameId, orientation: .landscape, scope: .session)
        manager.setSkin("com.example.game-pick", for: testSystem, gameId: testGameId, orientation: .landscape, scope: .game)

        #expect(manager.getSessionSkin(for: testSystem, gameId: testGameId, orientation: .landscape) == nil)
        #expect(manager.effectiveSkinIdentifier(for: testSystem, gameId: testGameId, orientation: .landscape) == "com.example.game-pick")
    }

    @Test func gamePickIsNotShadowedBySystemLevelSessionSkin() {
        // System-level session entry, as the case-companion coordinator writes.
        manager.setSkin("com.example.case-companion", for: testSystem, gameId: nil, orientation: .portrait, scope: .session)
        manager.setSkin("com.example.game-pick", for: testSystem, gameId: testGameId, orientation: .portrait, scope: .game)

        #expect(manager.getSessionSkin(for: testSystem, gameId: nil, orientation: .portrait) == nil)
        #expect(manager.effectiveSkinIdentifier(for: testSystem, gameId: testGameId, orientation: .portrait) == "com.example.game-pick")
    }

    @Test func systemPickSurvivesLaterSessionClear() {
        manager.setSkin("com.example.session", for: testSystem, gameId: nil, orientation: .portrait, scope: .session)
        manager.setSkin("com.example.system-pick", for: testSystem, gameId: nil, orientation: .portrait, scope: .system)
        manager.setSkin(nil, for: testSystem, gameId: nil, orientation: .portrait, scope: .session)

        #expect(manager.effectiveSkinIdentifier(for: testSystem, gameId: nil, orientation: .portrait) == "com.example.system-pick")
    }

    @Test func sessionPickStillWinsWhilePresent() {
        manager.setSkin("com.example.game-pick", for: testSystem, gameId: testGameId, orientation: .portrait, scope: .game)
        manager.setSkin("com.example.session-pick", for: testSystem, gameId: testGameId, orientation: .portrait, scope: .session)

        #expect(manager.effectiveSkinIdentifier(for: testSystem, gameId: testGameId, orientation: .portrait) == "com.example.session-pick")
    }

    // MARK: - New: persistence, notification, fallback

    @Test func persistentPicksSurviveANewManagerSessionPicksDoNot() {
        manager.setSkin("com.example.system-pick", for: testSystem, gameId: nil, orientation: .portrait, scope: .system)
        manager.setSkin("com.example.game-pick", for: testSystem, gameId: testGameId, orientation: .portrait, scope: .game)
        manager.setSkin("com.example.session-pick", for: testSystem, gameId: nil, orientation: .landscape, scope: .session)

        let relaunched = DeltaSkinSelectionManager(preferences: DeltaSkinPreferences(defaults: defaults))
        #expect(relaunched.effectiveSkinIdentifier(for: testSystem, gameId: testGameId, orientation: .portrait) == "com.example.game-pick")
        #expect(relaunched.effectiveSkinIdentifier(for: testSystem, gameId: nil, orientation: .portrait) == "com.example.system-pick")
        #expect(relaunched.effectiveSkinIdentifier(for: testSystem, gameId: nil, orientation: .landscape) == nil)
    }

    @Test func settingASkinPostsTheSelectionChangedNotification() {
        #expect(DeltaSkinSelectionManager.selectionChangedNotification.rawValue == "DeltaSkinSelectionChanged")
        // `setSkin` posts synchronously on the main actor, so a main-queue observer sees it inline.
        final class Box: @unchecked Sendable { var seen: [Notification] = [] }
        let box = Box()
        let token = NotificationCenter.default.addObserver(
            forName: DeltaSkinSelectionManager.selectionChangedNotification, object: nil, queue: nil
        ) { box.seen.append($0) }
        defer { NotificationCenter.default.removeObserver(token) }

        manager.setSkin("com.example.pick", for: testSystem, gameId: testGameId, orientation: .landscape, scope: .game)

        let note = box.seen.last { ($0.userInfo?["gameId"] as? String) == testGameId }
        #expect(note?.userInfo?["skinIdentifier"] as? String == "com.example.pick")
        #expect(note?.userInfo?["systemId"] as? String == "com.provenance.nes")
        #expect(note?.userInfo?["orientation"] as? String == "landscape")
        #expect(note?.userInfo?["scope"] as? String == "Game")
    }

    @Test func gameScopeWithoutAGameIdChangesNothing() {
        manager.setSkin("com.example.pick", for: testSystem, gameId: nil, orientation: .portrait, scope: .game)
        #expect(manager.effectiveSkinIdentifier(for: testSystem, gameId: nil, orientation: .portrait) == nil)
    }

    private func skin(_ id: String, orientations: Set<DeltaSkinOrientation>) -> StubSkin {
        var skin = StubSkin(identifier: id, name: id, gameType: .nes, fileURL: URL(fileURLWithPath: "/tmp/\(id).deltaskin"))
        skin.supported = { orientations.contains($0.orientation) }
        return skin
    }

    @Test func fallbackKeepsASelectionThatSupportsTheOrientation() {
        manager.setSkin("a", for: testSystem, gameId: nil, orientation: .portrait, scope: .system)
        let chosen = manager.effectiveSkinIdentifierWithFallback(
            for: testSystem, orientation: .portrait,
            availableSkins: [skin("a", orientations: [.portrait]), skin("b", orientations: [.portrait, .landscape])]
        )
        #expect(chosen == "a")
    }

    @Test func fallbackFindsAnotherSkinWhenTheSelectionLacksTheOrientation() {
        manager.setSkin("a", for: testSystem, gameId: nil, orientation: .landscape, scope: .system)
        let available = [skin("a", orientations: [.portrait]), skin("b", orientations: [.landscape])]
        #expect(manager.effectiveSkinIdentifierWithFallback(for: testSystem, orientation: .landscape, availableSkins: available) == "b")
    }

    @Test func fallbackReturnsNilForAnUnknownSelectionOrNoFallback() {
        manager.setSkin("gone", for: testSystem, gameId: nil, orientation: .portrait, scope: .system)
        #expect(manager.effectiveSkinIdentifierWithFallback(
            for: testSystem, orientation: .portrait, availableSkins: [skin("a", orientations: [.portrait])]
        ) == nil)

        manager.setSkin("a", for: testSystem, gameId: nil, orientation: .landscape, scope: .system)
        #expect(manager.effectiveSkinIdentifierWithFallback(
            for: testSystem, orientation: .landscape, availableSkins: [skin("a", orientations: [.portrait])]
        ) == nil)
    }

    @Test func fallbackSkipsCaseCompanionSkinsUnlessTheAppAllowsThem() {
        let caseSkinId = "com.example.case-companion-skin"
        let previous = DeltaSkinCompanionSkinDetection.matcher
        DeltaSkinCompanionSkinDetection.matcher = { $0 == caseSkinId }
        defer { DeltaSkinCompanionSkinDetection.matcher = previous }

        manager.setSkin("a", for: testSystem, gameId: nil, orientation: .landscape, scope: .system)
        let available = [skin("a", orientations: [.portrait]), skin(caseSkinId, orientations: [.landscape])]

        #expect(manager.effectiveSkinIdentifierWithFallback(for: testSystem, orientation: .landscape, availableSkins: available) == nil)

        manager.allowsCaseControllerSkinFallback = { true }
        #expect(manager.effectiveSkinIdentifierWithFallback(for: testSystem, orientation: .landscape, availableSkins: available) == caseSkinId)
    }

    @Test func fallbackUsesTheInjectedDevice() {
        manager.setSkin("a", for: testSystem, gameId: nil, orientation: .portrait, scope: .system)
        var onlyIPad = StubSkin(identifier: "a", name: "a", gameType: .nes, fileURL: URL(fileURLWithPath: "/tmp/a.deltaskin"))
        onlyIPad.supported = { $0.device == .ipad }

        manager.fallbackDevice = { .iphone }
        #expect(manager.effectiveSkinIdentifierWithFallback(for: testSystem, orientation: .portrait, availableSkins: [onlyIPad]) == nil)
        manager.fallbackDevice = { .ipad }
        #expect(manager.effectiveSkinIdentifierWithFallback(for: testSystem, orientation: .portrait, availableSkins: [onlyIPad]) == "a")
    }
}
