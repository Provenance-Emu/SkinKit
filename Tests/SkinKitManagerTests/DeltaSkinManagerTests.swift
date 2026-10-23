import Foundation
import SkinCatalogKit
import SkinKitCore
import Testing
@testable import SkinKitManager

/// Import, scan, list, delete and the persisted path index, on fixture skins in a temp directory.
@Suite("DeltaSkinManager")
final class DeltaSkinManagerTests {
    private let scratch: URL
    private let skinsDirectory: URL
    private let defaults: UserDefaults
    private let cleanupDefaults: () -> Void

    init() throws {
        scratch = try TestSupport.makeScratch("DeltaSkinManagerTests")
        skinsDirectory = scratch.appendingPathComponent("DeltaSkins", isDirectory: true)
        (defaults, cleanupDefaults) = TestSupport.makeDefaults()
    }

    deinit {
        try? FileManager.default.removeItem(at: scratch)
        cleanupDefaults()
    }

    private func makeManager(bundled: [URL] = []) -> DeltaSkinManager {
        let manager = DeltaSkinManager(
            configuration: DeltaSkinManager.Configuration(skinsDirectory: skinsDirectory, bundledSkinLocations: { bundled }),
            selectionManager: DeltaSkinSelectionManager(preferences: DeltaSkinPreferences(defaults: defaults))
        )
        manager.overrideRegistry = SkinSystemOverrideRegistry()
        return manager
    }

    private func identifiers(_ manager: DeltaSkinManager) async throws -> [String] {
        try await manager.availableSkins(forceRescan: true).map(\.identifier).sorted()
    }

    // MARK: - Import / list / delete

    @Test("Imports a directory skin and a zipped skin, then lists both")
    func importsAndLists() async throws {
        let manager = makeManager()
        #expect(try await identifiers(manager) == [])

        try await manager.importSkin(from: TestSupport.fixtureURL("GBA-Test"))
        let zipped = try TestSupport.zippedFixture("Backbone-NES", into: scratch)
        try await manager.importSkin(from: zipped)

        #expect(try await identifiers(manager) == ["com.provenance.defaultskins.backbone.nes", "com.provenance.test.gba"])
        #expect(FileManager.default.fileExists(atPath: skinsDirectory.appendingPathComponent("GBA-Test.deltaskin").path))
        #expect(FileManager.default.fileExists(atPath: skinsDirectory.appendingPathComponent("Backbone-NES.deltaskin").path))
    }

    @Test("loadedSkins is up to date when importSkin returns")
    @MainActor
    func importPublishesLoadedSkins() async throws {
        let manager = makeManager()
        try await manager.importSkin(from: TestSupport.fixtureURL("N64-Test"))
        #expect(manager.loadedSkins.map(\.identifier) == ["com.provenance.test.n64"])
        #expect(manager.skinsAreLoaded)
    }

    @Test("A file that is not a skin is rejected and removed again")
    func rejectsGarbage() async throws {
        let manager = makeManager()
        let junk = scratch.appendingPathComponent("junk.deltaskin")
        try Data("not a zip".utf8).write(to: junk)

        await #expect(throws: (any Error).self) {
            try await manager.importSkin(from: junk)
        }
        #expect(!FileManager.default.fileExists(atPath: skinsDirectory.appendingPathComponent("junk.deltaskin").path))
        #expect(try await identifiers(manager) == [])
    }

    @Test("Importing the same file again replaces it")
    func reimportReplaces() async throws {
        let manager = makeManager()
        let fixture = try TestSupport.fixtureURL("GBA-Test")
        try await manager.importSkin(from: fixture)
        try await manager.importSkin(from: fixture)
        #expect(try await identifiers(manager) == ["com.provenance.test.gba"])
    }

    @Test("Two files with one identifier list once")
    func duplicateIdentifiersListOnce() async throws {
        let manager = makeManager()
        let fixture = try TestSupport.fixtureURL("GBA-Test")
        try FileManager.default.createDirectory(at: skinsDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: skinsDirectory.appendingPathComponent("A.deltaskin"))
        try FileManager.default.copyItem(at: fixture, to: skinsDirectory.appendingPathComponent("B.deltaskin"))
        #expect(try await manager.availableSkins(forceRescan: true).count == 1)
    }

    @Test("Deletes an imported skin, its sidecar, and its path index entry")
    func deletes() async throws {
        let manager = makeManager()
        try await manager.importSkin(from: TestSupport.fixtureURL("GBA-Test"))
        try await manager.importSkin(from: TestSupport.fixtureURL("N64-Test"))
        let installed = skinsDirectory.appendingPathComponent("GBA-Test.deltaskin")
        let sidecar = SkinSystemOverrideRegistry.sidecarURL(for: installed)
        try Data("{}".utf8).write(to: sidecar)

        try await manager.deleteSkin("com.provenance.test.gba")

        #expect(!FileManager.default.fileExists(atPath: installed.path))
        #expect(!FileManager.default.fileExists(atPath: sidecar.path))
        #expect(try await identifiers(manager) == ["com.provenance.test.n64"])
        let index = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: skinsDirectory.appendingPathComponent("skin_path_index.json")))
        #expect(Set(index.keys) == ["com.provenance.test.n64"])
    }

    @Test("Deleting an unknown skin throws notFound; a bundled skin throws deletionNotAllowed")
    func deleteErrors() async throws {
        let bundledSkin = try TestSupport.fixtureURL("Backbone-SNES")
        let manager = makeManager(bundled: [bundledSkin])
        _ = try await manager.availableSkins(forceRescan: true)

        do {
            try await manager.deleteSkin("com.example.missing")
            Issue.record("expected notFound")
        } catch let error as DeltaSkinError {
            #expect(error == .notFound)
        }
        do {
            try await manager.deleteSkin("com.provenance.defaultskins.backbone.snes")
            Issue.record("expected deletionNotAllowed")
        } catch let error as DeltaSkinError {
            #expect(error == .deletionNotAllowed)
        }
        #expect(FileManager.default.fileExists(atPath: bundledSkin.path))
    }

    @Test("isDeletable is true only under the skins directory")
    func isDeletable() async throws {
        let bundledSkin = try TestSupport.fixtureURL("Backbone-SNES")
        let manager = makeManager(bundled: [bundledSkin])
        try await manager.importSkin(from: TestSupport.fixtureURL("GBA-Test"))
        let skins = try await manager.availableSkins()
        let byId = Dictionary(uniqueKeysWithValues: skins.map { ($0.identifier, $0) })
        #expect(manager.isDeletable(try #require(byId["com.provenance.test.gba"])))
        #expect(!manager.isDeletable(try #require(byId["com.provenance.defaultskins.backbone.snes"])))
    }

    @Test("Bundled skins and the skins directory both list; reloadSkins picks up files added outside the manager")
    @MainActor
    func reloadsFromDisk() async throws {
        let manager = makeManager(bundled: [try TestSupport.fixtureURL("Backbone-SNES")])
        #expect(try await manager.availableSkins().map(\.identifier) == ["com.provenance.defaultskins.backbone.snes"])

        try FileManager.default.createDirectory(at: skinsDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: TestSupport.fixtureURL("N64-Test"), to: skinsDirectory.appendingPathComponent("N64-Test.deltaskin"))
        // Cached until a rescan is asked for.
        #expect(try await manager.availableSkins().count == 1)

        await manager.reloadSkins()
        #expect(manager.loadedSkins.map(\.identifier).sorted() == ["com.provenance.defaultskins.backbone.snes", "com.provenance.test.n64"])
    }

    @Test("loadSkin(from:) loads a skin without importing it")
    func loadSkinFromURL() async throws {
        let manager = makeManager()
        let skin = try await manager.loadSkin(from: TestSupport.fixtureURL("N64-Test"))
        #expect(skin.identifier == "com.provenance.test.n64")
        #expect(!FileManager.default.fileExists(atPath: skinsDirectory.path))
    }

    // MARK: - Scan configuration

    @Test("Provenance's scan reads .zip files in the directory, iFly's does not")
    func zipScanningFollowsTheConfiguration() async throws {
        try FileManager.default.createDirectory(at: skinsDirectory, withIntermediateDirectories: true)
        _ = try TestSupport.zippedFixture("GBA-Test", into: skinsDirectory, as: "renamed.zip")

        #expect(try await identifiers(makeManager()) == ["com.provenance.test.gba"])

        let iFly = DeltaSkinManager(
            configuration: DeltaSkinManager.Configuration(
                skinsDirectory: skinsDirectory,
                bundledSkinLocations: { [] },
                directoryScanExtensions: DeltaSkinManager.Configuration.defaultSkinExtensions
            ),
            selectionManager: DeltaSkinSelectionManager(preferences: DeltaSkinPreferences(defaults: defaults))
        )
        #expect(try await iFly.availableSkins(forceRescan: true).isEmpty)
    }

    @Test("The Provenance and iFly presets differ in folder name and extensions")
    func presets() {
        let documents = URL(fileURLWithPath: "/docs")
        let provenance = DeltaSkinManager.Configuration.provenance(documents: documents)
        #expect(provenance.skinsDirectory.path == "/docs/DeltaSkins")
        #expect(provenance.pathIndexFileName == "skin_path_index.json")
        #expect(provenance.directoryScanExtensions == ["deltaskin", "manicskin", "zip"])

        let iFly = DeltaSkinManager.Configuration.iFly(documents: documents)
        #expect(iFly.skinsDirectory.path == "/docs/Skins")
        #expect(iFly.directoryScanExtensions == ["deltaskin", "manicskin"])
    }

    // MARK: - Path index

    @Test("The path index is JSON {identifier: path}, written after a scan")
    func pathIndexIsWritten() async throws {
        let manager = makeManager()
        try await manager.importSkin(from: TestSupport.fixtureURL("GBA-Test"))

        let data = try Data(contentsOf: skinsDirectory.appendingPathComponent("skin_path_index.json"))
        let index = try JSONDecoder().decode([String: String].self, from: data)
        #expect(index["com.provenance.test.gba"]?.hasSuffix("/GBA-Test.deltaskin") == true)
    }

    @Test("skin(withIdentifier:) resolves through the persisted index without a scan")
    func lookupUsesTheIndex() async throws {
        // A skin outside every scan location can only be found through the index.
        let outside = try TestSupport.fixtureURL("N64-Test")
        try FileManager.default.createDirectory(at: skinsDirectory, withIntermediateDirectories: true)
        let index = ["com.provenance.test.n64": outside.path]
        try JSONEncoder().encode(index).write(to: skinsDirectory.appendingPathComponent("skin_path_index.json"))

        let manager = makeManager()
        let skin = try await manager.skin(withIdentifier: "com.provenance.test.n64")
        #expect(skin?.fileURL == outside)
    }

    @Test("A stale index entry is dropped and the lookup falls through to a scan")
    func staleIndexEntryIsDropped() async throws {
        try FileManager.default.createDirectory(at: skinsDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: TestSupport.fixtureURL("GBA-Test"), to: skinsDirectory.appendingPathComponent("GBA-Test.deltaskin"))
        let index = ["com.provenance.test.gba": "/nowhere/GBA-Test.deltaskin", "gone": "/nowhere/gone.deltaskin"]
        try JSONEncoder().encode(index).write(to: skinsDirectory.appendingPathComponent("skin_path_index.json"))

        let manager = makeManager()
        let skin = try await manager.skin(withIdentifier: "com.provenance.test.gba")
        #expect(skin?.fileURL.lastPathComponent == "GBA-Test.deltaskin")
        #expect(try await manager.skin(withIdentifier: "com.example.missing") == nil)
    }

    // MARK: - Selection pass-throughs

    @Test("Session and effective identifiers go through the selection manager")
    @MainActor
    func selectionPassThroughs() async throws {
        let manager = makeManager()
        let system = SkinSystemID("com.provenance.gba")

        manager.selectionManager.setSkin("com.example.system", for: system, orientation: .portrait, scope: .system)
        #expect(manager.effectiveSkinIdentifier(for: system, orientation: .portrait) == "com.example.system")
        #expect(manager.sessionSkinIdentifier(for: system, orientation: .portrait) == "com.example.system")

        manager.setSessionSkin("com.example.session", for: system, gameId: "game-1", orientation: .portrait)
        // setSessionSkin hops to the main actor; wait for it to land.
        for _ in 0..<500 where manager.selectionManager.getSessionSkin(for: system, gameId: "game-1", orientation: .portrait) == nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(manager.effectiveGameSkinIdentifier(for: system, gameId: "game-1", orientation: .portrait) == "com.example.session")
        #expect(manager.sessionSkinIdentifier(for: system, gameId: "game-1", orientation: .portrait) == "com.example.session")
        #expect(manager.effectiveGameSkinIdentifier(for: system, gameId: "game-2", orientation: .portrait) == "com.example.system")
    }
}

/// The `skins(for:)` family: Provenance's `DeltaSkinManager+SystemIdentifier`, in plain values.
@Suite("DeltaSkinManager queries")
final class DeltaSkinManagerQueryTests {
    private let scratch: URL
    private let skinsDirectory: URL
    private let defaults: UserDefaults
    private let cleanupDefaults: () -> Void

    init() throws {
        scratch = try TestSupport.makeScratch("DeltaSkinManagerQueryTests")
        skinsDirectory = scratch.appendingPathComponent("DeltaSkins", isDirectory: true)
        (defaults, cleanupDefaults) = TestSupport.makeDefaults()
    }

    deinit {
        try? FileManager.default.removeItem(at: scratch)
        cleanupDefaults()
    }

    private func makeManager(allowAutomatic: @escaping @Sendable (String) -> Bool = { _ in true }) async throws -> DeltaSkinManager {
        var configuration = DeltaSkinManager.Configuration(skinsDirectory: skinsDirectory, bundledSkinLocations: { [] })
        configuration.isAllowedInAutomaticSelection = allowAutomatic
        let manager = DeltaSkinManager(
            configuration: configuration,
            selectionManager: DeltaSkinSelectionManager(preferences: DeltaSkinPreferences(defaults: defaults))
        )
        manager.overrideRegistry = SkinSystemOverrideRegistry()
        for name in ["GBA-Test", "N64-Test", "Backbone-NES", "Backbone-SNES"] {
            try await manager.importSkin(from: TestSupport.fixtureURL(name))
        }
        return manager
    }

    @Test("skins(for:) matches the game type, and a catalog override can add a skin")
    func skinsForGameType() async throws {
        let manager = try await makeManager()
        #expect(try await manager.skins(for: .gba).map(\.identifier) == ["com.provenance.test.gba"])
        #expect(try await manager.skins(for: .sg1000, catalogSystemCodes: ["sg1000"]).isEmpty)

        // The GBA skin's catalog metadata says it is really an SG-1000 skin.
        let gbaFile = skinsDirectory.appendingPathComponent("GBA-Test.deltaskin")
        let entry = try TestSupport.entry(id: "sg", systems: ["sg1000"], url: "https://example.com/sg.deltaskin")
        try await manager.overrideRegistry.writeSidecar(for: gbaFile, entry: entry, skinIdentifier: "com.provenance.test.gba")

        #expect(try await manager.skins(for: .sg1000, catalogSystemCodes: ["sg1000"]).map(\.identifier) == ["com.provenance.test.gba"])
        #expect(try await manager.skins(for: .sg1000, catalogSystemCodes: ["mastersystem"]).isEmpty)
    }

    @Test("defaultSkin is the first by name, then identifier, that may be chosen automatically")
    func defaultSkinIsDeterministic() async throws {
        let manager = try await makeManager()
        let nes = try await manager.defaultSkin(for: .nes)
        #expect(nes?.identifier == "com.provenance.defaultskins.backbone.nes")
        #expect(try await manager.defaultSkin(for: .psx) == nil)

        let blocking = try await makeManager(allowAutomatic: { _ in false })
        #expect(try await blocking.defaultSkin(for: .nes) == nil)
    }

    @Test("selectedSkin follows the pick, and skinToUse falls back to the default")
    func selectedAndSkinToUse() async throws {
        let manager = try await makeManager()
        let system = SkinSystemID("com.provenance.snes")

        #expect(try await manager.selectedSkin(for: system, gameType: .snes) == nil)
        #expect(try await manager.skinToUse(for: system, gameType: .snes)?.identifier == "com.provenance.defaultskins.backbone.snes")

        await MainActor.run {
            manager.selectionManager.setSkin("com.provenance.test.gba", for: system, orientation: .portrait, scope: .system)
        }
        // The pick is a GBA skin, which is not a SNES skin, so it is not offered for SNES.
        #expect(try await manager.selectedSkin(for: system, gameType: .snes) == nil)

        await MainActor.run {
            manager.selectionManager.setSkin("com.provenance.defaultskins.backbone.snes", for: system, orientation: .portrait, scope: .system)
        }
        #expect(try await manager.selectedSkin(for: system, gameType: .snes)?.identifier == "com.provenance.defaultskins.backbone.snes")
    }

    @Test("A pick the app forbids auto-selecting is skipped")
    func forbiddenPickIsSkipped() async throws {
        let manager = try await makeManager(allowAutomatic: { $0 != "com.provenance.defaultskins.backbone.snes" })
        let system = SkinSystemID("com.provenance.snes")
        await MainActor.run {
            manager.selectionManager.setSkin("com.provenance.defaultskins.backbone.snes", for: system, orientation: .portrait, scope: .system)
        }
        #expect(try await manager.selectedSkin(for: system, gameType: .snes) == nil)
    }

    @Test("The string overload finds a default by Delta or Manic identifier")
    @MainActor
    func defaultSkinByIdentifierString() async throws {
        let manager = try await makeManager()
        await manager.reloadSkins()
        #expect(manager.defaultSkin(for: "com.rileytestut.delta.game.n64")?.identifier == "com.provenance.test.n64")
        #expect(manager.defaultSkin(for: "COM.RILEYTESTUT.DELTA.GAME.N64")?.identifier == "com.provenance.test.n64")
        #expect(manager.defaultSkin(for: "nope") == nil)
    }
}

/// The catalog install path from Provenance's detail view, minus the download and the view state.
@Suite("Catalog install")
final class CatalogInstallTests {
    private let scratch: URL
    private let defaults: UserDefaults
    private let cleanupDefaults: () -> Void

    init() throws {
        scratch = try TestSupport.makeScratch("CatalogInstallTests")
        (defaults, cleanupDefaults) = TestSupport.makeDefaults()
    }

    deinit {
        try? FileManager.default.removeItem(at: scratch)
        cleanupDefaults()
    }

    @Test("Imports the download and writes the .skinmeta sidecar next to it")
    func installsAndWritesSidecar() async throws {
        let manager = TestSupport.makeManager(skinsDirectory: scratch.appendingPathComponent("DeltaSkins"), defaults: defaults)
        let entry = try TestSupport.entry(
            id: "com.provenance.test.gba",
            name: "GBA Test Skin",
            systems: ["SG1000"],
            url: "https://github.com/x/y/releases/download/v1/download",
            gameTypeIdentifier: "com.rileytestut.delta.game.gba"
        )
        // The download is saved under the entry's preferred name, as Provenance does.
        let download = scratch.appendingPathComponent(entry.preferredLocalDownloadFileName())
        try FileManager.default.copyItem(at: TestSupport.fixtureURL("GBA-Test"), to: download)

        let skin = try await manager.installCatalogSkin(from: download, entry: entry)

        #expect(skin?.identifier == "com.provenance.test.gba")
        let installed = scratch.appendingPathComponent("DeltaSkins/com.provenance.test.gba.deltaskin")
        #expect(FileManager.default.fileExists(atPath: installed.path))
        let sidecar = try #require(manager.overrideRegistry.readSidecar(for: installed))
        #expect(sidecar.catalogEntryId == "com.provenance.test.gba")
        #expect(sidecar.skinIdentifier == "com.provenance.test.gba")
        #expect(sidecar.systems == ["sg1000"])
        #expect(sidecar.gameTypeIdentifier == "com.rileytestut.delta.game.gba")
    }

    @Test("An unreadable download throws and installs nothing")
    func badDownloadThrows() async throws {
        let manager = TestSupport.makeManager(skinsDirectory: scratch.appendingPathComponent("DeltaSkins"), defaults: defaults)
        let entry = try TestSupport.entry(id: "bad", systems: ["gba"], url: "https://example.com/bad.deltaskin")
        let download = scratch.appendingPathComponent(entry.preferredLocalDownloadFileName())
        try Data("html, not a skin".utf8).write(to: download)

        await #expect(throws: (any Error).self) {
            try await manager.installCatalogSkin(from: download, entry: entry)
        }
        #expect(try await manager.availableSkins(forceRescan: true).isEmpty)
    }
}
