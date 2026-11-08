#if canImport(UIKit)
import CoreGraphics
import Foundation
import SkinKitCore
import SkinKitManager
import Testing
@testable import SkinKitUI

/// Moving the old trait-less `DeltaSkinButtonOffsets` into the per-trait `DeltaSkinLayoutEdits` store.
@MainActor
@Suite("Legacy offset migration")
struct DeltaSkinLegacyOffsetMigrationTests {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LegacyMigration-\(UUID().uuidString)")
    let skin = MockDeltaSkin(identifier: "com.test.migrate.\(UUID().uuidString)")
    var button: String { "\(skin.identifier)-button-0" }

    @Test("Offsets are copied to every trait the skin has, then cleared")
    func migrates() throws {
        let offsets = DeltaSkinButtonOffsets.shared
        defer {
            offsets.resetOffsets(for: skin.identifier)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = DeltaSkinLayoutEdits(editsDirectory: directory)
        let keys = DeltaSkinLayoutEdits.traitKeys(for: skin)
        #expect(keys.contains("iphone.edgeToEdge.portrait"))
        #expect(keys.contains("iphone.edgeToEdge.landscape"))

        // A trait the player already edited keeps that edit.
        let edited = "iphone.edgeToEdge.landscape"
        try store.setEdit(DeltaSkinButtonEdit(dx: 1, dy: 1, scale: 1.5), forButton: button, skinIdentifier: skin.identifier, traitKey: edited)
        offsets.setOffset(CGPoint(x: 12, y: -4), for: button, skinIdentifier: skin.identifier)

        store.migrateLegacyOffsets(from: offsets, skin: skin)

        #expect(!offsets.hasCustomOffsets(for: skin.identifier))
        #expect(store.editedTraitKeys(skinIdentifier: skin.identifier) == keys)
        for key in keys where key != edited {
            #expect(store.edit(forButton: button, skinIdentifier: skin.identifier, traitKey: key) == DeltaSkinButtonEdit(dx: 12, dy: -4))
        }
        #expect(store.edit(forButton: button, skinIdentifier: skin.identifier, traitKey: edited) == DeltaSkinButtonEdit(dx: 1, dy: 1, scale: 1.5))

        // Once moved, a reset goes back to the skin's own frame, not to the old offset.
        try store.resetAll(skinIdentifier: skin.identifier)
        store.migrateLegacyOffsets(from: offsets, skin: skin)
        #expect(!store.hasEdits(skinIdentifier: skin.identifier))
    }

    @Test("A skin with no old offsets is left alone")
    func nothingToMove() {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DeltaSkinLayoutEdits(editsDirectory: directory)
        store.migrateLegacyOffsets(from: .shared, skin: skin)
        #expect(!store.hasEdits(skinIdentifier: skin.identifier))
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}
#endif
