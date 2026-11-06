import Foundation
import Testing
@testable import SkinKitManager

/// A settable clock the stores read.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) {
        current = start
    }

    var now: Date {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

private let day: TimeInterval = 86_400
private let epoch = Date(timeIntervalSince1970: 1_800_000_000)
private let key = CreatorFollowStore.followsKey

/// A device: its own `UserDefaults`, its own clock and a replica of the shared cloud store.
@MainActor
private struct Device {
    let store: CreatorFollowStore
    let defaults: UserDefaults
    let cloud: InMemoryKeyValueCloudStore?
    let clock: TestClock
    let cleanup: () -> Void

    init(cloud: InMemoryKeyValueCloudStore?, start: Date = epoch) {
        (defaults, cleanup) = TestSupport.makeDefaults()
        self.cloud = cloud
        clock = TestClock(start)
        let clock = self.clock
        store = CreatorFollowStore(defaults: defaults, cloud: cloud, now: { clock.now })
    }

    /// A new launch of the same device: same defaults and cloud replica, fresh store object.
    func relaunched() -> CreatorFollowStore {
        let clock = self.clock
        return CreatorFollowStore(defaults: defaults, cloud: cloud, now: { clock.now })
    }
}

@Suite("CreatorFollowStore")
@MainActor
struct CreatorFollowStoreTests {
    // MARK: - Local behaviour

    @Test("Keys follow the DeltaSkinPreferences style")
    func keys() {
        #expect(CreatorFollowStore.followsKey == "com.provenance.skinkit.creatorFollows.v1")
        #expect(CreatorFollowStore.shelfSeenKey == "com.provenance.skinkit.creatorFollows.shelfSeen.v1")
    }

    @Test("Follow and unfollow")
    func followAndUnfollow() {
        let device = Device(cloud: nil)
        defer { device.cleanup() }
        let store = device.store

        #expect(!store.isFollowing("aphaits"))
        store.follow("aphaits")
        store.follow("litritt")
        #expect(store.isFollowing("aphaits"))
        #expect(store.followedSlugs == ["aphaits", "litritt"])

        device.clock.advance(60)
        store.unfollow("aphaits")
        #expect(!store.isFollowing("aphaits"))
        #expect(store.isFollowing("litritt"))
        #expect(store.followedSlugs == ["litritt"])
    }

    @Test("Unfollow keeps a tombstone and unfollowing a stranger records nothing")
    func unfollowLeavesTombstone() throws {
        let device = Device(cloud: nil)
        defer { device.cleanup() }
        let store = device.store

        store.unfollow("nobody")
        #expect(store.follows.isEmpty)

        store.follow("aphaits")
        device.clock.advance(60)
        store.unfollow("aphaits")
        let record = try #require(store.follows["aphaits"])
        #expect(record.followedAt == epoch)
        #expect(record.unfollowedAt == epoch.addingTimeInterval(60))
        #expect(!record.isFollowing)
    }

    @Test("Following twice and unfollowing twice change nothing")
    func idempotent() {
        let device = Device(cloud: nil)
        defer { device.cleanup() }
        let store = device.store

        store.follow("aphaits")
        let first = store.follows
        device.clock.advance(60)
        store.follow("aphaits")
        #expect(store.follows == first)

        store.unfollow("aphaits")
        let second = store.follows
        device.clock.advance(60)
        store.unfollow("aphaits")
        #expect(store.follows == second)
    }

    @Test("Re-following after an unfollow sets a newer followedAt and clears the tombstone")
    func refollowAfterUnfollow() throws {
        let device = Device(cloud: nil)
        defer { device.cleanup() }
        let store = device.store

        store.follow("aphaits")
        device.clock.advance(day)
        store.unfollow("aphaits")
        device.clock.advance(day)
        store.follow("aphaits")

        let record = try #require(store.follows["aphaits"])
        #expect(store.isFollowing("aphaits"))
        #expect(record.unfollowedAt == nil)
        #expect(record.followedAt == epoch.addingTimeInterval(2 * day))
        #expect(store.follows.count == 1)
    }

    @Test("Follow, unfollow and follow within one clock tick keep their order")
    func sameInstantToggles() throws {
        let device = Device(cloud: nil)
        defer { device.cleanup() }
        let store = device.store

        store.follow("aphaits")
        store.unfollow("aphaits")
        let tombstone = try #require(store.follows["aphaits"])
        #expect(tombstone.lastChange > tombstone.followedAt)

        store.follow("aphaits")
        let refollowed = try #require(store.follows["aphaits"])
        #expect(refollowed.followedAt > tombstone.lastChange)
        #expect(store.isFollowing("aphaits"))
    }

    @Test("Empty and padded slugs are ignored")
    func invalidSlugs() {
        let device = Device(cloud: nil)
        defer { device.cleanup() }
        device.store.follow("")
        device.store.follow(" aphaits")
        device.store.follow("aphaits\n")
        #expect(device.store.follows.isEmpty)
    }

    @Test("Follows persist across launches, tombstones included")
    func persists() throws {
        let device = Device(cloud: nil)
        defer { device.cleanup() }
        device.store.follow("aphaits")
        device.store.follow("litritt")
        device.clock.advance(60)
        device.store.unfollow("litritt")

        let reloaded = device.relaunched()
        #expect(reloaded.follows == device.store.follows)
        #expect(reloaded.isFollowing("aphaits"))
        #expect(!reloaded.isFollowing("litritt"))
        #expect(reloaded.follows["litritt"]?.unfollowedAt != nil)
    }

    @Test("The stored format is {slug: record} JSON with millisecond dates")
    func storedFormat() throws {
        let device = Device(cloud: nil)
        defer { device.cleanup() }
        device.store.follow("aphaits")
        device.clock.advance(1.5)
        device.store.follow("litritt")
        device.clock.advance(1)
        device.store.unfollow("litritt")

        let data = try #require(device.defaults.data(forKey: key))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: [String: Any]])
        #expect(Set(object.keys) == ["aphaits", "litritt"])
        #expect(object["aphaits"]?["slug"] as? String == "aphaits")
        #expect(object["aphaits"]?["followedAt"] as? Int64 == 1_800_000_000_000)
        #expect(object["aphaits"]?["unfollowedAt"] == nil)
        #expect(object["litritt"]?["followedAt"] as? Int64 == 1_800_000_001_500)
        #expect(object["litritt"]?["unfollowedAt"] as? Int64 == 1_800_000_002_500)
    }

    @Test("Unreadable stored data starts empty instead of crashing")
    func corruptLocalData() {
        let (defaults, cleanup) = TestSupport.makeDefaults()
        defer { cleanup() }
        defaults.set(Data("not json".utf8), forKey: key)
        let store = CreatorFollowStore(defaults: defaults, cloud: nil)
        #expect(store.follows.isEmpty)
        store.follow("aphaits")
        #expect(store.isFollowing("aphaits"))
    }

    @Test("Local-only mode never needs a cloud store")
    func localOnly() {
        let device = Device(cloud: nil)
        defer { device.cleanup() }
        device.store.follow("aphaits")
        device.store.mergeFromCloud()
        #expect(device.store.isFollowing("aphaits"))
    }

    @Test("markShelfSeen only moves forward and persists")
    func shelfSeen() {
        let (defaults, cleanup) = TestSupport.makeDefaults()
        defer { cleanup() }
        let store = CreatorFollowStore(defaults: defaults, cloud: nil)
        #expect(store.shelfSeenThrough == nil)

        store.markShelfSeen(through: epoch)
        store.markShelfSeen(through: epoch.addingTimeInterval(-day))
        #expect(store.shelfSeenThrough == epoch)
        store.markShelfSeen(through: epoch.addingTimeInterval(day))

        let reloaded = CreatorFollowStore(defaults: defaults, cloud: nil)
        #expect(reloaded.shelfSeenThrough == epoch.addingTimeInterval(day))
    }

    // MARK: - Merge

    @Test("The later change wins for each slug")
    func mergeLastWriterWins() {
        let old = CreatorFollow(slug: "a", followedAt: epoch)
        let newer = CreatorFollow(slug: "a", followedAt: epoch, unfollowedAt: epoch.addingTimeInterval(day))
        let newest = CreatorFollow(slug: "a", followedAt: epoch.addingTimeInterval(2 * day))

        #expect(CreatorFollowStore.merge(["a": old], ["a": newer]) == ["a": newer])
        #expect(CreatorFollowStore.merge(["a": newer], ["a": old]) == ["a": newer])
        #expect(CreatorFollowStore.merge(["a": newer], ["a": newest]) == ["a": newest])
        #expect(CreatorFollowStore.merge(["a": newest], ["a": newer]) == ["a": newest])
    }

    @Test("A tombstone beats a follow with the same timestamp, in either order")
    func mergeTieGoesToTombstone() {
        let follow = CreatorFollow(slug: "a", followedAt: epoch.addingTimeInterval(day))
        let tombstone = CreatorFollow(slug: "a", followedAt: epoch, unfollowedAt: epoch.addingTimeInterval(day))
        #expect(CreatorFollowStore.merge(["a": follow], ["a": tombstone]) == ["a": tombstone])
        #expect(CreatorFollowStore.merge(["a": tombstone], ["a": follow]) == ["a": tombstone])
    }

    @Test("Merge keeps slugs that only one side has, and is commutative and idempotent")
    func mergeProperties() {
        let a = ["x": CreatorFollow(slug: "x", followedAt: epoch), "y": CreatorFollow(slug: "y", followedAt: epoch)]
        let b = [
            "y": CreatorFollow(slug: "y", followedAt: epoch, unfollowedAt: epoch.addingTimeInterval(day)),
            "z": CreatorFollow(slug: "z", followedAt: epoch),
        ]
        let ab = CreatorFollowStore.merge(a, b)
        #expect(Set(ab.keys) == ["x", "y", "z"])
        #expect(ab == CreatorFollowStore.merge(b, a))
        #expect(CreatorFollowStore.merge(ab, a) == ab)
        #expect(CreatorFollowStore.merge(ab, b) == ab)
        #expect(CreatorFollowStore.merge(ab, ab) == ab)
        #expect(ab["y"]?.isFollowing == false)
    }

    // MARK: - Sync

    @Test("A follow on one device appears on a second signed into the same account")
    func followReachesSecondDevice() {
        let cloud = InMemoryKeyValueCloudStore()
        let phone = Device(cloud: cloud)
        let pad = Device(cloud: cloud.replica())
        defer { phone.cleanup(); pad.cleanup() }

        phone.store.follow("aphaits")
        #expect(pad.store.isFollowing("aphaits"))
        #expect(pad.store.follows == phone.store.follows)

        pad.clock.advance(day)
        pad.store.unfollow("aphaits")
        #expect(!phone.store.isFollowing("aphaits"))
    }

    @Test("A device that launches later picks up what the cloud holds, and the cloud picks up what it holds")
    func launchMerge() {
        let cloud = InMemoryKeyValueCloudStore()
        let phone = Device(cloud: cloud)
        defer { phone.cleanup() }
        phone.store.follow("aphaits")

        let pad = Device(cloud: cloud.replica())
        defer { pad.cleanup() }
        #expect(pad.store.isFollowing("aphaits"))

        // Local follows made before iCloud was on reach the cloud at the next launch.
        let (defaults, cleanup) = TestSupport.makeDefaults()
        defer { cleanup() }
        let offlineStore = CreatorFollowStore(defaults: defaults, cloud: nil, now: { epoch.addingTimeInterval(day) })
        offlineStore.follow("litritt")
        let enabled = CreatorFollowStore(defaults: defaults, cloud: cloud.replica())
        #expect(enabled.followedSlugs == ["aphaits", "litritt"])
        #expect(phone.store.followedSlugs == ["aphaits", "litritt"])
    }

    @Test("Edits made on two devices while apart both survive")
    func concurrentEditsOnDifferentCreators() {
        let cloud = InMemoryKeyValueCloudStore()
        let phone = Device(cloud: cloud)
        let pad = Device(cloud: nil) // offline
        defer { phone.cleanup(); pad.cleanup() }

        phone.store.follow("aphaits")
        pad.store.follow("litritt")

        // The pad gets online: it launches with its saved follows and finds the cloud's.
        let padOnline = CreatorFollowStore(defaults: pad.defaults, cloud: cloud.replica())
        #expect(padOnline.followedSlugs == ["aphaits", "litritt"])
        #expect(phone.store.followedSlugs == ["aphaits", "litritt"])
    }

    @Test("A stale follow does not undo an unfollow made elsewhere")
    func staleFollowLosesToTombstone() {
        let cloud = InMemoryKeyValueCloudStore()
        let phone = Device(cloud: cloud)
        let pad = Device(cloud: cloud.replica())
        defer { phone.cleanup(); pad.cleanup() }

        phone.store.follow("aphaits")
        #expect(pad.store.isFollowing("aphaits"))

        // The pad stops syncing, the phone unfollows a day later.
        let staleBlob = pad.defaults.data(forKey: key)
        phone.clock.advance(day)
        phone.store.unfollow("aphaits")

        // The pad comes back from its stale saved copy.
        pad.defaults.set(staleBlob, forKey: key)
        let padLater = pad.relaunched()
        #expect(!padLater.isFollowing("aphaits"))
        #expect(!phone.store.isFollowing("aphaits"))
    }

    @Test("A replica offline for a year loses to a tombstone, however it comes back")
    func replicaOfflineForAYear() throws {
        let cloud = InMemoryKeyValueCloudStore()
        let phone = Device(cloud: cloud)
        defer { phone.cleanup() }

        // Both devices follow two creators; the pad then goes offline holding that copy.
        phone.store.follow("aphaits")
        phone.store.follow("litritt")
        let padSavedBlob = try #require(phone.defaults.data(forKey: key))

        // A month later the phone unfollows aphaits; a year goes by with nothing else changing.
        phone.clock.advance(30 * day)
        phone.store.unfollow("aphaits")
        let tombstone = try #require(phone.store.follows["aphaits"])
        let phoneBlob = try #require(cloud.data(forKey: key))

        // Back online a year later, launching with the old copy.
        let (launchDefaults, cleanupLaunch) = TestSupport.makeDefaults()
        defer { cleanupLaunch() }
        launchDefaults.set(padSavedBlob, forKey: key)
        let launched = CreatorFollowStore(
            defaults: launchDefaults, cloud: cloud.replica(), now: { epoch.addingTimeInterval(365 * day) }
        )
        #expect(!launched.isFollowing("aphaits"))
        #expect(launched.isFollowing("litritt"))
        #expect(launched.follows["aphaits"] == tombstone)

        // Or already running with the old copy when the phone's write arrives.
        let staleCloud = InMemoryKeyValueCloudStore()
        staleCloud.setData(padSavedBlob, forKey: key)
        let (runningDefaults, cleanupRunning) = TestSupport.makeDefaults()
        defer { cleanupRunning() }
        let running = CreatorFollowStore(defaults: runningDefaults, cloud: staleCloud, now: { epoch.addingTimeInterval(365 * day) })
        #expect(running.isFollowing("aphaits"))
        staleCloud.replica().setData(phoneBlob, forKey: key)
        #expect(!running.isFollowing("aphaits"))
        #expect(running.follows["aphaits"] == tombstone)

        // And the old copy arriving at the phone never resurrects it; the phone corrects the cloud.
        cloud.replica().setData(padSavedBlob, forKey: key)
        #expect(!phone.store.isFollowing("aphaits"))
        #expect(phone.store.follows["aphaits"] == tombstone)
        let repaired = try JSONDecoder().decode([String: CreatorFollow].self, from: try #require(cloud.data(forKey: key)))
        #expect(repaired["aphaits"] == tombstone)
    }

    @Test("Following again after the tombstone wins everywhere")
    func refollowSyncs() {
        let cloud = InMemoryKeyValueCloudStore()
        let phone = Device(cloud: cloud)
        let pad = Device(cloud: cloud.replica())
        defer { phone.cleanup(); pad.cleanup() }

        phone.store.follow("aphaits")
        phone.clock.advance(day)
        phone.store.unfollow("aphaits")
        #expect(!pad.store.isFollowing("aphaits"))

        pad.clock.advance(2 * day)
        pad.store.follow("aphaits")
        #expect(phone.store.isFollowing("aphaits"))
        #expect(phone.store.follows["aphaits"]?.unfollowedAt == nil)
        #expect(phone.store.follows == pad.store.follows)
    }

    @Test("A stale cloud copy is corrected from a newer local one")
    func newerLocalPushesBack() throws {
        let cloud = InMemoryKeyValueCloudStore()
        let phone = Device(cloud: cloud)
        defer { phone.cleanup() }
        phone.store.follow("aphaits")
        phone.clock.advance(day)
        phone.store.unfollow("aphaits")

        // Something old lands in the cloud (a device that synced late).
        let old = ["aphaits": CreatorFollow(slug: "aphaits", followedAt: epoch)]
        cloud.replica().setData(try JSONEncoder().encode(old), forKey: key)

        #expect(!phone.store.isFollowing("aphaits"))
        let repaired = try JSONDecoder().decode([String: CreatorFollow].self, from: try #require(cloud.data(forKey: key)))
        #expect(repaired["aphaits"]?.isFollowing == false)
    }

    @Test("Changes to other keys are ignored")
    func ignoresOtherKeys() {
        let cloud = InMemoryKeyValueCloudStore()
        let phone = Device(cloud: cloud)
        defer { phone.cleanup() }
        let before = cloud.synchronizeCount
        cloud.deliver(["some.other.key"])
        #expect(cloud.synchronizeCount == before)
        #expect(phone.store.follows.isEmpty)
    }

    @Test("An unreadable cloud blob is replaced by the local copy")
    func corruptCloudData() {
        let cloud = InMemoryKeyValueCloudStore()
        cloud.setData(Data("garbage".utf8), forKey: key)
        let phone = Device(cloud: cloud)
        defer { phone.cleanup() }
        phone.store.follow("aphaits")

        let other = Device(cloud: cloud.replica())
        defer { other.cleanup() }
        #expect(other.store.isFollowing("aphaits"))
    }

    @Test("Launch syncs once and a follow syncs after writing")
    func asksToSynchronize() {
        let cloud = InMemoryKeyValueCloudStore()
        let phone = Device(cloud: cloud)
        defer { phone.cleanup() }
        #expect(cloud.synchronizeCount >= 1)
        let launched = cloud.synchronizeCount
        phone.store.follow("aphaits")
        #expect(cloud.synchronizeCount > launched)
    }

    @Test("A released store stops listening")
    func releasedStoreStopsObserving() {
        let cloud = InMemoryKeyValueCloudStore()
        let (defaults, cleanup) = TestSupport.makeDefaults()
        defer { cleanup() }
        weak var weakStore: CreatorFollowStore?
        do {
            let store = CreatorFollowStore(defaults: defaults, cloud: cloud)
            weakStore = store
        }
        #expect(weakStore == nil)
        cloud.deliver([key])
    }
}
