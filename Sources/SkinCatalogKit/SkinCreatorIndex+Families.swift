import Foundation

/// What the creator profile sheet lists (creator profiles spec §7): a creator's skins as variant
/// families, cut by the host store's policy. Pure, so the sheet's logic runs in `swift test` on the
/// host; the SwiftUI side only draws the result.
public extension SkinCreatorIndex {
    /// The credits behind a family card, in member order, one per creator slug (the first member of
    /// each creator is kept as the source entry).
    ///
    /// Resolves each member through ``creator(for:)-(SkinCatalogEntry)`` rather than reading
    /// ``SkinFamily/authors``: the `author` strings ignore the per-entry `creator` override, and a
    /// card whose credit names the uploader must still open the artist's profile. Members with no
    /// author and no `creator` contribute nothing, so the result is empty for an uncredited family.
    func credits(in family: SkinFamily) -> [SkinCreatorCredit] {
        var seen = Set<String>()
        return family.members.compactMap { entry in
            creator(for: entry).map { SkinCreatorCredit(creator: $0, entry: entry) }
        }.filter { seen.insert($0.creator.slug).inserted }
    }

    /// The credit's creator as this index knows it.
    ///
    /// A credit built before the directory loaded carries a minimal record from the local slug. That
    /// slug is wrong when the author is an alias (`felix#6506` slugs to `felix-6506`, the claimed
    /// creator is `felix`), so look the *entry* up again, which applies the catalog's `creator`,
    /// then the alias map, then the local slug. Falls back to the credit's own record.
    func resolve(_ credit: SkinCreatorCredit) -> SkinCreator {
        creator(for: credit.entry) ?? credit.creator
    }

    /// The families the profile sheet lists for `creator`, newest first.
    ///
    /// - Entries are cut to what the store shows *before* grouping: the host's `policy` decides
    ///   (`section(for:)` also applies content visibility and the installable extensions, so iCube
    ///   lists nothing it cannot install). With no `policy` the app-wide ``SkinContentVisibility``
    ///   is all that applies, which is what the plain catalog browser shows.
    /// - A creator's entry is one whose resolved slug is `creator.slug`, so the per-entry `creator`
    ///   override is honoured in both directions ("ClearDoom" credits `starvingartist` but lists
    ///   under `nostromocrew01`).
    /// - Each family comes out whole, as on every other card: a variant by someone else in a mixed
    ///   family stays in it (with its own credit) and "Install all" installs the same set as
    ///   everywhere else. Labels come from the whole catalog, so they match the store's.
    /// - Ordered by ``SkinFamily/effectiveDate`` descending, then catalog order.
    func families(
        by creator: SkinCreator,
        in catalog: SkinCatalog,
        policy: SkinStorePolicy? = nil
    ) -> [SkinFamily] {
        let eligible: [SkinCatalogEntry]
        if let policy {
            eligible = catalog.skins.filter { policy.section(for: $0) != nil }
        } else {
            eligible = SkinContentVisibility.current.filter(catalog.skins)
        }
        let mine = eligible.filter { slug(for: $0) == creator.slug }
        let families = catalog.familyIndex.families(containing: mine, in: eligible)
        return families.enumerated().sorted { lhs, rhs in
            switch (lhs.element.effectiveDate, rhs.element.effectiveDate) {
            case let (l?, r?) where l != r: return l > r
            case (.some, nil): return true
            case (nil, .some): return false
            default: return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }
}

/// A creator as a credit line names them: the record the store resolved, and the catalog entry the
/// credit belongs to. The entry is kept so the profile can resolve the creator again once the
/// directory has loaded (see ``SkinCreatorIndex/resolve(_:)``).
public struct SkinCreatorCredit: Sendable, Hashable, Identifiable {
    public var creator: SkinCreator
    public var entry: SkinCatalogEntry

    public init(creator: SkinCreator, entry: SkinCatalogEntry) {
        self.creator = creator
        self.entry = entry
    }

    public var id: String { creator.slug }
}

/// The numbers under a creator's name on the profile sheet, computed from the families it lists.
public struct SkinCreatorProfileSummary: Sendable, Hashable {
    /// Downloadable files (family members).
    public var skinCount: Int
    /// Variants a user can pick between, summed over the families (``SkinFamily/variantCount``).
    public var variantCount: Int
    public var downloadCount: Int
    /// Distinct lowercased system codes, placeholders removed, sorted.
    public var systemCodes: [String]

    public init(families: [SkinFamily]) {
        skinCount = families.reduce(0) { $0 + $1.members.count }
        variantCount = families.reduce(0) { $0 + $1.variantCount }
        downloadCount = families.reduce(0) { $0 + $1.totalDownloadCount }
        let codes = families.flatMap { $0.members.flatMap(\.normalizedSystems) }
        systemCodes = Set(codes).subtracting(SkinStorePolicy.defaultPlaceholderSystemCodes).sorted()
    }

    public var isEmpty: Bool { skinCount == 0 }
}
