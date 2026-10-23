import Foundation
import Testing
import ZIPFoundation
@testable import SkinKitCore

/// Loads fixture skins (a directory package and a zipped archive) through `DeltaSkin(fileURL:)`
/// and checks trait resolution and asset lookup. New tests: Provenance's tests build skins from
/// inline JSON, and none of them load a zip archive.
@Suite("DeltaSkin loading")
struct DeltaSkinLoadingTests {

    static func fixtureURL(_ name: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: "deltaskin", subdirectory: "Fixtures"))
    }

    /// Zips a fixture directory into a temporary `.deltaskin` archive, with files at the archive root.
    static func zippedFixture(_ name: String) throws -> URL {
        let source = try fixtureURL(name)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkinKitCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let archiveURL = tmp.appendingPathComponent("\(name).deltaskin")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        let files = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        for file in files {
            try archive.addEntry(with: file.lastPathComponent, relativeTo: source)
        }
        return archiveURL
    }

    @Test("Every fixture skin decodes", arguments: [
        ("GBA-Test", "com.provenance.test.gba", DeltaSkinGameType.gba),
        ("Genesis-Test", "com.provenance.test.genesis", .genesis),
        ("N64-Test", "com.provenance.test.n64", .n64),
        ("SNES-Test", "com.provenance.test.snes", .snes),
        ("Backbone-GBA", "com.provenance.defaultskins.backbone.gba", .gba),
    ])
    func fixtureDecodes(name: String, identifier: String, gameType: DeltaSkinGameType) throws {
        let skin = try DeltaSkin(fileURL: Self.fixtureURL(name))
        #expect(skin.identifier == identifier)
        #expect(skin.gameType == gameType)
    }

    @Test("Trait resolution follows the declared representations")
    func traitResolution() throws {
        let skin = try DeltaSkin(fileURL: Self.fixtureURL("GBA-Test"))
        let iphonePortrait = DeltaSkinTraits(device: .iphone, displayType: .standard, orientation: .portrait)
        let tv = DeltaSkinTraits(device: .tv, displayType: .standard, orientation: .landscape)
        #expect(skin.supports(iphonePortrait))
        #expect(!skin.supports(tv))
        #expect(skin.representation(for: tv) == nil)
        #expect(skin.mappingSize(for: iphonePortrait) != nil)
    }

    /// A minimal dual-screen skin that only declares `iphone/edgeToEdge/landscape`.
    /// (DS-Test.deltaskin cannot be loaded from disk: its info.json has `//` comments, and
    /// `DeltaSkin.init(fileURL:)` parses the raw file before sanitizing it. That is how Provenance
    /// behaves today; DS-Test is covered at the `DeltaSkin.Info` level in DeltaSkinDecodingTests.)
    static func writeEdgeOnlyDualScreenSkin() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkinKitCoreTests-\(UUID().uuidString).deltaskin", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = """
        {
          "name": "Edge-only DS", "identifier": "com.example.edge.ds",
          "gameTypeIdentifier": "com.rileytestut.delta.game.ds",
          "representations": { "iphone": { "edgeToEdge": { "landscape": {
            "assets": { "resizable": "skin.pdf" },
            "mappingSize": { "width": 852, "height": 393 },
            "screens": [
              { "inputFrame": { "x": 0, "y": 0, "width": 256, "height": 192 },
                "outputFrame": { "x": 100, "y": 10, "width": 300, "height": 225 } },
              { "inputFrame": { "x": 0, "y": 192, "width": 256, "height": 192 },
                "outputFrame": { "x": 450, "y": 10, "width": 300, "height": 225 } }
            ],
            "items": []
          } } } }
        }
        """
        try Data(json.utf8).write(to: dir.appendingPathComponent("info.json"))
        return dir
    }

    @Test("edgeToEdge falls back to standard, and standard to edgeToEdge")
    func displayTypeFallback() throws {
        let standardOnly = try DeltaSkin(fileURL: Self.fixtureURL("Genesis-Test"))
        #expect(standardOnly.supports(DeltaSkinTraits(device: .iphone, displayType: .edgeToEdge, orientation: .landscape)))

        let url = try Self.writeEdgeOnlyDualScreenSkin()
        defer { try? FileManager.default.removeItem(at: url) }
        let edgeOnly = try DeltaSkin(fileURL: url)
        #expect(edgeOnly.supports(DeltaSkinTraits(device: .iphone, displayType: .standard, orientation: .landscape)))
        #expect(!edgeOnly.supports(DeltaSkinTraits(device: .iphone, displayType: .splitView, orientation: .landscape)))
    }

    @Test("Dual-screen skin exposes both screens as one group")
    func dualScreenGroup() throws {
        let url = try Self.writeEdgeOnlyDualScreenSkin()
        defer { try? FileManager.default.removeItem(at: url) }
        let skin = try DeltaSkin(fileURL: url)
        let traits = DeltaSkinTraits(device: .iphone, displayType: .edgeToEdge, orientation: .landscape)
        let screens = try #require(skin.screens(for: traits))
        #expect(screens.count == 2)
        let groups = try #require(skin.screenGroups(for: traits))
        #expect(groups.count == 1)
        #expect(groups[0].screens.count == 2)
    }

    @Test("Asset data loads from a directory skin")
    func directoryAssetData() throws {
        let skin = try DeltaSkin(fileURL: Self.fixtureURL("Backbone-GBA"))
        let data = try skin.loadAssetData("controller.svg")
        #expect(!data.isEmpty)
        #expect(throws: DeltaSkinError.self) { _ = try skin.loadAssetData("nope.svg") }
    }

    @Test("A zipped .deltaskin loads the same as its directory")
    func archiveLoads() throws {
        let url = try Self.zippedFixture("Backbone-GBA")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let skin = try DeltaSkin(fileURL: url)
        let directory = try DeltaSkin(fileURL: Self.fixtureURL("Backbone-GBA"))
        #expect(skin.identifier == directory.identifier)

        let traits = DeltaSkinTraits(device: .iphone, displayType: .standard, orientation: .landscape)
        #expect(skin.buttons(for: traits)?.count == directory.buttons(for: traits)?.count)
        #expect(skin.mappingSize(for: traits) == directory.mappingSize(for: traits))
        #expect(try skin.loadAssetData("controller.svg") == directory.loadAssetData("controller.svg"))
    }

    @Test("Missing or malformed skins throw the matching error")
    func loadErrors() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkinKitCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let emptyDir = tmp.appendingPathComponent("empty.deltaskin", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        #expect(throws: DeltaSkinError.missingInfoFile) { _ = try DeltaSkin(fileURL: emptyDir) }

        let badDir = tmp.appendingPathComponent("bad.deltaskin", isDirectory: true)
        try FileManager.default.createDirectory(at: badDir, withIntermediateDirectories: true)
        try Data("[1, 2]".utf8).write(to: badDir.appendingPathComponent("info.json"))
        #expect(throws: DeltaSkinError.invalidInfoFile) { _ = try DeltaSkin(fileURL: badDir) }

        let notAZip = tmp.appendingPathComponent("notzip.deltaskin")
        try Data("not a zip".utf8).write(to: notAZip)
        #expect(throws: DeltaSkinError.invalidArchive) { _ = try DeltaSkin(fileURL: notAZip) }
    }
}

@Suite("Archive.entry(matchingAssetNamed:)")
struct ArchiveAssetLookupTests {

    private func makeArchive(entries: [String]) throws -> (Archive, URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkinKitCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let archive = try Archive(url: tmp.appendingPathComponent("a.zip"), accessMode: .create)
        for path in entries {
            let data = Data(path.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        return (archive, tmp)
    }

    @Test("Exact path wins")
    func exact() throws {
        let (archive, tmp) = try makeArchive(entries: ["art/Pad.png", "Pad.png"])
        defer { try? FileManager.default.removeItem(at: tmp) }
        #expect(archive.entry(matchingAssetNamed: "Pad.png")?.path == "Pad.png")
    }

    @Test("Case-insensitive match on the last path component, in any folder")
    func caseInsensitiveFilename() throws {
        let (archive, tmp) = try makeArchive(entries: ["info.json", "assets/IPHONE-Portrait.PNG"])
        defer { try? FileManager.default.removeItem(at: tmp) }
        #expect(archive.entry(matchingAssetNamed: "iphone-portrait.png")?.path == "assets/IPHONE-Portrait.PNG")
    }

    @Test("A missing extension falls back to the same stem as pdf, png or svg")
    func stemFallback() throws {
        let (archive, tmp) = try makeArchive(entries: ["info.json", "controller.pdf"])
        defer { try? FileManager.default.removeItem(at: tmp) }
        #expect(archive.entry(matchingAssetNamed: "controller.png")?.path == "controller.pdf")
        #expect(archive.entry(matchingAssetNamed: "other.png") == nil)
    }

    @Test("Empty names match nothing")
    func empty() throws {
        let (archive, tmp) = try makeArchive(entries: ["info.json"])
        defer { try? FileManager.default.removeItem(at: tmp) }
        #expect(archive.entry(matchingAssetNamed: "") == nil)
    }
}

@Suite("DeltaSkin theme and case-companion hooks")
struct DeltaSkinHooksTests {

    @Test("Theme selection round-trips through the same UserDefaults key Provenance used")
    func themeSelection() {
        let id = "com.example.themetest.\(UUID().uuidString)"
        defer { DeltaSkinThemeSelection.setSelectedThemeId(nil, for: id) }

        #expect(DeltaSkinThemeSelection.selectedThemeId(for: id) == nil)
        DeltaSkinThemeSelection.setSelectedThemeId("neon", for: id)
        #expect(DeltaSkinThemeSelection.selectedThemeId(for: id) == "neon")
        #expect(UserDefaults.standard.string(forKey: "com.provenance.deltaskin.theme." + id) == "neon")
        DeltaSkinThemeSelection.setSelectedThemeId(nil, for: id)
        #expect(DeltaSkinThemeSelection.selectedThemeId(for: id) == nil)
    }

    @Test("Native resolution registry loads from the bundled JSON")
    func nativeResolution() {
        #expect(DeltaSkinNativeResolution.size(for: .gba) == CGSize(width: 240, height: 160))
        #expect(DeltaSkinNativeResolution.aspectRatio(for: .nes) > 0)
    }

    @Test("Edge insets and frames keep the system Codable layout on every platform")
    func systemCodableLayout() throws {
        let insets = try JSONEncoder().encode(DeltaSkinEdgeInsets(top: 1, left: 2, bottom: 3, right: 4))
        #expect(String(decoding: insets, as: UTF8.self) == "[1,2,3,4]")
        let decoded = try JSONDecoder().decode(DeltaSkinEdgeInsets.self, from: insets)
        #expect(decoded == DeltaSkinEdgeInsets(top: 1, left: 2, bottom: 3, right: 4))

        let rect = try JSONEncoder().encode(CGRect(x: 1, y: 2, width: 3, height: 4))
        #expect(String(decoding: rect, as: UTF8.self) == "[[1,2],[3,4]]")
    }
}
