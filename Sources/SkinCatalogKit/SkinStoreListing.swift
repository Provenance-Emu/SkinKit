import Foundation

/// What one app's store lists from the catalog: the entries its ``SkinStorePolicy`` places on a
/// shelf, minus the ones that don't fit the device, with the shelves as categories.
///
/// The catalog browser builds one per catalog load when a host scopes it to a store, then asks it
/// for the entries of a category and a search. Pure and value-typed, so it is testable without UI.
public struct SkinStoreListing: Sendable {
    /// One category chip: a shelf that has at least one entry, and how many.
    public struct Category: Sendable, Identifiable, Equatable {
        public let section: SkinStoreSection
        /// Entries (files) on the shelf. A variant family counts once per member.
        public let entryCount: Int

        public var id: String { section.id }
    }

    /// Every entry the store shows, in feed order.
    public let entries: [SkinCatalogEntry]
    /// Shelves with entries, in the policy's display order.
    public let categories: [Category]

    private let sectionIdByEntryId: [String: String]

    /// - Parameters:
    ///   - entries: the whole catalog (`SkinCatalog.skins`).
    ///   - policy: the app's shelves, hidden entries, installable formats and content visibility.
    ///   - device: hides entries made for the other device class; `nil` keeps them all.
    public init(entries: [SkinCatalogEntry], policy: SkinStorePolicy, device: SkinStoreDevice?) {
        var kept: [SkinCatalogEntry] = []
        var sectionIds: [String: String] = [:]
        var counts: [String: Int] = [:]
        for entry in SkinStorePolicy.filtered(entries, for: device) {
            guard let section = policy.section(for: entry) else { continue }
            kept.append(entry)
            sectionIds[entry.id] = section.id
            counts[section.id, default: 0] += 1
        }
        self.entries = kept
        sectionIdByEntryId = sectionIds
        categories = policy.sections.compactMap { section in
            counts[section.id].map { Category(section: section, entryCount: $0) }
        }
    }

    /// The id of the shelf `entry` is on, or `nil` when the store doesn't list it.
    public func sectionId(for entry: SkinCatalogEntry) -> String? {
        sectionIdByEntryId[entry.id]
    }

    /// Whether the store lists `entry`.
    public func contains(_ entry: SkinCatalogEntry) -> Bool {
        sectionIdByEntryId[entry.id] != nil
    }

    /// The entries of one category (`nil`: all of them), in feed order.
    public func entries(inSection sectionId: String?) -> [SkinCatalogEntry] {
        guard let sectionId else { return entries }
        return entries.filter { sectionIdByEntryId[$0.id] == sectionId }
    }

    /// The entries of one category that match a search over name, author, tags and source,
    /// case-insensitively. A blank query matches everything.
    public func entries(inSection sectionId: String?, matching query: String) -> [SkinCatalogEntry] {
        let scoped = entries(inSection: sectionId)
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return scoped }
        return scoped.filter { entry in
            if entry.name.lowercased().contains(needle) { return true }
            if let author = entry.author, author.lowercased().contains(needle) { return true }
            if entry.tags.contains(where: { $0.lowercased().contains(needle) }) { return true }
            if let source = entry.source, source.lowercased().contains(needle) { return true }
            return false
        }
    }
}
