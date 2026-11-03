import Foundation
import SkinKitCore
import Testing
@testable import SkinKitManager

/// The `toggleAltRepresentations` choice persists per game (the game skin pick's scope), kept per skin.
@Suite("altRepresentations preference")
@MainActor
struct DeltaSkinAltRepresentationsPreferenceTests {
    let defaults: UserDefaults
    let cleanup: () -> Void

    init() {
        (defaults, cleanup) = TestSupport.makeDefaults()
    }

    @Test("Off by default, on after setting, and it persists across instances")
    func persists() {
        defer { cleanup() }
        let prefs = DeltaSkinPreferences(defaults: defaults)
        #expect(!prefs.usesAltRepresentations(skinIdentifier: "com.ignited.ds", gameIds: ["game-1"]))

        prefs.setUsesAltRepresentations(true, skinIdentifier: "com.ignited.ds", gameId: "game-1")
        #expect(prefs.usesAltRepresentations(skinIdentifier: "com.ignited.ds", gameIds: ["game-1"]))

        let reloaded = DeltaSkinPreferences(defaults: defaults)
        #expect(reloaded.usesAltRepresentations(skinIdentifier: "com.ignited.ds", gameIds: ["game-1"]))
    }

    @Test("The choice is per game and per skin")
    func scoped() {
        defer { cleanup() }
        let prefs = DeltaSkinPreferences(defaults: defaults)
        prefs.setUsesAltRepresentations(true, skinIdentifier: "skin.a", gameId: "game-1")
        #expect(!prefs.usesAltRepresentations(skinIdentifier: "skin.a", gameIds: ["game-2"]))
        #expect(!prefs.usesAltRepresentations(skinIdentifier: "skin.b", gameIds: ["game-1"]))
    }

    @Test("Any of the game's keys finds the choice, and turning it off clears every key")
    func multipleKeys() {
        defer { cleanup() }
        let prefs = DeltaSkinPreferences(defaults: defaults)
        prefs.setUsesAltRepresentations(true, skinIdentifier: "skin.a", gameId: "MD5HASH")   // an older writer's key
        #expect(prefs.usesAltRepresentations(skinIdentifier: "skin.a", gameIds: ["game-1", "MD5HASH", "crc"]))

        prefs.setUsesAltRepresentations(false, skinIdentifier: "skin.a", gameId: "game-1", otherGameKeys: ["MD5HASH", "crc"])
        #expect(!prefs.usesAltRepresentations(skinIdentifier: "skin.a", gameIds: ["game-1", "MD5HASH", "crc"]))
        #expect(prefs.gameAltRepresentations.isEmpty)
    }

    @Test("The stored format is {gameId: [skinId]} JSON under its own key")
    func storedFormat() throws {
        defer { cleanup() }
        #expect(DeltaSkinPreferences.gameAltRepresentationsKey == "com.provenance.deltaskin.game.altRepresentations.v1")
        let prefs = DeltaSkinPreferences(defaults: defaults)
        prefs.setUsesAltRepresentations(true, skinIdentifier: "skin.b", gameId: "game-1")
        prefs.setUsesAltRepresentations(true, skinIdentifier: "skin.a", gameId: "game-1")
        let data = try #require(defaults.data(forKey: DeltaSkinPreferences.gameAltRepresentationsKey))
        let stored = try JSONDecoder().decode([String: [String]].self, from: data)
        #expect(stored == ["game-1": ["skin.a", "skin.b"]])
        // The skin picks' keys are untouched.
        #expect(defaults.data(forKey: DeltaSkinPreferences.gamePreferencesKey) == nil)
    }

    @Test("The selection manager toggles, persists under the first key and posts a notification")
    func managerToggle() async {
        defer { cleanup() }
        let prefs = DeltaSkinPreferences(defaults: defaults)
        let manager = DeltaSkinSelectionManager(preferences: prefs)

        var posted: [Bool] = []
        let token = NotificationCenter.default.addObserver(
            forName: DeltaSkinSelectionManager.altRepresentationsChangedNotification, object: nil, queue: nil
        ) { note in
            if note.userInfo?["skinIdentifier"] as? String == "skin.toggle",
               let value = note.userInfo?["usesAltRepresentations"] as? Bool {
                posted.append(value)
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let keys = ["game-1", "", "md5"]
        #expect(manager.toggleAltRepresentations(skinIdentifier: "skin.toggle", gameIds: keys))
        #expect(manager.usesAltRepresentations(skinIdentifier: "skin.toggle", gameIds: keys))
        #expect(prefs.gameAltRepresentations["game-1"] == ["skin.toggle"])

        #expect(!manager.toggleAltRepresentations(skinIdentifier: "skin.toggle", gameIds: keys))
        #expect(!manager.usesAltRepresentations(skinIdentifier: "skin.toggle", gameIds: keys))
        #expect(posted == [true, false])

        // No game key: nothing to persist under.
        #expect(!manager.toggleAltRepresentations(skinIdentifier: "skin.toggle", gameIds: [""]))
    }
}
