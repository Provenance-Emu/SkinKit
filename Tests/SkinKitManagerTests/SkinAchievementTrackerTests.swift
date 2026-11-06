import Foundation
import SkinCatalogKit
import SkinKitCore
import Testing
@testable import SkinKitManager

private let epoch = Date(timeIntervalSince1970: 1_800_000_000)
private let day: TimeInterval = 86_400
private let key = SkinAchievementTracker.earnedKey

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date) { current = start }
    var now: Date {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

private func entry(
    _ id: String,
    system: String = "gba",
    author: String = "starvingartist",
    groupId: String? = nil,
    groupOrder: Int? = nil
) -> SkinCatalogEntry {
    SkinCatalogEntry(
        id: id,
        name: groupId == nil ? "Skin \(id)" : "Set — \(id)",
        author: author,
        systems: [system],
        downloadURL: URL(string: "https://example.com/\(id).deltaskin")!,
        groupId: groupId,
        groupOrder: groupOrder
    )
}

private func loaded(_ identifier: String, file: String? = nil) -> StubSkin {
    StubSkin(identifier: identifier, name: "Loaded \(identifier)", gameType: .gba,
             fileURL: URL(fileURLWithPath: "/skins/\(file ?? identifier + ".deltaskin")"))
}

private func pick(_ system: String, _ skin: String = "skin") -> (SkinSystemID, [SkinOrientation: String]) {
    (SkinSystemID(system), [.portrait: skin])
}

/// A device: its own `UserDefaults`, clock and cloud replica.
@MainActor
private struct Device {
    let tracker: SkinAchievementTracker
    let defaults: UserDefaults
    let cloud: InMemoryKeyValueCloudStore?
    let clock: Clock
    let cleanup: () -> Void

    init(cloud: InMemoryKeyValueCloudStore?, start: Date = epoch) {
        (defaults, cleanup) = TestSupport.makeDefaults()
        self.cloud = cloud
        clock = Clock(start)
        let clock = self.clock
        tracker = SkinAchievementTracker(defaults: defaults, cloud: cloud, now: { clock.now })
    }

    func relaunched() -> SkinAchievementTracker {
        let clock = self.clock
        return SkinAchievementTracker(defaults: defaults, cloud: cloud, now: { clock.now })
    }
}

@Suite("SkinUserStats")
struct SkinUserStatsTests {
    @Test("Nothing stored means zero stats and no badges")
    func empty() {
        let stats = SkinUserStats.derive(from: .init())
        #expect(stats == SkinUserStats())
        #expect(stats.metBadgeIds.isEmpty)
    }

    @Test("Systems tried counts non-default picks per system")
    func systemsFromPicks() {
        var inputs = SkinUserStats.Inputs()
        inputs.selectedSkins = [pick("nes").0: pick("nes").1, pick("snes").0: pick("snes").1]
        // Both orientations on one system are one system.
        inputs.selectedSkins[SkinSystemID("gba")] = [.portrait: "a", .landscape: "b"]
        // The built-in token is "no skin".
        inputs.selectedSkins[SkinSystemID("n64")] = [.portrait: DeltaSkinSelectionManager.builtInSkinPreferenceToken]
        #expect(SkinUserStats.derive(from: inputs).systemsTried == 3)
    }

    @Test("Installed systems count too, so installing on three systems is enough")
    func systemsFromInstalls() {
        let catalog = SkinCatalog(skins: [
            entry("a", system: "gba"), entry("b", system: "nes"), entry("c", system: "snes"),
            entry("d", system: "unofficial"), entry("e", system: "gba"),
        ])
        var inputs = SkinUserStats.Inputs(installedCatalogIds: ["a", "b", "c", "d", "e"], catalog: catalog)
        let stats = SkinUserStats.derive(from: inputs)
        #expect(stats.installed == 5)
        #expect(stats.systemsTried == 3, "placeholder codes and repeats do not count")

        inputs.selectedSkins = [pick("a").0: pick("a").1, pick("b").0: pick("b").1,
                                pick("c").0: pick("c").1, pick("d").0: pick("d").1]
        #expect(SkinUserStats.derive(from: inputs).systemsTried == 4, "the larger of the two")
    }

    @Test("Games, themes, layouts and follows")
    func otherCounts() {
        let inputs = SkinUserStats.Inputs(
            gameSpecificSkins: ["g1": [.portrait: "a"], "g2": [.landscape: "b"],
                                "g3": [.portrait: DeltaSkinSelectionManager.builtInSkinPreferenceToken]],
            skinsWithTheme: ["a", "b"],
            gameAltRepresentations: ["g1": ["a", "b"], "g2": ["b", "c"]],
            followedSlugs: ["x", "y", "z"]
        )
        let stats = SkinUserStats.derive(from: inputs)
        #expect(stats.gamesCustomised == 2)
        #expect(stats.themesUsed == 2)
        #expect(stats.altLayoutsUsed == 3, "distinct skins across games")
        #expect(stats.creatorsFollowed == 3)
    }

    @Test("A family is complete when every file is installed; a standalone skin is not a set")
    func familiesCompleted() {
        let catalog = SkinCatalog(skins: [
            entry("s1", groupId: "set", groupOrder: 1), entry("s2", groupId: "set", groupOrder: 2),
            entry("t1", groupId: "other", groupOrder: 1), entry("t2", groupId: "other", groupOrder: 2),
            entry("solo"),
        ])
        func completed(_ ids: Set<String>) -> Int {
            SkinUserStats.derive(from: .init(installedCatalogIds: ids, catalog: catalog)).familiesCompleted
        }
        #expect(completed(["solo"]) == 0)
        #expect(completed(["s1"]) == 0)
        #expect(completed(["s1", "s2"]) == 1)
        #expect(completed(["s1", "s2", "t1"]) == 1)
        #expect(completed(["s1", "s2", "t1", "t2", "solo"]) == 2)
    }

    @Test("Installed-from counts distinct creators, through the override and aliases")
    func creatorsInstalledFrom() {
        let catalog = SkinCatalog(skins: [
            entry("a", author: "Ann"), entry("b", author: "Ann"), entry("c", author: "Bob"),
            SkinCatalogEntry(id: "d", name: "D", author: "Ann", creatorSlug: "carol",
                             systems: ["gba"], downloadURL: URL(string: "https://example.com/d.deltaskin")!),
        ])
        let stats = SkinUserStats.derive(from: .init(installedCatalogIds: ["a", "b", "c", "d"], catalog: catalog))
        #expect(stats.creatorsInstalledFrom == 3, "ann, bob and the override's carol")
    }

    @Test("Badges follow the thresholds, lower tiers included")
    func thresholds() {
        var stats = SkinUserStats()
        stats.installed = 1
        #expect(stats.metBadgeIds == ["user.first-install"])

        stats.systemsTried = 5
        stats.creatorsFollowed = 1
        #expect(stats.metBadgeIds == ["user.first-install", "user.systems.3", "user.systems.5", "user.follow.1"])

        stats.themesUsed = 1
        stats.altLayoutsUsed = 1
        stats.familiesCompleted = 1
        stats.creatorsInstalledFrom = 5
        stats.systemsTried = 10
        #expect(stats.metBadgeIds.count == 9)
    }

    @Test("Every rule id is a user badge in the bundled definitions")
    func rulesMatchTheBundledFile() {
        let known = Set(SkinBadgeCatalog.bundled.definitions(for: .user).map(\.id))
        #expect(!known.isEmpty)
        #expect(Set(SkinUserStats.rules.map(\.id)) == known)
    }
}

@Suite("SkinAchievementTracker")
@MainActor
struct SkinAchievementTrackerTests {
    private func systems(_ codes: [String]) -> SkinUserStats.Inputs {
        var inputs = SkinUserStats.Inputs()
        for (offset, code) in codes.enumerated() {
            inputs.selectedSkins[SkinSystemID(code)] = [.portrait: "skin-\(offset)"]
        }
        return inputs
    }

    @Test("Key follows the DeltaSkinPreferences style")
    func keyName() {
        #expect(key == "com.provenance.skinkit.achievements.v1")
    }

    @Test("Three systems earn Explorer, with the day it happened")
    func explorer() {
        let device = Device(cloud: nil)
        defer { device.cleanup() }

        #expect(device.tracker.refresh(systems(["nes", "snes"])).isEmpty)
        device.clock.now = epoch.addingTimeInterval(day)
        let earned = device.tracker.refresh(systems(["nes", "snes", "gba"]))
        #expect(earned == ["user.systems.3"])
        #expect(device.tracker.earned["user.systems.3"] == epoch.addingTimeInterval(day))
        #expect(device.tracker.recentlyEarned.map(\.title) == ["Explorer"])
    }

    @Test("Uninstalling or unpicking does not revoke a badge, and the date stays")
    func neverRevoked() {
        let device = Device(cloud: nil)
        defer { device.cleanup() }
        device.tracker.refresh(systems(["a", "b", "c"]))
        let first = device.tracker.earned["user.systems.3"]
        #expect(first != nil)

        device.clock.now = epoch.addingTimeInterval(10 * day)
        #expect(device.tracker.refresh(.init()).isEmpty)
        #expect(device.tracker.stats.systemsTried == 0, "stats are live")
        #expect(device.tracker.earned["user.systems.3"] == first, "the badge and its date are kept")

        device.tracker.refresh(systems(["a", "b", "c"]))
        #expect(device.tracker.earned["user.systems.3"] == first, "earning again does not move the date")
    }

    @Test("A badge is announced once")
    func announcedOnce() {
        let device = Device(cloud: nil)
        defer { device.cleanup() }
        #expect(device.tracker.refresh(systems(["a", "b", "c"])) == ["user.systems.3"])
        #expect(device.tracker.refresh(systems(["a", "b", "c"])).isEmpty)
        #expect(device.tracker.recentlyEarned.isEmpty)
    }

    @Test("Earned dates survive a relaunch")
    func persists() {
        let device = Device(cloud: nil)
        defer { device.cleanup() }
        device.tracker.refresh(systems(["a", "b", "c"]))
        let again = device.relaunched()
        #expect(again.earned == device.tracker.earned)
        #expect(again.earned["user.systems.3"] == epoch)
    }

    @Test("A second device gets the badge through the cloud")
    func syncs() {
        let cloud = InMemoryKeyValueCloudStore()
        let phone = Device(cloud: cloud)
        let pad = Device(cloud: cloud.replica())
        defer { phone.cleanup(); pad.cleanup() }

        phone.tracker.refresh(systems(["a", "b", "c"]))
        #expect(pad.tracker.earned["user.systems.3"] == epoch)
    }

    @Test("A reinstall keeps its badges from the cloud")
    func reinstall() {
        let cloud = InMemoryKeyValueCloudStore()
        let old = Device(cloud: cloud)
        old.tracker.refresh(systems(["a", "b", "c"]))
        old.cleanup()

        let fresh = Device(cloud: cloud.replica(), start: epoch.addingTimeInterval(30 * day))
        defer { fresh.cleanup() }
        #expect(fresh.tracker.earned["user.systems.3"] == epoch)
        #expect(fresh.tracker.refresh(.init()).isEmpty, "an empty install earns nothing and revokes nothing")
        #expect(fresh.tracker.earned["user.systems.3"] == epoch)
    }

    @Test("When two devices earn a badge while offline, the earlier date wins on both")
    func earlierDateWins() {
        let cloud = InMemoryKeyValueCloudStore()
        let phone = Device(cloud: cloud, start: epoch)
        // The pad is offline: no cloud store yet.
        let pad = Device(cloud: nil, start: epoch.addingTimeInterval(5 * day))
        defer { phone.cleanup(); pad.cleanup() }

        pad.tracker.refresh(systems(["a", "b", "c"]))
        phone.tracker.refresh(systems(["a", "b", "c"]))
        #expect(pad.tracker.earned["user.systems.3"] == epoch.addingTimeInterval(5 * day))

        // The pad comes online: same defaults, now with the account's store.
        let clock = pad.clock
        let online = SkinAchievementTracker(defaults: pad.defaults, cloud: cloud.replica(), now: { clock.now })
        #expect(online.earned["user.systems.3"] == epoch)
        phone.tracker.mergeFromCloud()
        #expect(phone.tracker.earned["user.systems.3"] == epoch)
    }

    @Test("A stale replica cannot drop a badge")
    func staleReplica() {
        let cloud = InMemoryKeyValueCloudStore()
        let phone = Device(cloud: cloud)
        let pad = Device(cloud: cloud.replica())
        defer { phone.cleanup(); pad.cleanup() }

        phone.tracker.refresh(.init(installedCatalogIds: ["a"], catalog: SkinCatalog(skins: [entry("a")])))
        #expect(pad.tracker.earned["user.first-install"] != nil)

        // The pad writes an older, smaller copy straight into the store.
        let stale = try! JSONEncoder().encode([String: Int64]())
        cloud.replica().setData(stale, forKey: key)
        phone.tracker.mergeFromCloud()
        pad.tracker.mergeFromCloud()
        #expect(phone.tracker.earned["user.first-install"] != nil)
        #expect(pad.tracker.earned["user.first-install"] != nil)
        #expect(cloud.data(forKey: key) != stale, "the full map is written back")
    }

    @Test("Merge keeps every badge and the earlier date")
    func mergeLaws() {
        let a: [String: Date] = ["x": epoch, "y": epoch.addingTimeInterval(day)]
        let b: [String: Date] = ["y": epoch, "z": epoch.addingTimeInterval(2 * day)]
        let merged = SkinAchievementTracker.merge(a, b)
        #expect(merged == ["x": epoch, "y": epoch, "z": epoch.addingTimeInterval(2 * day)])
        #expect(SkinAchievementTracker.merge(b, a) == merged)
        #expect(SkinAchievementTracker.merge(merged, merged) == merged)
    }

    @Test("Local-only runs without a cloud store")
    func localOnly() {
        let device = Device(cloud: nil)
        defer { device.cleanup() }
        device.tracker.refresh(systems(["a", "b", "c"]))
        #expect(device.tracker.earned.count == 1)
    }

    // MARK: - Card rows

    @Test("A fresh user sees the first tier of each badge, locked")
    func rowsLocked() {
        let device = Device(cloud: nil)
        defer { device.cleanup() }
        let rows = device.tracker.achievements()
        #expect(rows.map(\.id) == [
            "user.first-install", "user.systems.3", "user.themes.1", "user.alt-layout.1",
            "user.family.1", "user.creators.5", "user.follow.1",
        ])
        #expect(rows.allSatisfy { !$0.isEarned })
        #expect(rows.allSatisfy { !($0.definition.detail ?? "").isEmpty }, "locked rows show what earns them")
    }

    @Test("A tiered badge shows the highest earned and the next goal")
    func rowsTiered() {
        let device = Device(cloud: nil)
        defer { device.cleanup() }
        device.tracker.refresh(systems(["a", "b", "c", "d", "e"]))
        let systemRows = device.tracker.achievements().filter { $0.definition.stem == "user.systems" }
        #expect(systemRows.map(\.id) == ["user.systems.5", "user.systems.10"])
        #expect(systemRows.map(\.isEarned) == [true, false])
        #expect(systemRows.first?.definition.title == "Collector")
    }

    @Test("A badge this build does not define still shows, generically")
    func rowsUnknown() {
        let device = Device(cloud: nil)
        defer { device.cleanup() }
        let data = try! JSONEncoder().encode(["user.something-new": Int64(1_800_000_000_000)])
        device.defaults.set(data, forKey: key)
        let tracker = device.relaunched()
        let row = tracker.achievements().first { $0.id == "user.something-new" }
        #expect(row?.isEarned == true)
        #expect(row?.definition.title == "Something new")
    }

    @Test("Inputs read the shared stores: preferences, follows and themes")
    func gathersInputs() {
        let device = Device(cloud: nil)
        defer { device.cleanup() }
        let (prefsDefaults, cleanup) = TestSupport.makeDefaults()
        defer { cleanup() }
        let preferences = DeltaSkinPreferences(defaults: prefsDefaults)
        preferences.setSelectedSkin("skin-a", for: SkinSystemID("nes"))
        preferences.setSelectedSkin("skin-b", for: SkinSystemID("snes"), orientation: .landscape)
        let follows = CreatorFollowStore(defaults: prefsDefaults, cloud: nil)
        follows.follow("ann")

        let inputs = device.tracker.currentInputs(
            installedRecord: nil,
            installedSkins: [loaded("a"), loaded("ghost")],
            catalog: SkinCatalog(skins: [entry("a")]),
            preferences: preferences,
            follows: follows
        )
        #expect(inputs.installedCatalogIds == ["a"], "only skins the catalog knows")
        #expect(inputs.selectedSkins.count == 2)
        #expect(inputs.followedSlugs == ["ann"])
    }

    @Test("Without a record, installs match the catalog the way the browser does, not by identifier alone")
    func fallbackUsesTheBrowserMatcher() {
        let device = Device(cloud: nil)
        defer { device.cleanup() }
        let (prefsDefaults, cleanup) = TestSupport.makeDefaults()
        defer { cleanup() }
        // The catalog browser saves `a` under its download file name; its info.json identifier differs.
        let inputs = device.tracker.currentInputs(
            installedRecord: nil,
            installedSkins: [loaded("com.example.internal", file: "a.deltaskin")],
            catalog: SkinCatalog(skins: [entry("a"), entry("b")]),
            preferences: DeltaSkinPreferences(defaults: prefsDefaults),
            follows: CreatorFollowStore(defaults: prefsDefaults, cloud: nil)
        )
        #expect(inputs.installedCatalogIds == ["a"])
    }

    @Test("A sideloaded skin's theme counts when the host supplies a record")
    func sideloadedThemeWithRecord() {
        let device = Device(cloud: nil)
        defer { device.cleanup() }
        let (prefsDefaults, cleanup) = TestSupport.makeDefaults()
        defer { cleanup() }
        let sideloaded = "skinkit.tests.sideloaded.\(UUID().uuidString)"
        DeltaSkinThemeSelection.setSelectedThemeId("dark", for: sideloaded)
        defer { DeltaSkinThemeSelection.setSelectedThemeId(nil, for: sideloaded) }
        let record = SkinStoreInstalledRecord(defaults: prefsDefaults)
        record.markInstalled(catalogId: "a", skinIdentifier: "a")

        let inputs = device.tracker.currentInputs(
            installedRecord: record,
            installedSkins: [loaded("a"), loaded(sideloaded)],
            catalog: SkinCatalog(skins: [entry("a")]),
            preferences: DeltaSkinPreferences(defaults: prefsDefaults),
            follows: CreatorFollowStore(defaults: prefsDefaults, cloud: nil)
        )
        #expect(inputs.installedCatalogIds == ["a"], "the install count stays catalog-only")
        #expect(inputs.skinsWithTheme == [sideloaded])
    }
}
