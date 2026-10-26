import Foundation
import SkinCatalogKit
import SkinKitCore
import Testing
@testable import SkinKitManager

/// Install → list → select → delete, end to end, for each app's configuration: the app's store
/// policy and installed-record storage, with the skin library being SkinKitManager's
/// `DeltaSkinManager` and selection `DeltaSkinSelectionManager`, on fixture skins in temp
/// directories and an isolated `UserDefaults` suite.
///
/// The install step is what an app writes (iFly's `SkinImporter`, iCube's `SkinLibrary`); here it
/// is the smallest one that exercises the shared parts: retarget by the policy, spot an
/// already-loaded skin by its predicted identifier, import through the manager.
@Suite("Install, list, select, delete round trip")
@MainActor
final class SkinStoreRoundTripTests {
    private let scratch: URL
    private let defaults: UserDefaults
    private let cleanupDefaults: () -> Void
    private let manager: DeltaSkinManager
    private let selection: DeltaSkinSelectionManager

    init() throws {
        scratch = try TestSupport.makeScratch("SkinStoreRoundTripTests")
        (defaults, cleanupDefaults) = TestSupport.makeDefaults()
        selection = DeltaSkinSelectionManager(preferences: DeltaSkinPreferences(defaults: defaults))
        manager = DeltaSkinManager(
            configuration: DeltaSkinManager.Configuration(
                skinsDirectory: scratch.appendingPathComponent("Skins", isDirectory: true),
                bundledSkinLocations: { [] }
            ),
            selectionManager: selection
        )
        manager.overrideRegistry = SkinSystemOverrideRegistry()
    }

    deinit {
        try? FileManager.default.removeItem(at: scratch)
        cleanupDefaults()
    }

    /// The identifier suffix this test's stand-in retargeter adds (the apps use their own rules).
    private func suffixed(_ identifier: String, target: String) -> String {
        identifier.hasSuffix(".\(target)") ? identifier : "\(identifier).\(target)"
    }

    /// What an app's install step does, using SkinKit's parts.
    private func installStep(policy: SkinStorePolicy, accepted: Set<DeltaSkinGameType>) -> SkinStoreInstaller.InstallStep {
        { [manager, scratch] file, section in
            let incoming = try DeltaSkin(fileURL: file)
            let target = policy.retarget(for: section, skinGameType: incoming.gameType, acceptedGameTypes: accepted)
            let predicted = policy.installedIdentifier(for: incoming.identifier, target: target) { id, target in
                self.suffixed(id, target: target)
            }

            let loaded = try await manager.availableSkins(forceRescan: true).map(\.identifier)
            if loaded.contains(predicted) {
                return .alreadyInstalled(identifier: predicted)
            }

            let toImport = try target.map { try TestSupport.retargetedCopy(of: file, target: $0, in: scratch) } ?? file
            try await manager.importSkin(from: toImport)
            let installed = try await manager.availableSkins().first { $0.fileURL.lastPathComponent == file.lastPathComponent }
            guard let installed else {
                throw SkinStoreInstaller.InstallError.unreadableAfterInstall(file.lastPathComponent)
            }
            return .installed(identifier: installed.identifier)
        }
    }

    private func archive(_ fixture: String, as name: String) throws -> URL {
        let directory = scratch.appendingPathComponent("downloads-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try TestSupport.zippedFixture(fixture, into: directory, as: name)
    }

    // MARK: - iFly

    @Test("iFly: install an arcade skin, list it, select it per system and game, delete it, install it again")
    func iFlyRoundTrip() async throws {
        let preset = StorePreset.iFly
        let (record, reopen, cleanup) = try preset.makeRecord()
        defer { cleanup() }
        let installer = SkinStoreInstaller(
            policy: preset.policy,
            downloader: FakeDownloader(source: try archive("GBA-Test", as: "download.manicskin")),
            record: record, appName: "iFly",
            installStep: installStep(policy: preset.policy, accepted: [.dreamcast])
        )
        let entry = try preset.installableEntry(id: "17b481d711267028")

        // install
        await installer.install(entry)
        #expect(installer.state(for: entry) == .installed)
        let skinId = "com.provenance.test.gba.arcade"
        #expect(reopen().load() == ["17b481d711267028": skinId], "arcade shelf retargets, so the identifier carries the suffix")

        // list
        let listed = try await manager.availableSkins(forceRescan: true)
        #expect(listed.map(\.identifier) == [skinId])
        #expect(listed.first?.fileURL.lastPathComponent == "17b481d711267028.manicskin")

        // select: per system (both orientations) and per game (by id, md5 and crc keys)
        let system = SkinSystemID("com.provenance.mame")
        selection.setSkin(skinId, for: system, orientation: .portrait, scope: .system)
        selection.setSkin(skinId, for: system, gameId: "md5-abc", orientation: .landscape, scope: .game)
        #expect(selection.effectiveSkinIdentifier(for: system, orientation: .portrait) == skinId)
        #expect(selection.effectiveSkinIdentifier(for: system, orientation: .landscape) == nil)
        #expect(selection.effectiveSkinIdentifier(for: system, gameIds: ["game-id", "md5-abc", "crc-1"], orientation: .landscape) == skinId)
        #expect(try await manager.skin(withIdentifier: skinId)?.name == listed.first?.name)

        // delete, then the store notices and offers it again
        try await manager.deleteSkin(skinId)
        #expect(try await manager.availableSkins().isEmpty)
        let remaining = try await manager.availableSkins().map(\.identifier)
        installer.reconcileInstalled(with: Set(remaining))
        #expect(installer.state(for: entry) == .idle)
        #expect(reopen().load().isEmpty)

        // and a reinstall works
        await installer.install(entry)
        #expect(installer.state(for: entry) == .installed)
        #expect(try await manager.availableSkins().map(\.identifier) == [skinId])
    }

    @Test("iFly: a skin whose predicted identifier is already loaded is not copied again")
    func iFlyAlreadyInstalled() async throws {
        let preset = StorePreset.iFly
        let (record, _, cleanup) = try preset.makeRecord()
        defer { cleanup() }
        let installer = SkinStoreInstaller(
            policy: preset.policy,
            downloader: FakeDownloader(source: try archive("GBA-Test", as: "download.manicskin")),
            record: record, appName: "iFly",
            installStep: installStep(policy: preset.policy, accepted: [.dreamcast])
        )
        let first = try preset.installableEntry(id: "aaaaaaaaaaaaaaaa", name: "First")
        let second = try preset.installableEntry(id: "bbbbbbbbbbbbbbbb", name: "Second")

        await installer.install(first)
        await installer.install(second)

        #expect(installer.state(for: second) == .installed)
        #expect(try await manager.availableSkins(forceRescan: true).count == 1, "the second entry is the same skin")
        #expect(record.load() == ["aaaaaaaaaaaaaaaa": "com.provenance.test.gba.arcade", "bbbbbbbbbbbbbbbb": "com.provenance.test.gba.arcade"])
    }

    @Test("iFly: a Dreamcast-shelf skin of an accepted type installs as-is; an unaccepted type is retargeted")
    func iFlyDreamcastShelf() async throws {
        let preset = StorePreset.iFly
        let (record, _, cleanup) = try preset.makeRecord()
        defer { cleanup() }
        let entry = try TestSupport.entry(id: "dc01", systems: ["dreamcast"], url: "https://example.com/dc01.manicskin")

        // GBA is not a type iFly shows, so the Dreamcast shelf retargets it.
        let retargeting = SkinStoreInstaller(
            policy: preset.policy, downloader: FakeDownloader(source: try archive("GBA-Test", as: "x.manicskin")),
            record: record, installStep: installStep(policy: preset.policy, accepted: [.dreamcast])
        )
        await retargeting.install(entry)
        #expect(record.load()["dc01"] == "com.provenance.test.gba.dreamcast")

        // If the app accepted GBA, the same skin would install untouched.
        let (record2, _, cleanup2) = try preset.makeRecord()
        defer { cleanup2() }
        try await manager.deleteSkin("com.provenance.test.gba.dreamcast")
        let asIs = SkinStoreInstaller(
            policy: preset.policy, downloader: FakeDownloader(source: try archive("GBA-Test", as: "x.manicskin")),
            record: record2, installStep: installStep(policy: preset.policy, accepted: [.dreamcast, .gba])
        )
        await asIs.install(entry)
        #expect(record2.load()["dc01"] == "com.provenance.test.gba")
    }

    // MARK: - iCube

    @Test("iCube: install a GameCube-shelf skin, list it, select it, delete it, install it again")
    func iCubeRoundTrip() async throws {
        let preset = StorePreset.iCube
        let (record, reopen, cleanup) = try preset.makeRecord()
        defer { cleanup() }
        let installer = SkinStoreInstaller(
            policy: preset.policy,
            downloader: FakeDownloader(source: try archive("GameCube-Test", as: "download.manicskin")),
            record: record, appName: "iCube",
            installStep: installStep(policy: preset.policy, accepted: [.gamecube])
        )
        let entry = try preset.installableEntry(id: "6f1c7b2a9d3e4f50", name: "GameCube Pocket")

        await installer.install(entry)
        #expect(installer.state(for: entry) == .installed)
        // The GameCube shelf installs as-is: no retarget, so the identifier is the skin's own.
        #expect(reopen().load() == ["6f1c7b2a9d3e4f50": "com.provenance.test.gamecube"])

        let listed = try await manager.availableSkins(forceRescan: true)
        #expect(listed.map(\.identifier) == ["com.provenance.test.gamecube"])
        #expect(listed.map(\.gameType) == [.gamecube])

        let system = SkinSystemID("com.provenance.gamecube")
        selection.setSkin("com.provenance.test.gamecube", for: system, orientation: .portrait, scope: .system)
        #expect(selection.hasExplicitPackagedSkinSelection(for: system, gameIds: ["any-game"]))
        #expect(selection.effectiveSkinIdentifier(for: system, gameId: "any-game", orientation: .portrait) == "com.provenance.test.gamecube")

        try await manager.deleteSkin("com.provenance.test.gamecube")
        installer.reconcileInstalled(with: Set(try await manager.availableSkins().map(\.identifier)))
        #expect(installer.state(for: entry) == .idle)
        #expect(reopen().load().isEmpty)

        await installer.install(entry)
        #expect(installer.state(for: entry) == .installed)
    }

    @Test("iCube: the N64 shelf rewrites to the GameCube target")
    func iCubeNintendo64Shelf() async throws {
        let preset = StorePreset.iCube
        let (record, reopen, cleanup) = try preset.makeRecord()
        defer { cleanup() }
        let installer = SkinStoreInstaller(
            policy: preset.policy,
            downloader: FakeDownloader(source: try archive("N64-Test", as: "download.manicskin")),
            record: record, appName: "iCube",
            installStep: installStep(policy: preset.policy, accepted: [.gamecube])
        )
        let n64 = try TestSupport.entry(id: "n64pack", systems: ["n64"], url: "https://example.com/n64pack.manicskin")

        await installer.install(n64)

        #expect(installer.state(for: n64) == .installed)
        #expect(reopen().load() == ["n64pack": "com.provenance.test.n64.gamecube"])
        #expect(try await manager.availableSkins(forceRescan: true).map(\.identifier) == ["com.provenance.test.n64.gamecube"])
    }

    @Test("iCube: a gameTypeIdentifier alone places an entry on the GameCube shelf")
    func iCubeGameTypePlacement() async throws {
        let preset = StorePreset.iCube
        let entry = try TestSupport.entry(
            id: "g1", systems: [], url: "https://example.com/g1.manicskin", gameTypeIdentifier: "public.aoshuang.game.ngc"
        )
        #expect(preset.policy.section(for: entry) == .gameCube)
    }

    // MARK: - Provenance (no store policy; the catalog detail view's flow)

    @Test("Provenance: catalog install, list, per-game select by md5, delete (sidecar removed)")
    func provenanceRoundTrip() async throws {
        let entry = try TestSupport.entry(
            id: "com.provenance.test.snes", name: "Backbone One — SNES", systems: ["snes"],
            url: "https://example.com/download"
        )
        let download = scratch.appendingPathComponent(entry.preferredLocalDownloadFileName())
        try FileManager.default.copyItem(at: TestSupport.fixtureURL("Backbone-SNES"), to: download)

        let installed = try await manager.installCatalogSkin(from: download, entry: entry)
        let skinId = "com.provenance.defaultskins.backbone.snes"
        #expect(installed?.identifier == skinId)
        #expect(try await manager.availableSkins().map(\.identifier) == [skinId])
        let sidecar = SkinSystemOverrideRegistry.sidecarURL(for: try #require(installed?.fileURL))
        #expect(FileManager.default.fileExists(atPath: sidecar.path))

        let system = SkinSystemID("com.provenance.snes")
        selection.setSkin(skinId, for: system, gameId: "md5-of-a-game", orientation: .portrait, scope: .game)
        #expect(selection.effectiveSkinIdentifier(for: system, gameIds: ["id", "md5-of-a-game"], orientation: .portrait) == skinId)
        #expect(selection.effectiveSkinIdentifier(for: system, gameIds: ["another-game"], orientation: .portrait) == nil)

        try await manager.deleteSkin(skinId)
        #expect(try await manager.availableSkins().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: sidecar.path))
    }
}
