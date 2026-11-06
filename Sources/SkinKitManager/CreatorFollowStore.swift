import Combine
import Foundation

/// One creator the user follows, or used to follow.
///
/// Unfollowing keeps the record and sets ``unfollowedAt`` (a tombstone), so a device that was
/// offline during the unfollow can't bring the follow back when it syncs.
public struct CreatorFollow: Codable, Sendable, Hashable {
    /// The creator slug (`SkinCreator.slug`).
    public var slug: String
    public var followedAt: Date
    /// Present means "not following".
    public var unfollowedAt: Date?

    /// Dates are rounded to the millisecond, the precision they are stored with, so a record
    /// compares equal to its own decoded copy.
    public init(slug: String, followedAt: Date, unfollowedAt: Date? = nil) {
        self.slug = slug
        self.followedAt = Self.rounded(followedAt)
        self.unfollowedAt = unfollowedAt.map(Self.rounded)
    }

    /// Stored as `{"slug": ..., "followedAt": <ms since 1970>, "unfollowedAt": <ms>}`; the last is
    /// absent while following.
    private enum CodingKeys: String, CodingKey {
        case slug, followedAt, unfollowedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            slug: try container.decode(String.self, forKey: .slug),
            followedAt: Self.date(milliseconds: try container.decode(Int64.self, forKey: .followedAt)),
            unfollowedAt: try container.decodeIfPresent(Int64.self, forKey: .unfollowedAt).map(Self.date(milliseconds:))
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(slug, forKey: .slug)
        try container.encode(Self.milliseconds(followedAt), forKey: .followedAt)
        try container.encodeIfPresent(unfollowedAt.map(Self.milliseconds), forKey: .unfollowedAt)
    }

    static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    static func date(milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    static func rounded(_ date: Date) -> Date {
        self.date(milliseconds: milliseconds(date))
    }

    public var isFollowing: Bool {
        unfollowedAt == nil
    }

    /// The time of the latest change: the newer of ``followedAt`` and ``unfollowedAt``.
    public var lastChange: Date {
        if let unfollowedAt, unfollowedAt > followedAt { return unfollowedAt }
        return followedAt
    }

    /// The record that wins a merge: the later change, and on an exact tie the tombstone, so every
    /// replica picks the same one whichever order it merges in.
    static func winner(_ a: CreatorFollow, _ b: CreatorFollow) -> CreatorFollow {
        if a.lastChange != b.lastChange { return a.lastChange > b.lastChange ? a : b }
        if a.isFollowing != b.isFollowing { return a.isFollowing ? b : a }
        return a
    }
}

/// The creators the user follows, kept in `UserDefaults` and mirrored to iCloud key-value storage.
///
/// - Local format: a JSON object `{slug: CreatorFollow}` under ``followsKey``, tombstones included.
/// - Sync: the same JSON under the same key in `cloud`. Merge is per slug, the later change wins
///   (``CreatorFollow/lastChange``), and a tombstone beats a follow with the same timestamp.
///   Tombstones are never dropped: there is at most one record per creator, and an expiry would
///   let a device that stayed offline past it bring an old follow back.
/// - Pass `cloud: nil` (or leave an unentitled app on the default) to run local-only.
///
/// See `docs/specs/2026-11-03-follow-creators-design.md` §2.
@MainActor
public final class CreatorFollowStore: ObservableObject {
    /// Shared instance, backed by `UserDefaults.standard` and the iCloud store when the app has it.
    public static let shared = CreatorFollowStore()

    /// `UserDefaults` / key-value store key for the follow records: `{slug: CreatorFollow}` JSON.
    public nonisolated static let followsKey = "com.provenance.skinkit.creatorFollows.v1"

    /// `UserDefaults` key for the newest effective date the user has seen on the shelf (local only).
    public nonisolated static let shelfSeenKey = "com.provenance.skinkit.creatorFollows.shelfSeen.v1"

    /// Every record by creator slug, unfollowed creators (tombstones) included. Use ``isFollowing(_:)``
    /// or ``followedSlugs`` to ask who is followed.
    @Published public private(set) var follows: [String: CreatorFollow] = [:]

    /// The newest `effectiveDate` the user has looked at on the shelf; entries after it are unseen.
    @Published public private(set) var shelfSeenThrough: Date?

    private let defaults: UserDefaults
    private let cloud: (any KeyValueCloudStore)?
    private let now: @Sendable () -> Date
    private var observation: KeyValueCloudObservation?

    /// - Parameters:
    ///   - defaults: where follows persist. Tests pass an isolated suite.
    ///   - cloud: the synced mirror, or nil to run local-only.
    ///   - now: the clock, for tests.
    public init(
        defaults: UserDefaults = .standard,
        cloud: (any KeyValueCloudStore)? = UbiquitousKeyValueCloudStore.ifEntitled(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.cloud = cloud
        self.now = now
        follows = Self.decode(defaults.data(forKey: Self.followsKey)) ?? [:]
        if defaults.object(forKey: Self.shelfSeenKey) != nil {
            shelfSeenThrough = Date(timeIntervalSince1970: defaults.double(forKey: Self.shelfSeenKey))
        }

        guard let cloud else { return }
        observation = cloud.observeExternalChanges { [weak self] keys in
            guard keys.contains(Self.followsKey) else { return }
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.mergeFromCloud() }
            } else {
                Task { @MainActor in self?.mergeFromCloud() }
            }
        }
        cloud.synchronize()
        mergeFromCloud()
    }

    // MARK: - Queries

    public func isFollowing(_ slug: String) -> Bool {
        follows[slug]?.isFollowing ?? false
    }

    /// The slugs the user follows now.
    public var followedSlugs: Set<String> {
        Set(follows.values.filter(\.isFollowing).map(\.slug))
    }

    // MARK: - Changes

    /// Follows `slug`. A no-op if already followed. After an unfollow it sets a newer `followedAt`
    /// and clears the tombstone, keeping the record.
    public func follow(_ slug: String) {
        guard Self.isValid(slug), !isFollowing(slug) else { return }
        let record = CreatorFollow(slug: slug, followedAt: nextStamp(after: follows[slug]))
        follows[slug] = record
        persistAndPush()
    }

    /// Unfollows `slug`, leaving a tombstone. A no-op if not followed.
    public func unfollow(_ slug: String) {
        guard var record = follows[slug], record.isFollowing else { return }
        record.unfollowedAt = nextStamp(after: record)
        follows[slug] = record
        persistAndPush()
    }

    /// Records that the user has seen the shelf up to `newest`, the newest `effectiveDate` it showed.
    /// Only moves forward.
    public func markShelfSeen(through newest: Date) {
        if let current = shelfSeenThrough, current >= newest { return }
        shelfSeenThrough = newest
        defaults.set(newest.timeIntervalSince1970, forKey: Self.shelfSeenKey)
    }

    /// Folds in what the cloud store holds now. Runs at launch and on every external change; apps
    /// can also call it when they come to the foreground.
    public func mergeFromCloud() {
        guard let cloud else { return }
        let remote = Self.decode(cloud.data(forKey: Self.followsKey))
        let merged = Self.merge(follows, remote ?? [:])
        if merged != follows {
            follows = merged
            persistLocal()
        }
        // Push when the cloud copy is missing, unreadable, or behind what we hold.
        if remote != merged {
            pushToCloud()
        }
    }

    // MARK: - Merge

    /// Per-slug merge of two replicas. Commutative, associative and idempotent, so replicas converge
    /// whatever order they meet in.
    nonisolated static func merge(_ a: [String: CreatorFollow], _ b: [String: CreatorFollow]) -> [String: CreatorFollow] {
        a.merging(b) { CreatorFollow.winner($0, $1) }
    }

    // MARK: - Internals

    private static func isValid(_ slug: String) -> Bool {
        !slug.isEmpty && slug == slug.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The time for a new change: now, but always after the record's last change so a quick
    /// follow, unfollow, follow sequence keeps its order even when the clock hasn't moved.
    private func nextStamp(after record: CreatorFollow?) -> Date {
        let current = CreatorFollow.rounded(now())
        guard let record else { return current }
        return CreatorFollow.rounded(max(current, record.lastChange.addingTimeInterval(0.001)))
    }

    private func persistAndPush() {
        persistLocal()
        pushToCloud()
    }

    private func persistLocal() {
        guard let data = Self.encode(follows) else { return }
        defaults.set(data, forKey: Self.followsKey)
    }

    private func pushToCloud() {
        guard let cloud, let data = Self.encode(follows) else { return }
        cloud.setData(data, forKey: Self.followsKey)
        cloud.synchronize()
    }

    private static func encode(_ follows: [String: CreatorFollow]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(follows)
    }

    private static func decode(_ data: Data?) -> [String: CreatorFollow]? {
        guard let data else { return nil }
        return try? JSONDecoder().decode([String: CreatorFollow].self, from: data)
    }
}
