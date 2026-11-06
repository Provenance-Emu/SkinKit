import Combine
import Foundation
import SkinCatalogKit
import SkinKitCore

/// One row of the "Your skins" card: a badge and, when it is earned, the day it was.
public struct SkinAchievement: Sendable, Hashable, Identifiable {
    public var definition: SkinBadgeDefinition
    /// Nil while the badge is locked.
    public var earnedAt: Date?

    public var id: String { definition.id }
    public var isEarned: Bool { earnedAt != nil }
}

/// The user's private badges (gamification spec §3): live stats derived from what the app stores, and
/// the dates the badges were first earned.
///
/// - Stats are recomputed on ``refresh(_:)``, never logged. The inputs are `SkinUserStats.Inputs`;
///   ``currentInputs(installedRecord:installedSkins:catalog:creators:preferences:follows:)`` gathers them from the shared stores.
/// - Earned dates are `{badgeId: earnedAt}` JSON under ``earnedKey`` in `UserDefaults`, mirrored to the
///   iCloud key-value store the follow design adds, so a reinstall keeps them. Merging two replicas
///   keeps every badge and the earlier date of each. **Nothing is ever revoked**: uninstalling a skin
///   does not un-earn "Explorer".
/// - No popup is raised here. ``recentlyEarned`` lists the badges a refresh just earned for a host
///   that opts in to toasts.
///
/// See `docs/specs/2026-11-03-gamification-design.md` §3.
@MainActor
public final class SkinAchievementTracker: ObservableObject {
    /// Shared instance, backed by `UserDefaults.standard` and the iCloud store when the app has it.
    public static let shared = SkinAchievementTracker()

    /// `UserDefaults` / key-value store key for the earned map: `{badgeId: <ms since 1970>}` JSON.
    public nonisolated static let earnedKey = "com.provenance.skinkit.achievements.v1"

    /// The date each badge was first earned. Only grows.
    @Published public private(set) var earned: [String: Date] = [:]

    /// The stats at the last ``refresh(_:)``.
    @Published public private(set) var stats = SkinUserStats()

    /// Badges the last refresh that earned anything earned (empty after a refresh that earned nothing,
    /// and after ``acknowledgeRecentlyEarned()``). For the toast flag; the card never reads it.
    @Published public private(set) var recentlyEarned: [SkinBadgeDefinition] = []

    public let badges: SkinBadgeCatalog

    private let defaults: UserDefaults
    private let cloud: (any KeyValueCloudStore)?
    private let now: @Sendable () -> Date
    private var observation: KeyValueCloudObservation?

    /// - Parameters:
    ///   - defaults: where the earned dates persist. Tests pass an isolated suite.
    ///   - cloud: the synced mirror, or nil to run local-only.
    ///   - badges: the definitions, bundled `badges.json` by default.
    ///   - now: the clock, for tests.
    public init(
        defaults: UserDefaults = .standard,
        cloud: (any KeyValueCloudStore)? = UbiquitousKeyValueCloudStore.ifEntitled(),
        badges: SkinBadgeCatalog = .bundled,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.cloud = cloud
        self.badges = badges
        self.now = now
        earned = Self.decode(defaults.data(forKey: Self.earnedKey)) ?? [:]

        guard let cloud else { return }
        observation = cloud.observeExternalChanges { [weak self] keys in
            guard keys.contains(Self.earnedKey) else { return }
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.mergeFromCloud() }
            } else {
                Task { @MainActor in self?.mergeFromCloud() }
            }
        }
        cloud.synchronize()
        mergeFromCloud()
    }

    // MARK: - Refresh

    /// Recomputes the stats from `inputs` and records any badge they newly earn.
    ///
    /// - Returns: the ids earned by this call, in rule order.
    @discardableResult
    public func refresh(_ inputs: SkinUserStats.Inputs) -> [String] {
        let fresh = SkinUserStats.derive(from: inputs)
        if fresh != stats { stats = fresh }

        let stamp = SkinAchievementTracker.rounded(now())
        let newIds = fresh.metBadgeIds.filter { earned[$0] == nil }
        guard !newIds.isEmpty else {
            if !recentlyEarned.isEmpty { recentlyEarned = [] }
            return []
        }
        for id in newIds {
            earned[id] = stamp
        }
        recentlyEarned = newIds.map(badges.resolve(_:))
        persistAndPush()
        return newIds
    }

    /// The inputs from the shared stores.
    ///
    /// - Parameters:
    ///   - installedRecord: the app's `SkinStoreInstalledRecord`. Nil falls back to the catalog entries
    ///     that ``matchingInstalledSkin(for:in:)`` finds among `installedSkins`, the way the catalog
    ///     browser marks an entry installed.
    ///   - installedSkins: the loaded skins. Their identifiers are always theme candidates, so a
    ///     sideloaded skin's theme counts whether or not a record is supplied.
    ///   - catalog: the catalog the store shows, hidden `sample` and `mature` entries removed.
    public func currentInputs(
        installedRecord: SkinStoreInstalledRecord?,
        installedSkins: [any DeltaSkinProtocol] = [],
        catalog: SkinCatalog?,
        creators: SkinCreatorIndex = .empty,
        preferences: DeltaSkinPreferences? = nil,
        follows: CreatorFollowStore? = nil
    ) -> SkinUserStats.Inputs {
        let preferences = preferences ?? .shared
        let follows = follows ?? .shared
        let installedIds: Set<String>
        var candidates = Set(installedSkins.map(\.identifier))
        if let installedRecord {
            let record = installedRecord.load()
            installedIds = Set(record.keys)
            candidates.formUnion(record.values)
        } else if let catalog, !installedSkins.isEmpty {
            // A catalog id can differ from the skin's `info.json` identifier, so match the way the
            // browser does (identifier, file name, then name) rather than by identifier alone.
            installedIds = Set(catalog.skins.lazy
                .filter { matchingInstalledSkin(for: $0, in: installedSkins) != nil }
                .map(\.id))
        } else {
            installedIds = []
        }

        // A theme is stored per skin, so look at the skins that could have one: the loaded and
        // installed ones, and the ones picked for a system or a game.
        for picks in preferences.selectedSkins.values { candidates.formUnion(picks.values) }
        for picks in preferences.gameSpecificSkins.values { candidates.formUnion(picks.values) }
        let themed = candidates.filter {
            $0 != DeltaSkinSelectionManager.builtInSkinPreferenceToken
                && DeltaSkinThemeSelection.selectedThemeId(for: $0) != nil
        }

        return SkinUserStats.Inputs(
            installedCatalogIds: installedIds,
            selectedSkins: preferences.selectedSkins,
            gameSpecificSkins: preferences.gameSpecificSkins,
            skinsWithTheme: Set(themed),
            gameAltRepresentations: preferences.gameAltRepresentations,
            followedSlugs: follows.followedSlugs,
            catalog: catalog,
            creators: creators
        )
    }

    /// Clears ``recentlyEarned`` once a host has shown it.
    public func acknowledgeRecentlyEarned() {
        if !recentlyEarned.isEmpty { recentlyEarned = [] }
    }

    // MARK: - Display

    /// The rows of the card, in `badges.json` order.
    ///
    /// A tiered stem (`user.systems.3`, `.5`, `.10`) shows the highest earned tier, then the next tier
    /// as a locked goal; a stem nothing is earned on shows its lowest tier locked (spec §1: the UI shows
    /// only the highest earned). Untiered badges are one row each. A badge the user earned that this
    /// build's `badges.json` does not know shows as a generic badge.
    public func achievements() -> [SkinAchievement] {
        let defined = badges.definitions(for: .user)
        var byStem: [String: [SkinBadgeDefinition]] = [:]
        var stemOrder: [String] = []
        for definition in defined {
            if byStem[definition.stem] == nil { stemOrder.append(definition.stem) }
            byStem[definition.stem, default: []].append(definition)
        }

        var rows: [SkinAchievement] = []
        for stem in stemOrder {
            let tiers = (byStem[stem] ?? []).sorted { ($0.threshold ?? 0) < ($1.threshold ?? 0) }
            let earnedTiers = tiers.filter { earned[$0.id] != nil }
            if let highest = earnedTiers.last {
                rows.append(SkinAchievement(definition: highest, earnedAt: earned[highest.id]))
            }
            if let next = tiers.first(where: { earned[$0.id] == nil }) {
                rows.append(SkinAchievement(definition: next, earnedAt: nil))
            }
        }

        let known = Set(defined.map(\.id))
        let unknown = earned.filter { $0.key.hasPrefix("user.") && !known.contains($0.key) }
            .sorted { ($0.value, $0.key) < ($1.value, $1.key) }
        rows += unknown.map { SkinAchievement(definition: badges.resolve($0.key), earnedAt: $0.value) }
        return rows
    }

    // MARK: - Sync

    /// Folds in what the cloud store holds now. Runs at launch and on every external change.
    public func mergeFromCloud() {
        guard let cloud else { return }
        let remote = Self.decode(cloud.data(forKey: Self.earnedKey))
        let merged = Self.merge(earned, remote ?? [:])
        if merged != earned {
            earned = merged
            persistLocal()
        }
        // Push when the cloud copy is missing, unreadable, or behind what we hold.
        if remote != merged {
            pushToCloud()
        }
    }

    /// Union of two replicas, keeping the earlier date of a badge both have. Commutative, associative
    /// and idempotent, and it never drops a badge, so a stale replica can't revoke one.
    nonisolated static func merge(_ a: [String: Date], _ b: [String: Date]) -> [String: Date] {
        a.merging(b) { min($0, $1) }
    }

    // MARK: - Internals

    private func persistAndPush() {
        persistLocal()
        pushToCloud()
    }

    private func persistLocal() {
        guard let data = Self.encode(earned) else { return }
        defaults.set(data, forKey: Self.earnedKey)
    }

    private func pushToCloud() {
        guard let cloud, let data = Self.encode(earned) else { return }
        cloud.setData(data, forKey: Self.earnedKey)
        cloud.synchronize()
    }

    /// Dates are kept to the millisecond, the precision they are stored with.
    nonisolated static func rounded(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000)
    }

    private static func encode(_ earned: [String: Date]) -> Data? {
        let milliseconds = earned.mapValues { Int64(($0.timeIntervalSince1970 * 1000).rounded()) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(milliseconds)
    }

    private static func decode(_ data: Data?) -> [String: Date]? {
        guard let data, let raw = try? JSONDecoder().decode([String: Int64].self, from: data) else { return nil }
        return raw.mapValues { Date(timeIntervalSince1970: Double($0) / 1000) }
    }
}
