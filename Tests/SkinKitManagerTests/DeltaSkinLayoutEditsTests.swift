import CoreGraphics
import Foundation
import SkinKitCore
import Testing
@testable import SkinKitManager

@Suite("DeltaSkinLayoutEdits")
struct DeltaSkinLayoutEditsTests {
    let directory: URL
    let store: DeltaSkinLayoutEdits
    let skin = "com.example.skin"
    let portrait = "iphone.edgeToEdge.portrait"
    let landscape = "iphone.edgeToEdge.landscape"

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LayoutEditsTests-\(UUID().uuidString)", isDirectory: true)
        store = DeltaSkinLayoutEdits(editsDirectory: directory)
    }

    private func cleanup() { try? FileManager.default.removeItem(at: directory) }

    @Test("Trait key is device.displayType.orientation")
    func traitKeySpelling() {
        let traits = DeltaSkinTraits(device: .ipad, displayType: .splitView, orientation: .landscape)
        #expect(traits.layoutEditKey == "ipad.splitView.landscape")
        #expect(DeltaSkinLayoutEdits.traitKey(device: .iphone, displayType: .edgeToEdge, orientation: .portrait) == portrait)
    }

    @Test("A portrait nudge leaves landscape alone")
    func perTraitIsolation() throws {
        defer { cleanup() }
        try store.setEdit(DeltaSkinButtonEdit(dx: 12, dy: -4), forButton: "a", skinIdentifier: skin, traitKey: portrait)
        #expect(store.edit(forButton: "a", skinIdentifier: skin, traitKey: portrait) == DeltaSkinButtonEdit(dx: 12, dy: -4))
        #expect(store.edit(forButton: "a", skinIdentifier: skin, traitKey: landscape) == .identity)
        #expect(store.editedTraitKeys(skinIdentifier: skin) == [portrait])
        #expect(store.hasEdits(skinIdentifier: skin, traitKey: landscape) == false)
    }

    @Test("Round trip through the file survives a new instance")
    func roundTrip() throws {
        defer { cleanup() }
        try store.setEdit(DeltaSkinButtonEdit(dx: 3, dy: 5, scale: 1.5), forButton: "a", skinIdentifier: skin, traitKey: portrait)
        try store.setEdit(DeltaSkinButtonEdit(dx: -7, dy: 0), forButton: "b", skinIdentifier: skin, traitKey: landscape)

        let reloaded = DeltaSkinLayoutEdits(editsDirectory: directory)
        #expect(reloaded.edit(forButton: "a", skinIdentifier: skin, traitKey: portrait) == DeltaSkinButtonEdit(dx: 3, dy: 5, scale: 1.5))
        #expect(reloaded.edit(forButton: "b", skinIdentifier: skin, traitKey: landscape) == DeltaSkinButtonEdit(dx: -7, dy: 0))
        #expect(reloaded.document(for: skin) == store.document(for: skin))
    }

    @Test("The file is <edits dir>/<identifier>-<digest>.json with the documented shape")
    func fileShape() throws {
        defer { cleanup() }
        try store.setEdit(DeltaSkinButtonEdit(dx: 1, dy: 2, scale: 1.25), forButton: "a", skinIdentifier: skin, traitKey: portrait)
        let url = directory.appendingPathComponent(DeltaSkinLayoutEdits.fileName(forSkinIdentifier: skin))
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(json["skinIdentifier"] as? String == skin)
        #expect(json["version"] as? Int == 1)
        let traits = try #require(json["traits"] as? [String: [String: [String: Double]]])
        #expect(traits[portrait]?["a"] == ["dx": 1, "dy": 2, "scale": 1.25])
    }

    @Test("Storage-backed init puts the file under <skinsDirectory>/edits")
    func storageBacked() throws {
        defer { cleanup() }
        let storage = DeltaSkinStorage(directory: directory)
        let edits = DeltaSkinLayoutEdits(storage: storage)
        try edits.setEdit(DeltaSkinButtonEdit(dx: 1), forButton: "a", skinIdentifier: skin, traitKey: portrait)
        let expected = directory.appendingPathComponent("edits/" + DeltaSkinLayoutEdits.fileName(forSkinIdentifier: skin))
        #expect(FileManager.default.fileExists(atPath: expected.path))
    }

    @Test("Identity edits are not stored and an emptied file is deleted")
    func identityRemoves() throws {
        defer { cleanup() }
        let url = try store.fileURL(forSkinIdentifier: skin)
        try store.setEdit(DeltaSkinButtonEdit(dx: 4), forButton: "a", skinIdentifier: skin, traitKey: portrait)
        #expect(FileManager.default.fileExists(atPath: url.path))
        try store.setEdit(.identity, forButton: "a", skinIdentifier: skin, traitKey: portrait)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(store.hasEdits(skinIdentifier: skin) == false)
    }

    @Test("Scale is clamped to 0.5...2.0")
    func scaleClamped() throws {
        defer { cleanup() }
        try store.setEdit(DeltaSkinButtonEdit(scale: 9), forButton: "a", skinIdentifier: skin, traitKey: portrait)
        try store.setEdit(DeltaSkinButtonEdit(scale: 0.1), forButton: "b", skinIdentifier: skin, traitKey: portrait)
        #expect(store.edit(forButton: "a", skinIdentifier: skin, traitKey: portrait).scale == 2.0)
        #expect(store.edit(forButton: "b", skinIdentifier: skin, traitKey: portrait).scale == 0.5)
    }

    @Test("Reset a button, a trait, and a whole skin")
    func resets() throws {
        defer { cleanup() }
        for trait in [portrait, landscape] {
            for button in ["a", "b"] {
                try store.setEdit(DeltaSkinButtonEdit(dx: 1), forButton: button, skinIdentifier: skin, traitKey: trait)
            }
        }
        try store.resetButton("a", skinIdentifier: skin, traitKey: portrait)
        #expect(store.edits(skinIdentifier: skin, traitKey: portrait).keys.sorted() == ["b"])
        #expect(store.edits(skinIdentifier: skin, traitKey: landscape).count == 2)

        try store.resetTrait(skinIdentifier: skin, traitKey: portrait)
        #expect(store.editedTraitKeys(skinIdentifier: skin) == [landscape])

        try store.resetAll(skinIdentifier: skin)
        #expect(store.hasEdits(skinIdentifier: skin) == false)
        #expect(!FileManager.default.fileExists(atPath: try store.fileURL(forSkinIdentifier: skin).path))
    }

    @Test("Skins do not see each other's edits")
    func skinsAreSeparate() throws {
        defer { cleanup() }
        try store.setEdit(DeltaSkinButtonEdit(dx: 1), forButton: "a", skinIdentifier: "one", traitKey: portrait)
        #expect(store.hasEdits(skinIdentifier: "two") == false)
    }

    @Test("Frame application scales about the center, then moves")
    func frameApplication() {
        let frame = CGRect(x: 100, y: 200, width: 40, height: 20)
        #expect(DeltaSkinButtonEdit.identity.applying(to: frame) == frame)
        #expect(DeltaSkinButtonEdit(dx: 10, dy: -5).applying(to: frame) == CGRect(x: 110, y: 195, width: 40, height: 20))
        let scaled = DeltaSkinButtonEdit(scale: 2).applying(to: frame)
        #expect(scaled == CGRect(x: 80, y: 190, width: 80, height: 40))
        #expect(scaled.midX == frame.midX && scaled.midY == frame.midY)
        // Out-of-range scale is clamped here too, so a hand-edited file can't blow a button up.
        #expect(DeltaSkinButtonEdit(scale: 50).applying(to: frame).width == 80)
    }

    @Test("editedFrame reads the store")
    func editedFrame() throws {
        defer { cleanup() }
        let frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        try store.setEdit(DeltaSkinButtonEdit(dx: 5), forButton: "a", skinIdentifier: skin, traitKey: portrait)
        #expect(store.editedFrame(frame, forButton: "a", skinIdentifier: skin, traitKey: portrait).minX == 5)
        #expect(store.editedFrame(frame, forButton: "a", skinIdentifier: skin, traitKey: landscape) == frame)
        #expect(store.editedFrame(frame, forButton: "zzz", skinIdentifier: skin, traitKey: portrait) == frame)
    }

    @Test("Legacy offsets are applied to every trait and never overwrite newer edits")
    func legacyMigration() throws {
        defer { cleanup() }
        try store.setEdit(DeltaSkinButtonEdit(dx: 99), forButton: "a", skinIdentifier: skin, traitKey: landscape)
        try store.importLegacyOffsets(
            ["a": CGPoint(x: 1, y: 2), "b": CGPoint(x: -3, y: 0), "zero": .zero],
            skinIdentifier: skin,
            traitKeys: [portrait, landscape]
        )
        #expect(store.edit(forButton: "a", skinIdentifier: skin, traitKey: portrait) == DeltaSkinButtonEdit(dx: 1, dy: 2))
        #expect(store.edit(forButton: "b", skinIdentifier: skin, traitKey: portrait) == DeltaSkinButtonEdit(dx: -3))
        #expect(store.edit(forButton: "b", skinIdentifier: skin, traitKey: landscape) == DeltaSkinButtonEdit(dx: -3))
        #expect(store.edit(forButton: "a", skinIdentifier: skin, traitKey: landscape) == DeltaSkinButtonEdit(dx: 99))
        #expect(store.edit(forButton: "zero", skinIdentifier: skin, traitKey: portrait) == .identity)
    }

    @Test("A corrupt file reads as no edits and can be overwritten")
    func corruptFile() throws {
        defer { cleanup() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: try store.fileURL(forSkinIdentifier: skin))
        #expect(store.hasEdits(skinIdentifier: skin) == false)
        try store.setEdit(DeltaSkinButtonEdit(dx: 2), forButton: "a", skinIdentifier: skin, traitKey: portrait)
        let reloaded = DeltaSkinLayoutEdits(editsDirectory: directory)
        #expect(reloaded.edit(forButton: "a", skinIdentifier: skin, traitKey: portrait).dx == 2)
    }

    @Test("Hostile identifiers stay inside the edits folder")
    func fileNameSafety() throws {
        defer { cleanup() }
        let evil = "../../etc/passwd"
        let name = DeltaSkinLayoutEdits.fileName(forSkinIdentifier: evil)
        #expect(!name.contains("/"))
        #expect(!name.hasPrefix("."))
        try store.setEdit(DeltaSkinButtonEdit(dx: 1), forButton: "a", skinIdentifier: evil, traitKey: portrait)
        let url = try store.fileURL(forSkinIdentifier: evil)
        #expect(url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL)
        let name2 = DeltaSkinLayoutEdits.fileName(forSkinIdentifier: "com.example.skin")
        #expect(name2.hasPrefix("com.example.skin-") && name2.hasSuffix(".json"))
        #expect(DeltaSkinLayoutEdits.fileName(forSkinIdentifier: String(repeating: "x", count: 1000)).count < 255)
    }

    @Test("Identifiers that differ only by case keep separate edits on a case-insensitive disk")
    func caseOnlyIdentifiers() throws {
        defer { cleanup() }
        let upper = "com.example.Skin", lower = "com.example.skin"
        let a = DeltaSkinLayoutEdits.fileName(forSkinIdentifier: upper)
        let b = DeltaSkinLayoutEdits.fileName(forSkinIdentifier: lower)
        #expect(a.lowercased() != b.lowercased())
        try store.setEdit(DeltaSkinButtonEdit(dx: 5), forButton: "a", skinIdentifier: upper, traitKey: portrait)
        try store.setEdit(DeltaSkinButtonEdit(dx: 9), forButton: "a", skinIdentifier: lower, traitKey: portrait)
        try store.setEdit(.identity, forButton: "a", skinIdentifier: lower, traitKey: portrait)   // reset one
        let fresh = DeltaSkinLayoutEdits(editsDirectory: directory)
        #expect(fresh.edit(forButton: "a", skinIdentifier: upper, traitKey: portrait).dx == 5)
        #expect(fresh.edit(forButton: "a", skinIdentifier: lower, traitKey: portrait) == .identity)
    }

    @Test("A file whose stored identifier is another skin's is ignored")
    func mismatchedDocumentIgnored() throws {
        defer { cleanup() }
        try store.setEdit(DeltaSkinButtonEdit(dx: 3), forButton: "a", skinIdentifier: "other.skin", traitKey: portrait)
        let source = try store.fileURL(forSkinIdentifier: "other.skin")
        let target = try store.fileURL(forSkinIdentifier: skin)
        try FileManager.default.copyItem(at: source, to: target)
        let fresh = DeltaSkinLayoutEdits(editsDirectory: directory)
        #expect(!fresh.hasEdits(skinIdentifier: skin))
    }
}
