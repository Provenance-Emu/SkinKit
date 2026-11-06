import Foundation
import SkinCatalogKit

/// What the "Your skins" card shows, derived from state the app already stores (gamification spec
/// §3). Nothing here is logged as events: it is recomputed from the inputs whenever it is asked for.
///
/// Pure, so it runs in `swift test` on the host; ``SkinAchievementTracker`` gathers the inputs from
/// the real stores.
public struct SkinUserStats: Sendable, Hashable {
    /// Catalog skins installed. Sideloaded skins are not counted, which keeps the number about the store.
    public var installed = 0
    /// Systems the user has tried: the larger of the systems with a non-default pick in
    /// `DeltaSkinPreferences.selectedSkins` and the distinct systems of the installed catalog skins.
    public var systemsTried = 0
    /// Games with a skin of their own (keys of `gameSpecificSkins`).
    public var gamesCustomised = 0
    /// Skins with a theme selected.
    public var themesUsed = 0
    /// Skins whose alternate layout is on for at least one game.
    public var altLayoutsUsed = 0
    /// Variant families (two or more files) whose every file is installed.
    public var familiesCompleted = 0
    /// Creators followed now (tombstones do not count).
    public var creatorsFollowed = 0
    /// Distinct creators behind the installed catalog skins.
    public var creatorsInstalledFrom = 0

    public init() {}

    /// Everything ``derive(from:)`` reads, as plain values.
    public struct Inputs {
        /// Catalog ids of installed skins (`SkinStoreInstalledRecord.load().keys`).
        public var installedCatalogIds: Set<String>
        /// `DeltaSkinPreferences.selectedSkins`.
        public var selectedSkins: [SkinSystemID: [SkinOrientation: String]]
        /// `DeltaSkinPreferences.gameSpecificSkins`.
        public var gameSpecificSkins: [String: [SkinOrientation: String]]
        /// The skin identifiers that have a theme selected (`DeltaSkinThemeSelection.selectedThemeId(for:)`).
        public var skinsWithTheme: Set<String>
        /// `DeltaSkinPreferences.gameAltRepresentations`.
        public var gameAltRepresentations: [String: Set<String>]
        /// `CreatorFollowStore.followedSlugs`.
        public var followedSlugs: Set<String>
        /// The catalog the store shows (hidden `sample` and `mature` entries already removed), for
        /// families, systems and creators. Nil before it has loaded; those stats are then 0.
        public var catalog: SkinCatalog?
        public var creators: SkinCreatorIndex

        public init(
            installedCatalogIds: Set<String> = [],
            selectedSkins: [SkinSystemID: [SkinOrientation: String]] = [:],
            gameSpecificSkins: [String: [SkinOrientation: String]] = [:],
            skinsWithTheme: Set<String> = [],
            gameAltRepresentations: [String: Set<String>] = [:],
            followedSlugs: Set<String> = [],
            catalog: SkinCatalog? = nil,
            creators: SkinCreatorIndex = .empty
        ) {
            self.installedCatalogIds = installedCatalogIds
            self.selectedSkins = selectedSkins
            self.gameSpecificSkins = gameSpecificSkins
            self.skinsWithTheme = skinsWithTheme
            self.gameAltRepresentations = gameAltRepresentations
            self.followedSlugs = followedSlugs
            self.catalog = catalog
            self.creators = creators
        }
    }

    /// The stats the inputs imply.
    public static func derive(from inputs: Inputs) -> SkinUserStats {
        var stats = SkinUserStats()
        stats.installed = inputs.installedCatalogIds.count

        // A pick of the built-in skin is "no skin": it does not count as trying a system.
        func isRealPick(_ id: String) -> Bool {
            id != DeltaSkinSelectionManager.builtInSkinPreferenceToken
        }
        let pickedSystems = inputs.selectedSkins.filter { $0.value.values.contains(where: isRealPick) }.count

        stats.gamesCustomised = inputs.gameSpecificSkins.filter { $0.value.values.contains(where: isRealPick) }.count
        stats.themesUsed = inputs.skinsWithTheme.count
        stats.altLayoutsUsed = inputs.gameAltRepresentations.values.reduce(into: Set<String>()) { $0.formUnion($1) }.count
        stats.creatorsFollowed = inputs.followedSlugs.count

        var installedSystems = Set<String>()
        var installedCreators = Set<String>()
        if let catalog = inputs.catalog {
            let installedEntries = catalog.skins.filter { inputs.installedCatalogIds.contains($0.id) }
            for entry in installedEntries {
                installedSystems.formUnion(Set(entry.normalizedSystems).subtracting(SkinStorePolicy.defaultPlaceholderSystemCodes))
                if let slug = inputs.creators.slug(for: entry) {
                    installedCreators.insert(slug)
                }
            }
            // A set is a family with several files; it is complete when "Install all" would have
            // nothing left to fetch (a merged member is not required when the split files are in).
            stats.familiesCompleted = catalog.families.filter { family in
                family.isMultiFile && family.installAllMembers(installedIds: inputs.installedCatalogIds).isEmpty
            }.count
        }
        stats.systemsTried = max(pickedSystems, installedSystems.count)
        stats.creatorsInstalledFrom = installedCreators.count
        return stats
    }

    // MARK: - Badges

    /// One user badge and the stat threshold that earns it.
    struct Rule {
        var id: String
        var isMet: (SkinUserStats) -> Bool
    }

    /// The v1 user badges (gamification spec §3). Titles, descriptions and symbols come from the
    /// bundled `badges.json`, not from here; an id the file lacks still resolves to a generic badge.
    static let rules: [Rule] = [
        Rule(id: "user.first-install") { $0.installed >= 1 },
        Rule(id: "user.systems.3") { $0.systemsTried >= 3 },
        Rule(id: "user.systems.5") { $0.systemsTried >= 5 },
        Rule(id: "user.systems.10") { $0.systemsTried >= 10 },
        Rule(id: "user.themes.1") { $0.themesUsed >= 1 },
        Rule(id: "user.alt-layout.1") { $0.altLayoutsUsed >= 1 },
        Rule(id: "user.family.1") { $0.familiesCompleted >= 1 },
        Rule(id: "user.creators.5") { $0.creatorsInstalledFrom >= 5 },
        Rule(id: "user.follow.1") { $0.creatorsFollowed >= 1 },
    ]

    /// The ids of every badge these stats meet, lower tiers included, in rule order.
    public var metBadgeIds: [String] {
        Self.rules.filter { $0.isMet(self) }.map(\.id)
    }
}
