import Foundation
import SkinKitCore
import Testing
@testable import SkinKitManager

/// `Configuration.rescansOnEveryRead`: Provenance scans once and serves the cached list; iFly's
/// manager read the folders on every `availableSkins()`.
@Suite("DeltaSkinManager.Configuration.rescansOnEveryRead", .serialized)
@MainActor
final class DeltaSkinManagerRescanTests {
    private let skinsDirectory: URL
    private let defaults: UserDefaults
    private let cleanup: () -> Void

    init() throws {
        skinsDirectory = try TestSupport.makeScratch().appendingPathComponent("Skins", isDirectory: true)
        (defaults, cleanup) = TestSupport.makeDefaults()
        try FileManager.default.createDirectory(at: skinsDirectory, withIntermediateDirectories: true)
    }

    deinit {
        cleanup()
        try? FileManager.default.removeItem(at: skinsDirectory.deletingLastPathComponent())
    }

    private func makeManager(rescans: Bool) -> DeltaSkinManager {
        DeltaSkinManager(
            configuration: DeltaSkinManager.Configuration(
                skinsDirectory: skinsDirectory,
                bundledSkinLocations: { [] },
                rescansOnEveryRead: rescans
            ),
            selectionManager: DeltaSkinSelectionManager(preferences: DeltaSkinPreferences(defaults: defaults))
        )
    }

    private func dropInFolder(_ fixture: String) throws {
        try FileManager.default.copyItem(
            at: TestSupport.fixtureURL(fixture),
            to: skinsDirectory.appendingPathComponent("\(fixture).deltaskin")
        )
    }

    @Test("Off (the default): a file added after the first scan is not seen until a rescan is asked for")
    func offServesTheCache() async throws {
        let manager = makeManager(rescans: false)
        #expect(try await manager.availableSkins().isEmpty)

        try dropInFolder("N64-Test")
        #expect(try await manager.availableSkins().isEmpty)
        #expect(try await manager.availableSkins(forceRescan: true).map(\.identifier) == ["com.provenance.test.n64"])
    }

    @Test("On: every availableSkins() sees files added since the last read, and files removed")
    func onRescansEveryCall() async throws {
        let manager = makeManager(rescans: true)
        #expect(try await manager.availableSkins().isEmpty)

        try dropInFolder("N64-Test")
        #expect(try await manager.availableSkins().map(\.identifier) == ["com.provenance.test.n64"])

        try FileManager.default.removeItem(at: skinsDirectory.appendingPathComponent("N64-Test.deltaskin"))
        #expect(try await manager.availableSkins().isEmpty)
    }

    @Test("The default configuration and the Provenance preset do not rescan; the iFly preset does")
    func presets() {
        #expect(!DeltaSkinManager.Configuration(skinsDirectory: skinsDirectory).rescansOnEveryRead)
        #expect(!DeltaSkinManager.Configuration.provenance().rescansOnEveryRead)
        #expect(DeltaSkinManager.Configuration.iFly().rescansOnEveryRead)
    }
}
