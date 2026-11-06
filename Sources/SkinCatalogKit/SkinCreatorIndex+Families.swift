import Foundation

/// What the creator profile sheet lists (creator profiles spec §7): a creator's skins as variant
/// families, cut by the host store's policy. Pure, so the sheet's logic runs in `swift test` on the
/// host; the SwiftUI side only draws the result.
public extension SkinCreatorIndex {
    /// The creators behind a family's members, in member order, one per slug.
    ///
    /// Resolves each member through ``creator(for:)-(SkinCatalogEntry)`` rather than reading
    /// ``SkinFamily/authors``: the `author` strings ignore the per-entry `creator` override, and a
    /// card whose credit names the uploader must still open the artist's profile. Members with no
    /// author and no `creator` contribute nothing, so the result is empty for an uncredited family.
    func creators(in family: SkinFamily) -> [SkinCreator] {
        var seen = Set<String>()
        return family.members.compactMap { creator(for: $0) }.filter { seen.insert($0.slug).inserted }
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
