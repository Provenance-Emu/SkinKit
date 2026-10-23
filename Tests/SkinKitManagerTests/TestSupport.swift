import Foundation
import SkinCatalogKit
import SkinKitCore
import Testing
import ZIPFoundation
@testable import SkinKitManager

/// Shared helpers: fixture skins, scratch directories, isolated defaults, a fake downloader.
enum TestSupport {
    /// The fixture skins this target ships (copied from SkinKitCoreTests/Fixtures).
    static func fixtureURL(_ name: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: "deltaskin", subdirectory: "Fixtures"))
    }

    /// `(fixture name, skin identifier, game type)` for every fixture.
    static let fixtures: [(name: String, identifier: String, gameType: DeltaSkinGameType)] = [
        ("GBA-Test", "com.provenance.test.gba", .gba),
        ("N64-Test", "com.provenance.test.n64", .n64),
        ("Backbone-NES", "com.provenance.defaultskins.backbone.nes", .nes),
        ("Backbone-SNES", "com.provenance.defaultskins.backbone.snes", .snes),
    ]

    /// A fresh scratch directory, removed by the caller.
    static func makeScratch(_ label: String = "SkinKitManagerTests") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A `UserDefaults` suite nothing else writes to. Call `cleanup` when done.
    static func makeDefaults() -> (defaults: UserDefaults, cleanup: () -> Void) {
        let suite = "SkinKitManagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    /// Zips a fixture directory into `<directory>/<name>.deltaskin` with the files at the archive root.
    static func zippedFixture(_ name: String, into directory: URL, as fileName: String? = nil) throws -> URL {
        let source = try fixtureURL(name)
        let archiveURL = directory.appendingPathComponent(fileName ?? "\(name).deltaskin")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        for file in try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            try archive.addEntry(with: file.lastPathComponent, relativeTo: source)
        }
        return archiveURL
    }

    /// A retargeted copy of a skin archive, the way an app's importer does it: same files, but the
    /// `identifier` in `info.json` gets `.<target>` added (the apps' own rules are app code; this
    /// stands in for them). Returns the new archive, named like `archive`.
    static func retargetedCopy(of archive: URL, target: String, in directory: URL) throws -> URL {
        let fm = FileManager.default
        let extractDir = directory.appendingPathComponent("extract-\(UUID().uuidString)", isDirectory: true)
        try fm.unzipItem(at: archive, to: extractDir)
        let infoURL = extractDir.appendingPathComponent("info.json")
        var info = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: infoURL)) as? [String: Any])
        info["identifier"] = "\(info["identifier"] as? String ?? "imported.skin").\(target)"
        try JSONSerialization.data(withJSONObject: info).write(to: infoURL)

        let output = directory.appendingPathComponent("retargeted-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(archive.lastPathComponent)
        try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        let zip = try Archive(url: output, accessMode: .create)
        for file in try fm.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil) {
            try zip.addEntry(with: file.lastPathComponent, relativeTo: extractDir)
        }
        try? fm.removeItem(at: extractDir)
        return output
    }

    /// A manager that scans only `skinsDirectory` (no bundled skins), with its own selection state.
    static func makeManager(
        skinsDirectory: URL,
        defaults: UserDefaults,
        registry: SkinSystemOverrideRegistry = SkinSystemOverrideRegistry()
    ) -> DeltaSkinManager {
        let manager = DeltaSkinManager(
            configuration: DeltaSkinManager.Configuration(skinsDirectory: skinsDirectory, bundledSkinLocations: { [] }),
            selectionManager: DeltaSkinSelectionManager(preferences: DeltaSkinPreferences(defaults: defaults))
        )
        manager.overrideRegistry = registry
        return manager
    }

    /// A catalog entry with the fields the store reads.
    static func entry(
        id: String,
        name: String = "Test Skin",
        systems: [String],
        url: String,
        gameTypeIdentifier: String? = nil
    ) throws -> SkinCatalogEntry {
        SkinCatalogEntry(
            id: id,
            name: name,
            systems: systems,
            gameTypeIdentifier: gameTypeIdentifier,
            downloadURL: try #require(URL(string: url))
        )
    }
}

/// Writes a file for the installer to pick up: a fixture archive when `source` is set, or a
/// placeholder. Reports scripted progress and optionally fails. Like the apps' test doubles, it
/// creates the parent folder first (the installer does not).
struct FakeDownloader: SkinStoreDownloading {
    var error: Error?
    var source: URL?
    var progressSteps: [Double] = [0.25, 0.5, 1]

    func download(
        from _: URL,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        for step in progressSteps {
            progress(step)
        }
        if let error {
            throw error
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let source {
            try FileManager.default.copyItem(at: source, to: destination)
        } else {
            try Data("skin".utf8).write(to: destination)
        }
    }
}

/// A `DeltaSkinProtocol` that never touches disk, for tests that only need identity, name and path.
struct StubSkin: DeltaSkinProtocol {
    let identifier: String
    let name: String
    let gameType: DeltaSkinGameType
    let fileURL: URL
    /// Which traits `supports(_:)` answers true for. Defaults to none.
    var supported: @Sendable (DeltaSkinTraits) -> Bool = { _ in false }
    var isDebugEnabled: Bool { false }
    var jsonRepresentation: [String: Any] { [:] }
    func supports(_ traits: DeltaSkinTraits) -> Bool { supported(traits) }
    func mappingSize(for traits: DeltaSkinTraits) -> CGSize? { nil }
    func screenGroups(for traits: DeltaSkinTraits) -> [DeltaSkinScreenGroup]? { nil }
    func buttons(for traits: DeltaSkinTraits) -> [DeltaSkinButton]? { nil }
    func screens(for traits: DeltaSkinTraits) -> [DeltaSkinScreen]? { nil }
    func representation(for traits: DeltaSkinTraits) -> DeltaSkin.RepresentationInfo? { nil }
}
