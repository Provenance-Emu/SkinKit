import Foundation

/// The "New from creators you follow" shelf (follow creators spec §3): the skins of the creators
/// the user follows that the store can install and the user does not have yet, newest first, one
/// item per variant family.
///
/// Pure, so the shelf's logic runs in `swift test` on the host and can be checked against the same
/// fixture as the website's. The SwiftUI side only draws ``items``.
public struct SkinFollowFeed: Sendable {
    /// One card on the shelf: a whole variant family with at least one member that is new to the user.
    public struct Item: Sendable, Hashable, Identifiable {
        public var family: SkinFamily
        /// The family's members that made it onto the shelf (the followed creators', not installed).
        /// The rest of the family is shown on the card but is not what is new.
        public var newMembers: [SkinCatalogEntry]
        /// The followed creators behind ``newMembers``, in member order, one per slug.
        public var creatorSlugs: [String]
        /// The newest ``SkinCatalogEntry/effectiveDate`` among ``newMembers``. Nil when none has one.
        public var effectiveDate: Date?
        /// ``effectiveDate`` is after the `since` the feed was built with (any date counts when there
        /// was none). An undated item is never unseen: nothing says when it appeared.
        public var isUnseen: Bool

        public var id: String { family.id }
    }

    /// Newest first; items without a date last, in catalog order.
    public let items: [Item]

    /// Items that are unseen: what the shelf's badge shows.
    public var unseenCount: Int { items.filter(\.isUnseen).count }

    /// The newest date on the shelf, to hand to `CreatorFollowStore.markShelfSeen(through:)` when the
    /// user opens it. Nil when no item has a date.
    public var newestDate: Date? { items.compactMap(\.effectiveDate).max() }

    public var isEmpty: Bool { items.isEmpty }

    public init(items: [Item]) {
        self.items = items
    }

    /// Builds the shelf.
    ///
    /// - Parameters:
    ///   - catalog: the whole catalog. Families and their labels come from all of it.
    ///   - creators: the creator directory, so an entry resolves to its creator the way the profile
    ///     sheet does (the catalog's `creator`, then aliases, then the local slug of its `author`).
    ///   - following: the slugs the user follows now (`CreatorFollowStore.followedSlugs`).
    ///   - since: the newest date the user has seen on the shelf (`CreatorFollowStore.shelfSeenThrough`).
    ///     Nil means the shelf was never opened, so every dated item is unseen.
    ///   - installed: catalog ids already installed. An installed entry is not new, but its family
    ///     keeps its place on the shelf while another followed member is not installed.
    ///   - policy: the host store's policy: what it can install and shows. Nil applies only the
    ///     app-wide ``SkinContentVisibility``, like the plain catalog browser.
    public static func make(
        in catalog: SkinCatalog,
        creators: SkinCreatorIndex = .empty,
        following: Set<String>,
        since: Date?,
        installed: Set<String>,
        policy: SkinStorePolicy? = nil
    ) -> SkinFollowFeed {
        guard !following.isEmpty else { return SkinFollowFeed(items: []) }

        let eligible: [SkinCatalogEntry]
        if let policy {
            eligible = catalog.skins.filter { policy.section(for: $0) != nil }
        } else {
            eligible = SkinContentVisibility.current.filter(catalog.skins)
        }

        var slugs: [String: String] = [:]
        var matches: [SkinCatalogEntry] = []
        for entry in eligible where !installed.contains(entry.id) {
            guard let slug = creators.slug(for: entry), following.contains(slug) else { continue }
            slugs[entry.id] = slug
            matches.append(entry)
        }
        guard !matches.isEmpty else { return SkinFollowFeed(items: []) }

        // Families come out whole (every eligible member), as on every other card.
        let families = catalog.familyIndex.families(containing: matches, in: eligible)

        let built = families.map { family -> Item in
            let new = family.members.filter { slugs[$0.id] != nil }
            var seen = Set<String>()
            let creatorSlugs = new.compactMap { slugs[$0.id] }.filter { seen.insert($0).inserted }
            let date = new.compactMap(\.effectiveDate).max()
            let isUnseen: Bool
            if let date {
                isUnseen = since.map { date > $0 } ?? true
            } else {
                isUnseen = false
            }
            return Item(
                family: family,
                newMembers: new,
                creatorSlugs: creatorSlugs,
                effectiveDate: date,
                isUnseen: isUnseen
            )
        }

        // `sorted` is not stable, so break ties on position.
        let ordered = built.enumerated().sorted { lhs, rhs in
            switch (lhs.element.effectiveDate, rhs.element.effectiveDate) {
            case let (l?, r?) where l != r: return l > r
            case (.some, nil): return true
            case (nil, .some): return false
            default: return lhs.offset < rhs.offset
            }
        }.map(\.element)
        return SkinFollowFeed(items: ordered)
    }
}
