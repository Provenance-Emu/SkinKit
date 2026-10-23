import Foundation
import SkinKitCore
import Testing
@testable import SkinKitManager

/// Preferences keep Provenance's `UserDefaults` keys and formats, so a user's picks survive the move.
@Suite("DeltaSkinPreferences")
@MainActor
struct DeltaSkinPreferencesTests {
    let defaults: UserDefaults
    let cleanup: () -> Void

    init() {
        (defaults, cleanup) = TestSupport.makeDefaults()
    }

    @Test("Keys are the ones Provenance wrote")
    func keysAreUnchanged() {
        #expect(DeltaSkinPreferences.preferencesKey == "com.provenance.deltaskin.preferences.v2")
        #expect(DeltaSkinPreferences.gamePreferencesKey == "com.provenance.deltaskin.game.preferences.v1")
        #expect(DeltaSkinPreferences.legacyPreferencesKey == "com.provenance.deltaskin.preferences")
    }

    @Test("System picks are per orientation and persist across instances")
    func systemPicksPersist() {
        defer { cleanup() }
        let prefs = DeltaSkinPreferences(defaults: defaults)
        prefs.setSelectedSkin("skin.portrait", for: SkinSystemID("com.provenance.nes"), orientation: .portrait)
        prefs.setSelectedSkin("skin.landscape", for: SkinSystemID("com.provenance.nes"), orientation: .landscape)

        let reloaded = DeltaSkinPreferences(defaults: defaults)
        #expect(reloaded.selectedSkinIdentifier(for: SkinSystemID("com.provenance.nes"), orientation: .portrait) == "skin.portrait")
        #expect(reloaded.selectedSkinIdentifier(for: SkinSystemID("com.provenance.nes"), orientation: .landscape) == "skin.landscape")
        #expect(reloaded.selectedSkinIdentifier(for: SkinSystemID("com.provenance.nes")) == "skin.portrait")
    }

    @Test("The stored v2 format is {system: {orientation: skin}} JSON")
    func v2Format() throws {
        defer { cleanup() }
        let prefs = DeltaSkinPreferences(defaults: defaults)
        prefs.setSelectedSkin("skin.a", for: SkinSystemID("com.provenance.snes"), orientation: .landscape)

        let data = try #require(defaults.data(forKey: DeltaSkinPreferences.preferencesKey))
        let decoded = try JSONDecoder().decode([String: [String: String]].self, from: data)
        #expect(decoded == ["com.provenance.snes": ["landscape": "skin.a"]])
    }

    @Test("Reads a v2 record Provenance wrote")
    func readsExistingV2() throws {
        defer { cleanup() }
        let seeded = ["com.provenance.gba": ["portrait": "skin.gba", "landscape": "skin.gba.l"]]
        defaults.set(try JSONEncoder().encode(seeded), forKey: "com.provenance.deltaskin.preferences.v2")

        let prefs = DeltaSkinPreferences(defaults: defaults)
        #expect(prefs.selectedSkinIdentifier(for: SkinSystemID("com.provenance.gba"), orientation: .landscape) == "skin.gba.l")
    }

    @Test("Migrates the legacy format to portrait v2 and removes it")
    func migratesLegacy() throws {
        defer { cleanup() }
        let legacy = ["com.provenance.gba": "skin.gba", "com.provenance.nes": "skin.nes"]
        defaults.set(try JSONEncoder().encode(legacy), forKey: "com.provenance.deltaskin.preferences")

        let prefs = DeltaSkinPreferences(defaults: defaults)
        #expect(prefs.selectedSkinIdentifier(for: SkinSystemID("com.provenance.gba"), orientation: .portrait) == "skin.gba")
        #expect(prefs.selectedSkinIdentifier(for: SkinSystemID("com.provenance.gba"), orientation: .landscape) == nil)
        #expect(defaults.data(forKey: "com.provenance.deltaskin.preferences") == nil)

        let v2 = try #require(defaults.data(forKey: DeltaSkinPreferences.preferencesKey))
        let decoded = try JSONDecoder().decode([String: [String: String]].self, from: v2)
        #expect(decoded["com.provenance.nes"] == ["portrait": "skin.nes"])
    }

    @Test("Per-game picks are keyed by any id string (id, md5 or crc) and persist")
    func gamePicks() throws {
        defer { cleanup() }
        let prefs = DeltaSkinPreferences(defaults: defaults)
        prefs.setSelectedSkin("skin.by.id", for: "game-id", orientation: .portrait)
        prefs.setSelectedSkin("skin.by.md5", for: "d41d8cd98f00b204e9800998ecf8427e", orientation: .landscape)
        prefs.setSelectedSkin("skin.by.crc", for: "DEADBEEF", orientation: .portrait)

        let reloaded = DeltaSkinPreferences(defaults: defaults)
        #expect(reloaded.selectedSkinIdentifier(for: "game-id", orientation: .portrait) == "skin.by.id")
        #expect(reloaded.selectedSkinIdentifier(for: "d41d8cd98f00b204e9800998ecf8427e", orientation: .landscape) == "skin.by.md5")
        #expect(reloaded.selectedSkinIdentifier(for: "DEADBEEF", orientation: .portrait) == "skin.by.crc")
        #expect(reloaded.selectedSkinIdentifier(for: "game-id", orientation: .landscape) == nil)

        let data = try #require(defaults.data(forKey: DeltaSkinPreferences.gamePreferencesKey))
        let decoded = try JSONDecoder().decode([String: [String: String]].self, from: data)
        #expect(decoded["game-id"] == ["portrait": "skin.by.id"])
    }

    @Test("A game pick wins over the system pick; clearing falls back")
    func effectiveFallsBackToSystem() {
        defer { cleanup() }
        let prefs = DeltaSkinPreferences(defaults: defaults)
        let system = SkinSystemID("com.provenance.n64")
        prefs.setSelectedSkin("skin.system", for: system, orientation: .portrait)
        #expect(prefs.effectiveSkinIdentifier(for: "game", system: system) == "skin.system")

        prefs.setSelectedSkin("skin.game", for: "game", orientation: .portrait)
        #expect(prefs.effectiveSkinIdentifier(for: "game", system: system) == "skin.game")

        prefs.setSelectedSkin(nil, for: "game", orientation: .portrait)
        #expect(prefs.effectiveSkinIdentifier(for: "game", system: system) == "skin.system")
        #expect(prefs.gameSpecificSkins["game"] == nil, "an emptied game entry is removed")
    }

    @Test("Clearing both orientations removes the system entry")
    func clearingRemovesEntry() {
        defer { cleanup() }
        let prefs = DeltaSkinPreferences(defaults: defaults)
        let system = SkinSystemID("com.provenance.nes")
        prefs.setSelectedSkin("a", for: system, orientation: .portrait)
        prefs.setSelectedSkin("b", for: system, orientation: .landscape)
        prefs.setSelectedSkin(nil, for: system, orientation: .portrait)
        #expect(prefs.selectedSkins[system] == [.landscape: "b"])
        prefs.setSelectedSkin(nil, for: system, orientation: .landscape)
        #expect(prefs.selectedSkins[system] == nil)
    }

    @Test("The observer hears system picks, but not the built-in token or clears")
    func observerHearsRealPicks() {
        defer { cleanup() }
        let prefs = DeltaSkinPreferences(defaults: defaults)
        var heard: [String] = []
        prefs.systemSkinSelectionObserver = { heard.append($0) }
        let system = SkinSystemID("com.provenance.gba")

        prefs.setSelectedSkin("com.example.real", for: system, orientation: .portrait)
        prefs.setSelectedSkin(DeltaSkinSelectionManager.builtInSkinPreferenceToken, for: system, orientation: .landscape)
        prefs.setSelectedSkin(nil, for: system, orientation: .portrait)
        prefs.setSelectedSkin("com.example.game", for: "a-game", orientation: .portrait)

        #expect(heard == ["com.example.real"])
    }

    @Test("A system id Provenance no longer knows is kept, not dropped")
    func unknownSystemKeysAreKept() throws {
        defer { cleanup() }
        let seeded = ["com.provenance.retired-system": ["portrait": "skin.old"]]
        defaults.set(try JSONEncoder().encode(seeded), forKey: DeltaSkinPreferences.preferencesKey)

        let prefs = DeltaSkinPreferences(defaults: defaults)
        #expect(prefs.selectedSkinIdentifier(for: SkinSystemID("com.provenance.retired-system"), orientation: .portrait) == "skin.old")
    }

    @Test("Theme picks use SkinKitCore's storage")
    func themeSelectionUsesCore() {
        let prefs = DeltaSkinPreferences(defaults: defaults)
        let skinId = "com.test.theme-\(UUID().uuidString)"
        defer {
            cleanup()
            DeltaSkinThemeSelection.setSelectedThemeId(nil, for: skinId)
        }
        #expect(prefs.selectedThemeId(for: skinId) == nil)
        prefs.setSelectedThemeId("dark", for: skinId)
        #expect(prefs.selectedThemeId(for: skinId) == "dark")
        #expect(DeltaSkinThemeSelection.selectedThemeId(for: skinId) == "dark")
    }
}
