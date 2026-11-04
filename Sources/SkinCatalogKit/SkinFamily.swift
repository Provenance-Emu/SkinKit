import Foundation

// MARK: - Membership

/// Where one skin sits in a variant family: the catalog's `groupId`, `groupOrder` and resolved
/// variant label. Stored with installed skins (SkinKitManager's `.skinmeta` sidecar and
/// `SkinStoreInstalledRecord`) so the pickers can group them without the catalog.
///
/// A membership with no `groupId` is an explicit "standalone": the skin was checked against the
/// catalog and belongs to no family.
public struct SkinFamilyMembership: Codable, Sendable, Hashable {
    public var groupId: String?
    public var groupOrder: Int?
    /// The resolved label ("Doom"): the entry's `variantLabel`, else the derived one. `nil` when
    /// nothing was derivable; show the skin's name then.
    public var variantLabel: String?

    public init(groupId: String? = nil, groupOrder: Int? = nil, variantLabel: String? = nil) {
        self.groupId = groupId?.isEmpty == true ? nil : groupId
        self.groupOrder = groupOrder
        self.variantLabel = variantLabel
    }

    /// Belongs to no family.
    public static let standalone = SkinFamilyMembership()

    public var isStandalone: Bool { groupId == nil }

    /// The membership of a catalog entry. Pass the whole catalog's index so the label falls back
    /// the same way everywhere; without one only the entry's own `variantLabel` and name suffix
    /// count.
    public init(entry: SkinCatalogEntry, index: SkinFamilyIndex? = nil) {
        self.init(
            groupId: entry.groupId,
            groupOrder: entry.groupOrder,
            variantLabel: entry.groupId == nil ? entry.variantLabel : (index?.variantLabel(for: entry)
                ?? SkinVariantLabel.resolve(explicit: entry.variantLabel, fullName: entry.name, baseName: nil))
        )
    }
}

// MARK: - Catalog families

/// A variant family in the store: catalog entries sharing a `groupId`, ordered by `groupOrder`.
/// A standalone entry is a family of one. A family can mix split files and single-file skins that
/// carry their own `variants`.
///
/// Every member keeps its own entry, so its creator credit, source and download count stay visible
/// (spec anti-goal: grouping never hides attribution).
public struct SkinFamily: Identifiable, Sendable, Hashable {
    /// `group:<groupId>`, or `entry:<id>` for a standalone entry.
    public let id: String
    public let groupId: String?
    /// The family's display name: the members' shared name before " — " (the first member's),
    /// or the entry's own name for a family of one.
    public let name: String
    /// In `groupOrder` (members without one last, then feed order).
    public let members: [SkinCatalogEntry]
    /// Entry id → label to show for that member inside the family.
    public let labels: [String: String]

    public init(id: String, groupId: String?, name: String, members: [SkinCatalogEntry], labels: [String: String]) {
        self.id = id
        self.groupId = groupId
        self.name = name
        self.members = members
        self.labels = labels
    }

    /// The member whose thumbnail represents the family.
    public var primary: SkinCatalogEntry { members[0] }

    /// More than one downloadable file.
    public var isMultiFile: Bool { members.count > 1 }

    /// The "Has variants" predicate: several files, or one file that packs variants of its own.
    public var hasVariants: Bool { isMultiFile || members.contains(where: \.hasPackedVariants) }

    /// Members that are a catalog-built merge of the other members (``SkinCatalogEntry/mergedFrom``).
    /// Normally zero or one, listed first by `groupOrder` 0.
    public var mergedMembers: [SkinCatalogEntry] { members.filter(\.isMerged) }

    /// The members that are real uploads: every member except the merged ones. These are what
    /// "Install all" fetches when the family has a merged member.
    public var splitMembers: [SkinCatalogEntry] { members.filter { !$0.isMerged } }

    /// What "Install all" fetches, given the ids already installed: the split members not yet installed.
    /// A merged member is never offered while the family has split members, even when every split file is
    /// already installed (it would install the same skin twice). A family with only merged members offers
    /// those not yet installed.
    public func installAllMembers(installedIds: Set<String>) -> [SkinCatalogEntry] {
        let pool = splitMembers.isEmpty ? members : splitMembers
        return pool.filter { !installedIds.contains($0.id) }
    }

    /// Variants a user can pick between: one per split file plus each file's packed variants
    /// beyond its base layout.
    public var variantCount: Int {
        members.reduce(0) { $0 + 1 + $1.variants.count }
    }

    /// Sum of the members' download counts, for sorting families by popularity.
    public var totalDownloadCount: Int {
        members.reduce(0) { $0 + ($1.downloadCount ?? 0) }
    }

    /// The most recent member update.
    public var lastUpdated: Date? {
        members.compactMap(\.lastUpdated).max()
    }

    /// The newest member's ``SkinCatalogEntry/effectiveDate``, so adding a variant makes the family recent.
    public var effectiveDate: Date? {
        members.compactMap(\.effectiveDate).max()
    }

    /// Distinct authors in member order, for a family card's credit line.
    public var authors: [String] {
        var seen = Set<String>()
        return members.compactMap(\.author).filter { seen.insert($0.lowercased()).inserted }
    }

    /// The label to show for `member`: its variant label, else its full name.
    public func label(for member: SkinCatalogEntry) -> String {
        labels[member.id] ?? member.name
    }

    /// Group `entries` into families with labels computed from `entries` alone. Prefer
    /// `SkinFamilyIndex(entries: catalog.skins).families(from:)` when `entries` is a filtered slice,
    /// so labels don't change with the filter.
    public static func families(from entries: [SkinCatalogEntry]) -> [SkinFamily] {
        SkinFamilyIndex(entries: entries).families(from: entries)
    }
}

// MARK: - Index

/// Family facts computed once over the whole catalog: each group's base name and each grouped
/// entry's resolved label. Build it from `catalog.skins` (never a filtered slice) and use it to
/// group whatever slice a screen shows, so search and filters never change a label.
public struct SkinFamilyIndex: Sendable {
    private var baseNames: [String: String] = [:]
    private var labels: [String: String] = [:]

    public init(entries: [SkinCatalogEntry]) {
        for (groupId, members) in Self.grouped(entries) {
            guard let first = members.first else { continue }
            let base = SkinVariantLabel.stripSuffix(first.name)
            baseNames[groupId] = base
            for member in members {
                if let label = SkinVariantLabel.resolve(explicit: member.variantLabel, fullName: member.name, baseName: base) {
                    labels[member.id] = label
                }
            }
        }
    }

    /// The group's display name, or `nil` for an unknown group.
    public func baseName(forGroup groupId: String) -> String? {
        baseNames[groupId]
    }

    /// The entry's resolved variant label: `variantLabel`, else derived; `nil` when neither (or the
    /// entry has no `groupId`).
    public func variantLabel(for entry: SkinCatalogEntry) -> String? {
        labels[entry.id]
    }

    /// Group `entries` into families. Families come out in the order of their first member in
    /// `entries` (so a sorted list stays sorted); members in `groupOrder`.
    public func families(from entries: [SkinCatalogEntry]) -> [SkinFamily] {
        SkinFamilyGrouping.group(entries, groupId: \.groupId, groupOrder: \.groupOrder).map { members in
            let first = members[0]
            guard let groupId = first.groupId else {
                return SkinFamily(id: SkinFamily.id(for: first), groupId: nil, name: first.name, members: members, labels: [:])
            }
            var memberLabels: [String: String] = [:]
            for member in members {
                memberLabels[member.id] = labels[member.id]
                    ?? SkinVariantLabel.resolve(explicit: member.variantLabel, fullName: member.name, baseName: baseNames[groupId])
            }
            let name = members.count == 1 ? first.name : (baseNames[groupId] ?? SkinVariantLabel.stripSuffix(first.name))
            return SkinFamily(id: SkinFamily.id(for: first), groupId: groupId, name: name, members: members, labels: memberLabels)
        }
    }

    private static func grouped(_ entries: [SkinCatalogEntry]) -> [(String, [SkinCatalogEntry])] {
        SkinFamilyGrouping.group(entries, groupId: \.groupId, groupOrder: \.groupOrder).compactMap { members in
            members[0].groupId.map { ($0, members) }
        }
    }
}

public extension SkinFamilyIndex {
    /// The complete families of `eligible` that have at least one member in `matches`, in the order
    /// their first match appears in `matches`.
    ///
    /// Use this wherever a search, filter or shelf cut picks entries: grouping the picked entries
    /// alone would hand the card a family missing the members that didn't make the cut, so its
    /// variants section shrinks and "Install all" installs a subset.
    func families(containing matches: [SkinCatalogEntry], in eligible: [SkinCatalogEntry]) -> [SkinFamily] {
        let complete = families(from: eligible)
        var byId: [String: SkinFamily] = [:]
        for family in complete {
            byId[family.id] = family
        }
        var seen = Set<String>()
        var result: [SkinFamily] = []
        for entry in matches {
            let id = SkinFamily.id(for: entry)
            guard seen.insert(id).inserted, let family = byId[id] else { continue }
            result.append(family)
        }
        return result
    }

    /// A shelf of at most `limit` complete families of `eligible`, sorted by family. The cut is
    /// taken after grouping, so it never splits a family.
    func shelf(
        from eligible: [SkinCatalogEntry],
        limit: Int,
        by areInIncreasingOrder: (SkinFamily, SkinFamily) -> Bool
    ) -> [SkinFamily] {
        Array(families(from: eligible).sorted(by: areInIncreasingOrder).prefix(max(0, limit)))
    }
}

public extension SkinFamily {
    /// The `id` of the family `entry` belongs to.
    static func id(for entry: SkinCatalogEntry) -> String {
        entry.groupId.map { "group:\($0)" } ?? "entry:\(entry.id)"
    }
}

public extension SkinCatalog {
    /// The family index over every entry in the catalog.
    var familyIndex: SkinFamilyIndex { SkinFamilyIndex(entries: skins) }

    /// Every entry grouped into families.
    var families: [SkinFamily] { familyIndex.families(from: skins) }
}

// MARK: - Generic grouping

/// The grouping rule, for any item: catalog entries, or an app's installed skins with their stored
/// `SkinFamilyMembership`.
///
/// Items sharing a `groupId` form one group; items without one are groups of one. Groups come out
/// in the order of their first item; items within a group by `groupOrder` ascending, items without
/// one after those, ties in input order.
public enum SkinFamilyGrouping {
    public static func group<Item>(
        _ items: [Item],
        groupId: (Item) -> String?,
        groupOrder: (Item) -> Int?
    ) -> [[Item]] {
        var order: [String] = []
        var buckets: [String: [(offset: Int, item: Item)]] = [:]
        for (offset, item) in items.enumerated() {
            let key: String
            if let id = groupId(item), !id.isEmpty {
                key = "g:" + id
            } else {
                key = "i:\(offset)"
            }
            if buckets[key] == nil {
                order.append(key)
            }
            buckets[key, default: []].append((offset, item))
        }
        return order.compactMap { key in
            buckets[key]?.sorted { lhs, rhs in
                switch (groupOrder(lhs.item), groupOrder(rhs.item)) {
                case let (l?, r?) where l != r: return l < r
                case (.some, nil): return true
                case (nil, .some): return false
                default: return lhs.offset < rhs.offset
                }
            }.map(\.item)
        }
    }

    /// Group installed items by their stored memberships. `nil` membership means standalone.
    public static func group<Item>(
        _ items: [Item],
        membership: (Item) -> SkinFamilyMembership?
    ) -> [[Item]] {
        group(items, groupId: { membership($0)?.groupId }, groupOrder: { membership($0)?.groupOrder })
    }
}

/// An installed-skin family for a picker: any item type, labelled from stored memberships.
public struct SkinInstalledFamily<Item>: Identifiable {
    /// `group:<groupId>`, or `item:<key>` for a standalone skin.
    public let id: String
    public let groupId: String?
    /// The family's display name (first member's name before " — "), or the skin's name.
    public let name: String
    public let members: [Item]
    /// Parallel to `members`: the label to show for each.
    public let labels: [String]

    public var isMultiMember: Bool { members.count > 1 }

    /// Group installed skins into families for a picker.
    ///
    /// - Parameters:
    ///   - key: a stable unique key for an item (the skin identifier).
    ///   - name: the item's display name.
    ///   - membership: the stored membership, or `nil` when the skin has none (standalone).
    public static func families(
        _ items: [Item],
        key: (Item) -> String,
        name: (Item) -> String,
        membership: (Item) -> SkinFamilyMembership?
    ) -> [SkinInstalledFamily<Item>] {
        SkinFamilyGrouping.group(items, membership: membership).map { members in
            let first = members[0]
            guard members.count > 1, let groupId = membership(first)?.groupId else {
                return SkinInstalledFamily(
                    id: "item:\(key(first))", groupId: membership(first)?.groupId, name: name(first),
                    members: members, labels: members.map(name)
                )
            }
            let base = SkinVariantLabel.stripSuffix(name(first))
            let labels = members.map { item in
                SkinVariantLabel.resolve(explicit: membership(item)?.variantLabel, fullName: name(item), baseName: base)
                    ?? name(item)
            }
            return SkinInstalledFamily(id: "group:\(groupId)", groupId: groupId, name: base, members: members, labels: labels)
        }
    }
}

extension SkinInstalledFamily: Sendable where Item: Sendable {}
