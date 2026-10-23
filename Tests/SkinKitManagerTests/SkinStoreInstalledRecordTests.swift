import Foundation
import Testing
@testable import SkinKitManager

/// Each app keeps reading the installed-skins record it already wrote. These seed the app's old
/// on-disk format by hand (not through the record type) and then load it.
@Suite("SkinStoreInstalledRecord")
struct SkinStoreInstalledRecordTests {

    // MARK: - iFly: a plist dictionary in UserDefaults

    @Test("iFly: reads the dictionary iFly stored with defaults.set under its key")
    func iFlyReadsExistingRecord() {
        let (defaults, cleanup) = TestSupport.makeDefaults()
        defer { cleanup() }
        // What iFly's `SkinStoreInstalledRecord.markInstalled` wrote: a [String: String] plist value.
        defaults.set(["17b481d711267028": "com.hzn.smashtv.arcade", "3957312ad9e7c59e": "com.starvingartist.dc.dreamsicle-white"],
                     forKey: "iFly.skinStore.installedIds")

        let record = SkinStoreInstalledRecord.iFly(defaults: defaults)
        #expect(record.load() == ["17b481d711267028": "com.hzn.smashtv.arcade", "3957312ad9e7c59e": "com.starvingartist.dc.dreamsicle-white"])
    }

    @Test("iFly: the key and the stored type are what iFly used")
    func iFlyKeyAndType() {
        let (defaults, cleanup) = TestSupport.makeDefaults()
        defer { cleanup() }
        #expect(SkinStorePrefs.installedIds == "iFly.skinStore.installedIds")

        let record = SkinStoreInstalledRecord(defaults: defaults)
        record.markInstalled(catalogId: "a", skinIdentifier: "skin.a")
        #expect(defaults.dictionary(forKey: "iFly.skinStore.installedIds") as? [String: String] == ["a": "skin.a"])
        #expect(defaults.data(forKey: "iFly.skinStore.installedIds") == nil, "a plist dictionary, not JSON data")
    }

    @Test("iFly: mark, remove, and an empty or wrongly typed value reads as empty")
    func iFlyMarkRemove() {
        let (defaults, cleanup) = TestSupport.makeDefaults()
        defer { cleanup() }
        let record = SkinStoreInstalledRecord(defaults: defaults)
        #expect(record.load().isEmpty)

        record.markInstalled(catalogId: "a", skinIdentifier: "skin.a")
        record.markInstalled(catalogId: "b", skinIdentifier: "skin.b")
        record.markInstalled(catalogId: "a", skinIdentifier: "skin.a2")
        #expect(record.load() == ["a": "skin.a2", "b": "skin.b"])

        record.remove(catalogIds: ["a", "never-installed"])
        #expect(record.load() == ["b": "skin.b"])
        record.remove(catalogIds: [])
        #expect(record.load() == ["b": "skin.b"])

        defaults.set("not a dictionary", forKey: "iFly.skinStore.installedIds")
        #expect(record.load().isEmpty)
    }

    @Test("iFly: the record is scoped to the defaults it is given")
    func iFlyIsolation() {
        let first = TestSupport.makeDefaults()
        let second = TestSupport.makeDefaults()
        defer { first.cleanup(); second.cleanup() }
        SkinStoreInstalledRecord(defaults: first.defaults).markInstalled(catalogId: "a", skinIdentifier: "x")
        #expect(SkinStoreInstalledRecord(defaults: second.defaults).load().isEmpty)
    }

    // MARK: - iCube: a JSON file

    @Test("iCube: reads the store.json iCube wrote, beside the library root")
    func iCubeReadsExistingRecord() throws {
        let root = try TestSupport.makeScratch("SkinStoreInstalledRecordTests")
        defer { try? FileManager.default.removeItem(at: root) }
        // What iCube's `SkinStoreInstalledRecord.save` wrote: a JSON object, in `store.json`.
        let json = #"{"6f1c7b2a9d3e4f50":"com.starvingartist.gamecubepocket"}"#
        try Data(json.utf8).write(to: root.appendingPathComponent("store.json"))

        let record = SkinStoreInstalledRecord.iCube(rootURL: root)
        #expect(record.load() == ["6f1c7b2a9d3e4f50": "com.starvingartist.gamecubepocket"])
        #expect(SkinStoreInstalledRecord.iCubeFileName == "store.json")
    }

    @Test("iCube: writes JSON atomically, creating the folder, and reads it back")
    func iCubeWritesJSON() throws {
        let root = try TestSupport.makeScratch("SkinStoreInstalledRecordTests").appendingPathComponent("Skins", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let record = SkinStoreInstalledRecord.iCube(rootURL: root)
        #expect(record.load().isEmpty, "a missing file reads as empty")

        record.markInstalled(catalogId: "a", skinIdentifier: "skin.a")
        record.markInstalled(catalogId: "b", skinIdentifier: "skin.b")
        record.remove(catalogIds: ["a"])

        let data = try Data(contentsOf: root.appendingPathComponent("store.json"))
        #expect(try JSONDecoder().decode([String: String].self, from: data) == ["b": "skin.b"])
        #expect(SkinStoreInstalledRecord(fileURL: root.appendingPathComponent("store.json")).load() == ["b": "skin.b"])
    }

    @Test("iCube: a corrupt file reads as empty rather than failing")
    func iCubeCorruptFile() throws {
        let root = try TestSupport.makeScratch("SkinStoreInstalledRecordTests")
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("{ not json".utf8).write(to: root.appendingPathComponent("store.json"))
        #expect(SkinStoreInstalledRecord.iCube(rootURL: root).load().isEmpty)
    }

    // MARK: - Custom storage

    @Test("Any storage can back a record")
    func customStorage() {
        final class Box: @unchecked Sendable { var value: [String: String] = [:] }
        let box = Box()
        let record = SkinStoreInstalledRecord(load: { box.value }, save: { box.value = $0 })
        record.markInstalled(catalogId: "a", skinIdentifier: "skin.a")
        #expect(box.value == ["a": "skin.a"])
    }
}
