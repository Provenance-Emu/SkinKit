//
//  SkinSystemOverrideRegistryTests.swift
//
//  Ported from Provenance's PVUIBaseTests. Validates the catalog-override registry that backs the
//  SG-1000 catalog install fix: sidecar IO, normalization, batch lookups and removal hygiene. The
//  catalog fallback is injected here, so the tests never touch the network.
//

import Foundation
import SkinCatalogKit
import SkinKitCore
import Testing
@testable import SkinKitManager

@Suite("SkinSystemOverrideRegistry")
struct SkinSystemOverrideRegistryTests {

    // MARK: - Test Helpers

    /// Creates a fresh temporary directory we can drop sidecars and fake skins into.
    private func makeTempDirectory() throws -> URL {
        try TestSupport.makeScratch("SkinSystemOverrideRegistryTests")
    }

    private func writeRawSidecar(_ json: String, next skinURL: URL) throws {
        let sidecarURL = SkinSystemOverrideRegistry.sidecarURL(for: skinURL)
        try json.data(using: .utf8)!.write(to: sidecarURL, options: .atomic)
    }

    // MARK: - Sidecar URL Naming

    @Test("Sidecar URL replaces .deltaskin with .skinmeta")
    func sidecarURLDerivation() {
        let skin = URL(fileURLWithPath: "/tmp/cool-skin.deltaskin")
        let sidecar = SkinSystemOverrideRegistry.sidecarURL(for: skin)
        #expect(sidecar.lastPathComponent == "cool-skin.skinmeta")
        #expect(sidecar.pathExtension == SkinSystemOverrideRegistry.sidecarPathExtension)
    }

    @Test("Sidecar URL is computed for .manicskin too")
    func sidecarURLManicSkin() {
        let skin = URL(fileURLWithPath: "/tmp/funky.manicskin")
        let sidecar = SkinSystemOverrideRegistry.sidecarURL(for: skin)
        #expect(sidecar.lastPathComponent == "funky.skinmeta")
    }

    // MARK: - Sidecar Parsing

    @Test("Reads a well-formed sidecar from disk")
    func reads_validSidecar() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let skinURL = dir.appendingPathComponent("sega.deltaskin")
        let json = """
        {
          "version": 1,
          "catalogEntryId": "27142316e1ac9953",
          "skinIdentifier": "com.failyx.sega.sg1000",
          "name": "SEGA SG-1000 Thumbstick",
          "systems": ["sg1000"],
          "gameTypeIdentifier": "com.rileytestut.delta.game.gba"
        }
        """
        try writeRawSidecar(json, next: skinURL)

        let sidecar = SkinSystemOverrideRegistry.shared.readSidecar(for: skinURL)
        #expect(sidecar?.catalogEntryId == "27142316e1ac9953")
        #expect(sidecar?.systems == ["sg1000"])
        #expect(sidecar?.gameTypeIdentifier == "com.rileytestut.delta.game.gba")
    }

    @Test("Returns nil when sidecar is missing")
    func reads_missingSidecar() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let skinURL = dir.appendingPathComponent("nope.deltaskin")
        #expect(SkinSystemOverrideRegistry.shared.readSidecar(for: skinURL) == nil)
    }

    @Test("Returns nil for malformed sidecar JSON")
    func reads_malformedSidecar() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let skinURL = dir.appendingPathComponent("bad.deltaskin")
        try writeRawSidecar("{ this is not json", next: skinURL)
        #expect(SkinSystemOverrideRegistry.shared.readSidecar(for: skinURL) == nil)
    }

    // MARK: - Write / Remove Lifecycle

    @Test("writeSidecar persists json and warms in-memory cache")
    func write_thenLookup() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let registry = SkinSystemOverrideRegistry()
        let skinURL = dir.appendingPathComponent("install-me.deltaskin")
        FileManager.default.createFile(atPath: skinURL.path, contents: nil)

        let entry = SkinCatalogEntry(
            id: "27142316e1ac9953",
            name: "SEGA SG-1000 Thumbstick",
            systems: ["SG1000"],
            downloadURL: URL(string: "https://example.com/x.deltaskin")!
        )
        try await registry.writeSidecar(for: skinURL, entry: entry, skinIdentifier: "com.failyx.sega.sg1000")

        /// Sidecar exists on disk with the .skinmeta extension.
        let sidecarURL = SkinSystemOverrideRegistry.sidecarURL(for: skinURL)
        #expect(FileManager.default.fileExists(atPath: sidecarURL.path))

        let stub = StubSkin(
            identifier: "com.failyx.sega.sg1000",
            name: "SEGA SG-1000 Thumbstick",
            gameType: .gba,
            fileURL: skinURL
        )
        let codes = await registry.systemCodes(for: stub)
        #expect(codes == ["sg1000"])
    }

    @Test("removeSidecar deletes the file and forgets cached overrides")
    func remove_clearsEverything() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let registry = SkinSystemOverrideRegistry()
        let skinURL = dir.appendingPathComponent("remove-me.deltaskin")
        FileManager.default.createFile(atPath: skinURL.path, contents: nil)

        let entry = SkinCatalogEntry(
            id: "abc",
            name: "Tester",
            systems: ["nes"],
            downloadURL: URL(string: "https://example.com/x.deltaskin")!
        )
        try await registry.writeSidecar(for: skinURL, entry: entry, skinIdentifier: "tester.id")

        let sidecarURL = SkinSystemOverrideRegistry.sidecarURL(for: skinURL)
        #expect(FileManager.default.fileExists(atPath: sidecarURL.path))

        await registry.removeSidecar(for: skinURL, skinIdentifier: "tester.id")
        #expect(!FileManager.default.fileExists(atPath: sidecarURL.path))

        let stub = StubSkin(identifier: "tester.id", name: "Tester", gameType: .nes, fileURL: skinURL)
        let codes = await registry.systemCodes(for: stub)
        /// No sidecar, no catalog entry that matches a temp-only file, so empty set.
        #expect(codes.isEmpty)
    }

    // MARK: - Normalization & Batch Lookup

    @Test("System codes are lowercased and legacy codes are dropped")
    func normalization_dropsLegacyAndCases() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let registry = SkinSystemOverrideRegistry()
        let skinURL = dir.appendingPathComponent("mixed.deltaskin")
        FileManager.default.createFile(atPath: skinURL.path, contents: nil)

        /// Hand-craft a sidecar with mixed-case + legacy codes to confirm the
        /// reader path normalizes consistently with the writer path.
        let raw = """
        {
          "version": 1,
          "catalogEntryId": "x",
          "skinIdentifier": "x",
          "name": "X",
          "systems": ["SG1000", "Unofficial", "  ", "MasterSystem"],
          "gameTypeIdentifier": null
        }
        """
        try writeRawSidecar(raw, next: skinURL)

        let stub = StubSkin(identifier: "x", name: "X", gameType: .sg1000, fileURL: skinURL)
        let codes = await registry.systemCodes(for: stub)
        #expect(codes == ["sg1000", "mastersystem"])
    }

    @Test("Batch lookup omits skins with no override")
    func batch_omitsEmpty() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let registry = SkinSystemOverrideRegistry()
        let withSidecarURL = dir.appendingPathComponent("with.deltaskin")
        let bareURL = dir.appendingPathComponent("bare.deltaskin")
        FileManager.default.createFile(atPath: withSidecarURL.path, contents: nil)
        FileManager.default.createFile(atPath: bareURL.path, contents: nil)

        let entry = SkinCatalogEntry(
            id: "id1",
            name: "Has Sidecar",
            systems: ["sg1000"],
            downloadURL: URL(string: "https://example.com/x.deltaskin")!
        )
        try await registry.writeSidecar(for: withSidecarURL, entry: entry, skinIdentifier: "skin.with")

        let withSkin = StubSkin(identifier: "skin.with", name: "Has Sidecar", gameType: .gba, fileURL: withSidecarURL)
        let bareSkin = StubSkin(identifier: "skin.bare", name: "Bare", gameType: .nes, fileURL: bareURL)

        let map = await registry.overrideCodesByIdentifier(for: [withSkin, bareSkin])
        #expect(map.keys.contains("skin.with"))
        #expect(!map.keys.contains("skin.bare"))
        #expect(map["skin.with"] == ["sg1000"])
    }

    // MARK: - Codable Round-trip

    @Test("SkinCatalogSidecar round-trips through JSON")
    func sidecarRoundTrip() throws {
        let original = SkinCatalogSidecar(
            catalogEntryId: "27142316e1ac9953",
            skinIdentifier: "com.failyx.sega.sg1000",
            name: "SEGA SG-1000 Thumbstick",
            systems: ["sg1000"],
            gameTypeIdentifier: "com.rileytestut.delta.game.gba"
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SkinCatalogSidecar.self, from: encoded)
        #expect(decoded == original)
    }

    // MARK: - New: the injected catalog fallback

    @Test("Falls back to the injected catalog when there is no sidecar")
    func catalogFallback() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let skinURL = dir.appendingPathComponent("from-catalog.deltaskin")

        let entry = SkinCatalogEntry(
            id: "from-catalog",
            name: "Catalog Skin",
            systems: ["SG1000", "Unknown"],
            downloadURL: URL(string: "https://example.com/from-catalog.deltaskin")!
        )
        let catalog = SkinCatalog(skins: [entry])
        let registry = SkinSystemOverrideRegistry(catalogProvider: { catalog })

        let stub = StubSkin(identifier: "wrong.id", name: "Different Name", gameType: .gba, fileURL: skinURL)
        #expect(await registry.systemCodes(for: stub) == ["sg1000"], "matched by file stem, placeholder code dropped")

        let unrelated = StubSkin(identifier: "other", name: "Other", gameType: .nes, fileURL: dir.appendingPathComponent("other.deltaskin"))
        #expect(await registry.systemCodes(for: unrelated).isEmpty)
    }

    // MARK: - Catalog index

    /// A catalog whose entries each match by a different rule, plus later entries that would match
    /// the same skins.
    private func rulesCatalog() throws -> SkinCatalog {
        SkinCatalog(skins: [
            try TestSupport.entry(id: "by.identifier", name: "One", systems: ["nes"], url: "https://example.com/a.deltaskin"),
            try TestSupport.entry(id: "catalog/id:two", name: "Two", systems: ["snes"], url: "https://example.com/b.deltaskin"),
            try TestSupport.entry(id: "three", name: "Three", systems: ["gba"], url: "https://example.com/Download-Stem.manicskin"),
            try TestSupport.entry(id: "four", name: "Named Skin", systems: ["jaguar"], url: "https://example.com/d.deltaskin"),
            try TestSupport.entry(id: "five", name: "named skin", systems: ["lynx"], url: "https://example.com/e.deltaskin")
        ])
    }

    private func stub(identifier: String = "none", name: String = "None", file: String = "none.deltaskin") -> StubSkin {
        StubSkin(identifier: identifier, name: name, gameType: .gba, fileURL: URL(fileURLWithPath: "/tmp/\(file)"))
    }

    @Test("The index matches by identifier, install name, download name and name, like matchingInstalledSkin")
    func indexMatchesEveryRule() throws {
        let catalog = try rulesCatalog()
        let index = CatalogMatchIndex(catalog: catalog, signature: CatalogMatchIndex.signature(of: catalog))
        let skins = [
            stub(identifier: "by.identifier"),
            stub(file: "catalog-id-two.deltaskin"),
            stub(file: "download-stem.manicskin"),
            stub(name: "NAMED SKIN"),
            stub()
        ]
        #expect(skins.map { index.systems(matching: $0) } == [["nes"], ["snes"], ["gba"], ["jaguar"], nil])
        for skin in skins {
            let expected = catalog.skins.first { matchingInstalledSkin(for: $0, in: [skin]) != nil }?.systems
            #expect(index.systems(matching: skin) == expected, "\(skin.identifier) / \(skin.fileURL.lastPathComponent) / \(skin.name)")
        }
    }

    @Test("When several entries match a skin, the earliest in the catalog wins")
    func indexPrefersEarliestEntry() throws {
        let catalog = try rulesCatalog()
        let index = CatalogMatchIndex(catalog: catalog, signature: CatalogMatchIndex.signature(of: catalog))
        // Identifier of entry four, file name of entry three: three comes first.
        let skin = stub(identifier: "four", file: "download-stem.deltaskin")
        #expect(index.systems(matching: skin) == ["gba"])
    }

    @Test("A batch asks for the catalog once, and not at all when every skin has a sidecar")
    func batchFetchesCatalogOnce() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let catalog = try rulesCatalog()
        let calls = CallCounter()
        let registry = SkinSystemOverrideRegistry(catalogProvider: {
            await calls.increment()
            return catalog
        })

        let withSidecar = StubSkin(identifier: "side", name: "Side", gameType: .gba,
                                   fileURL: dir.appendingPathComponent("side.deltaskin"))
        try writeRawSidecar(#"{"version": 1, "systems": ["sg1000"]}"#, next: withSidecar.fileURL)
        #expect(await registry.overrideCodesByIdentifier(for: [withSidecar]) == ["side": ["sg1000"]])
        #expect(await calls.count == 0)

        let unmatched = (0..<50).map { stub(identifier: "u\($0)", name: "U\($0)", file: "u\($0).deltaskin") }
        let codes = await registry.overrideCodesByIdentifier(for: unmatched + [withSidecar, stub(identifier: "by.identifier")])
        #expect(codes == ["side": ["sg1000"], "by.identifier": ["nes"]])
        #expect(await calls.count == 1)
    }

    @Test("A different catalog replaces the index")
    func newCatalogIsIndexedAgain() async throws {
        let catalogs = CatalogBox(try rulesCatalog())
        let registry = SkinSystemOverrideRegistry(catalogProvider: { await catalogs.value })
        let skin = stub(identifier: "added.later")
        #expect(await registry.systemCodes(for: skin).isEmpty)

        await catalogs.set(SkinCatalog(skins: [
            try TestSupport.entry(id: "added.later", name: "Later", systems: ["sms"], url: "https://example.com/l.deltaskin")
        ]))
        #expect(await registry.systemCodes(for: skin) == ["sms"])
    }

    @Test("A fresh registry has no catalog, so it never reaches for the network")
    func defaultRegistryHasNoCatalog() async {
        let registry = SkinSystemOverrideRegistry()
        let stub = StubSkin(identifier: "x", name: "X", gameType: .gba, fileURL: URL(fileURLWithPath: "/tmp/does-not-exist.deltaskin"))
        #expect(await registry.systemCodes(for: stub).isEmpty)
    }
}

private actor CallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

private actor CatalogBox {
    private(set) var value: SkinCatalog
    init(_ value: SkinCatalog) { self.value = value }
    func set(_ value: SkinCatalog) { self.value = value }
}
