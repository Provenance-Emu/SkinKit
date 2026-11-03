import Foundation
import SkinCatalogKit
import Testing
@testable import SkinKitManager

/// Variant families on the install side (SkinKit#17): the `.skinmeta` sidecar and the store's
/// installed record gain `groupId` / `groupOrder` / `variantLabel`, installs write them, records from
/// before families migrate on read, and a download plan installs one, some or all members.
@Suite("Store families")
@MainActor
struct SkinStoreFamilyTests {

    private static func entry(
        _ id: String,
        name: String,
        group: String? = nil,
        order: Int? = nil,
        label: String? = nil,
        systems: [String] = ["mame"]
    ) -> SkinCatalogEntry {
        SkinCatalogEntry(
            id: id, name: name, systems: systems,
            downloadURL: URL(string: "https://deltastyles.com/files/skins/1/\(id).manicskin")!,
            groupId: group, groupOrder: order, variantLabel: label
        )
    }

    private static let doom = entry("doom", name: "Jaguar Paw — Doom", group: "paw", order: 1)
    private static let avp = entry("avp", name: "Jaguar Paw — Alien vs Predator", group: "paw", order: 2, label: "AvP")
    private static let solo = entry("solo", name: "Solo Pad")
    private static let catalog = SkinCatalog(skins: [doom, avp, solo])

    // MARK: - Installed record

    @Test("markInstalled(entry:) stores the family next to the id map", arguments: StorePreset.all)
    func recordStoresFamily(preset: StorePreset) throws {
        let (record, reopen, cleanup) = try preset.makeRecord()
        defer { cleanup() }
        record.markInstalled(entry: Self.avp, skinIdentifier: "skin.avp", index: Self.catalog.familyIndex)
        record.markInstalled(entry: Self.solo, skinIdentifier: "skin.solo")

        let again = reopen()
        #expect(again.load() == ["avp": "skin.avp", "solo": "skin.solo"], "the id map keeps its old shape")
        #expect(again.storedMemberships()["avp"] == SkinFamilyMembership(groupId: "paw", groupOrder: 2, variantLabel: "AvP"))
        #expect(again.storedMemberships()["solo"] == .standalone)
        #expect(again.membershipsBySkinIdentifier(migratingWith: nil) == [
            "skin.avp": SkinFamilyMembership(groupId: "paw", groupOrder: 2, variantLabel: "AvP"),
        ], "standalone skins are left out")
    }

    @Test("iFly keeps installedIds a plist dictionary and the families in their own key")
    func iFlyStorageShape() {
        let (defaults, cleanup) = TestSupport.makeDefaults()
        defer { cleanup() }
        SkinStoreInstalledRecord.iFly(defaults: defaults).markInstalled(entry: Self.doom, skinIdentifier: "skin.doom")
        #expect(defaults.dictionary(forKey: SkinStorePrefs.installedIds) as? [String: String] == ["doom": "skin.doom"])
        #expect(defaults.data(forKey: SkinStorePrefs.installedFamilies) != nil)
    }

    @Test("iCube writes store-families.json beside store.json")
    func iCubeStorageShape() throws {
        let root = try TestSupport.makeScratch("StoreFamilies-iCube")
        defer { try? FileManager.default.removeItem(at: root) }
        SkinStoreInstalledRecord.iCube(rootURL: root).markInstalled(entry: Self.doom, skinIdentifier: "skin.doom")
        let ids = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: root.appendingPathComponent("store.json")))
        #expect(ids == ["doom": "skin.doom"])
        let families = try JSONDecoder().decode(
            [String: SkinFamilyMembership].self,
            from: Data(contentsOf: root.appendingPathComponent(SkinStoreInstalledRecord.iCubeFamiliesFileName))
        )
        #expect(families["doom"] == SkinFamilyMembership(groupId: "paw", groupOrder: 1, variantLabel: "Doom"))
    }

    @Test("Records from before families migrate from the catalog, once", arguments: StorePreset.all)
    func recordMigration(preset: StorePreset) throws {
        let (record, reopen, cleanup) = try preset.makeRecord()
        defer { cleanup() }
        // What an older build wrote: ids only.
        record.markInstalled(catalogId: "doom", skinIdentifier: "skin.doom")
        record.markInstalled(catalogId: "gone-from-catalog", skinIdentifier: "skin.gone")

        #expect(record.memberships(migratingWith: nil).isEmpty, "no catalog: nothing saved, retried later")
        #expect(reopen().storedMemberships().isEmpty)

        let migrated = record.memberships(migratingWith: Self.catalog)
        #expect(migrated["doom"] == SkinFamilyMembership(groupId: "paw", groupOrder: 1, variantLabel: "Doom"))
        #expect(migrated["gone-from-catalog"] == .standalone, "not in the catalog: stays standalone")

        let stored = reopen().storedMemberships()
        #expect(stored.count == 2, "saved, so the next read doesn't look again")
        #expect(reopen().membershipsBySkinIdentifier(migratingWith: nil) == [
            "skin.doom": SkinFamilyMembership(groupId: "paw", groupOrder: 1, variantLabel: "Doom"),
        ])
    }

    @Test("Removing an install drops its family too", arguments: StorePreset.all)
    func removeDropsFamily(preset: StorePreset) throws {
        let (record, reopen, cleanup) = try preset.makeRecord()
        defer { cleanup() }
        record.markInstalled(entry: Self.doom, skinIdentifier: "skin.doom")
        record.markInstalled(entry: Self.avp, skinIdentifier: "skin.avp")
        record.remove(catalogIds: ["doom"])
        #expect(Set(reopen().storedMemberships().keys) == ["avp"])
    }

    // MARK: - Sidecar

    @Test("The sidecar records the family at version 2")
    func sidecarWritesFamily() async throws {
        let dir = try TestSupport.makeScratch("StoreFamilies-sidecar")
        defer { try? FileManager.default.removeItem(at: dir) }
        let skinURL = dir.appendingPathComponent("doom.deltaskin")
        let registry = SkinSystemOverrideRegistry()
        try await registry.writeSidecar(for: skinURL, entry: Self.doom, skinIdentifier: "skin.doom", index: Self.catalog.familyIndex)

        let sidecar = try #require(registry.readSidecar(for: skinURL))
        #expect(sidecar.version == SkinCatalogSidecar.currentVersion)
        #expect(sidecar.familyMembership == SkinFamilyMembership(groupId: "paw", groupOrder: 1, variantLabel: "Doom"))

        let skin = StubSkin(identifier: "skin.doom", name: "Jaguar Paw — Doom", gameType: .gba, fileURL: skinURL)
        #expect(await registry.familyMemberships(for: [skin], catalog: nil)["skin.doom"]?.groupId == "paw")
    }

    @Test("A version 1 sidecar migrates on read when a catalog is at hand, else stays put")
    func sidecarMigration() async throws {
        let dir = try TestSupport.makeScratch("StoreFamilies-sidecar-v1")
        defer { try? FileManager.default.removeItem(at: dir) }
        let avpURL = dir.appendingPathComponent("avp.deltaskin")
        let soloURL = dir.appendingPathComponent("solo.deltaskin")
        let strayURL = dir.appendingPathComponent("stray.deltaskin")
        let bareURL = dir.appendingPathComponent("bare.deltaskin")
        for (url, id) in [(avpURL, "avp"), (soloURL, "solo"), (strayURL, "not-in-catalog")] {
            let json = #"{"version": 1, "catalogEntryId": "\#(id)", "skinIdentifier": "skin.\#(id)", "name": "x", "systems": ["mame"]}"#
            try Data(json.utf8).write(to: SkinSystemOverrideRegistry.sidecarURL(for: url))
        }
        let skins = [
            StubSkin(identifier: "skin.avp", name: "AvP", gameType: .gba, fileURL: avpURL),
            StubSkin(identifier: "skin.solo", name: "Solo", gameType: .gba, fileURL: soloURL),
            StubSkin(identifier: "skin.stray", name: "Stray", gameType: .gba, fileURL: strayURL),
            StubSkin(identifier: "skin.bare", name: "Bare", gameType: .gba, fileURL: bareURL),
        ]
        let registry = SkinSystemOverrideRegistry()

        #expect(await registry.familyMemberships(for: skins, catalog: nil).isEmpty)
        #expect(registry.readSidecar(for: avpURL)?.version == 1, "no catalog: left for later")

        let memberships = await registry.familyMemberships(for: skins, catalog: Self.catalog)
        #expect(memberships == ["skin.avp": SkinFamilyMembership(groupId: "paw", groupOrder: 2, variantLabel: "AvP")])
        let avp = try #require(registry.readSidecar(for: avpURL))
        #expect(avp.version == 2)
        #expect(avp.catalogEntryId == "avp", "the rest of the sidecar is kept")
        #expect(avp.systems == ["mame"])
        #expect(registry.readSidecar(for: soloURL)?.hasFamilyFields == true, "standalone, and marked done")
        #expect(registry.readSidecar(for: strayURL)?.familyMembership == .standalone)
        #expect(registry.readSidecar(for: bareURL) == nil, "a skin without a sidecar gets none")
    }

    // MARK: - Installing a plan

    @Test("A family plan installs each member file in order and records each family", arguments: StorePreset.all)
    func installPlan(preset: StorePreset) async throws {
        let (record, _, cleanup) = try preset.makeRecord()
        defer { cleanup() }
        let members = (1 ... 3).map { (i: Int) in Self.entry("m\(i)", name: "Pack — V\(i)", group: "pack", order: i, systems: [preset.installableSystemCode]) }
        let zip = SkinCatalogEntry(
            id: "zip", name: "Pack — Zip", systems: [preset.installableSystemCode],
            downloadURL: URL(string: "https://example.com/pack.zip")!, groupId: "pack", groupOrder: 4
        )
        let family = try #require(SkinFamily.families(from: members + [zip]).first)
        var installed: [String] = []
        let installer = SkinStoreInstaller(
            policy: preset.policy, downloader: FakeDownloader(), record: record, appName: preset.appName
        ) { file, _ in
            installed.append(file.deletingPathExtension().lastPathComponent)
            return .installed(identifier: "skin.\(file.deletingPathExtension().lastPathComponent)")
        }
        installer.familyIndex = SkinFamilyIndex(entries: members + [zip])

        let plan = family.downloadPlan(policy: preset.policy)
        #expect(plan.entries.map(\.id) == ["m1", "m2", "m3"], "the .zip member can't install here")

        await installer.install(family.downloadPlan(for: members[1], policy: preset.policy))
        #expect(installed == ["m2"])
        #expect(installer.remaining(plan).entries.map(\.id) == ["m1", "m3"])

        await installer.install(plan)
        #expect(installed == ["m2", "m1", "m3"], "already-installed members are skipped")
        #expect(plan.entries.allSatisfy { installer.state(for: $0) == .installed })
        #expect(!installer.isBusy(plan))
        #expect(record.storedMemberships()["m3"] == SkinFamilyMembership(groupId: "pack", groupOrder: 3, variantLabel: "V3"))
    }
}
