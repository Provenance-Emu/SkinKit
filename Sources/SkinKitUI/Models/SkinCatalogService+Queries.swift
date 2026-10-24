#if canImport(UIKit)
import Foundation
import SkinCatalogKit

/// Sorting options for skin catalog queries.
public enum SkinSortOption: String, CaseIterable, Sendable {
    /// Sort by download count (descending)
    case popular
    /// Sort by last updated date (most recent first)
    case recent
    /// Sort alphabetically by name
    case alphabetical
    /// Sort by user rating (highest first)
    case rating
}

/// The catalog queries the browser views make: search, filter, sort and list systems/tags.
///
/// Provenance's `SkinCatalogService` had these built in. SkinCatalogKit's service fetches and caches the
/// catalog only, so they live here, written against `catalog(forceRefresh:)`. System-family expansion
/// (`SystemIdentifier.relatedCatalogSystemCodes`) comes from ``DeltaSkinSystemDirectory``.
public extension SkinCatalogService {

    /// Returns `true` if the given system code is a legacy/invalid placeholder
    /// that should be hidden from the UI.
    static func isLegacySystemCode(_ code: String) -> Bool {
        SkinStorePolicy.defaultPlaceholderSystemCodes.contains(code.lowercased())
    }

    /// Searches the catalog by name, author, tags and source.
    ///
    /// Performs a case-insensitive search across skin name, author, tags, and source fields.
    ///
    /// - Parameters:
    ///   - query: The search text.
    ///   - system: Optional system short code to narrow results (e.g. "gba").
    func searchSkins(query: String, system: String? = nil) async throws -> [SkinCatalogEntry] {
        let catalog = try await catalog()
        let lowercasedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let systemFilterCodes = Self.resolvedSystemFilterCodes(system)

        guard !lowercasedQuery.isEmpty else {
            // Empty query: return all skins, optionally filtered by system
            if let filterCodes = systemFilterCodes {
                return catalog.skins.filter { Self.matchesAnySystemCode(in: $0.systems, filterCodes: filterCodes) }
            }
            return catalog.skins
        }

        return catalog.skins.filter { entry in
            // System filter — include related group codes (for example Genesis/Sega CD/32X).
            if let filterCodes = systemFilterCodes {
                guard Self.matchesAnySystemCode(in: entry.systems, filterCodes: filterCodes) else { return false }
            }

            // Text search across name, author, tags, source
            if entry.name.lowercased().contains(lowercasedQuery) { return true }
            if let author = entry.author, author.lowercased().contains(lowercasedQuery) { return true }
            if entry.tags.contains(where: { $0.lowercased().contains(lowercasedQuery) }) { return true }
            if let source = entry.source, source.lowercased().contains(lowercasedQuery) { return true }

            return false
        }
    }

    /// Filter and sort skins by various criteria.
    ///
    /// - Parameters:
    ///   - system: Optional system short code filter.
    ///   - tags: Optional tags to filter by (entries must contain at least one matching tag).
    ///   - deviceSupport: Optional device filters (e.g. ["iphone", "ipad"]).
    ///   - sortBy: How to sort the results.
    func filterSkins(
        system: String? = nil,
        tags: [String]? = nil,
        deviceSupport: [String]? = nil,
        sortBy: SkinSortOption = .popular
    ) async throws -> [SkinCatalogEntry] {
        let catalog = try await catalog()
        var results = catalog.skins
        let systemFilterCodes = Self.resolvedSystemFilterCodes(system)

        // Filter by system — include related group codes (for example NES/FDS sharing NES code).
        if let filterCodes = systemFilterCodes {
            results = results.filter { Self.matchesAnySystemCode(in: $0.systems, filterCodes: filterCodes) }
        }

        // Filter by tags (match any)
        if let tags = tags, !tags.isEmpty {
            let lowerTags = Set(tags.map { $0.lowercased() })
            results = results.filter { entry in
                let entryLowerTags = Set(entry.tags.map { $0.lowercased() })
                return !entryLowerTags.isDisjoint(with: lowerTags)
            }
        }

        /// Filter by device support (match any).
        /// Use prefix matching so broad filter tokens (e.g. "iphone") match
        /// specific catalog variants (e.g. "iphone-x", "iphone-legacy").
        /// Treat an omitted or empty `deviceSupport` list as unrestricted support.
        if let deviceSupport = deviceSupport, !deviceSupport.isEmpty {
            let lowerFilters = deviceSupport.map { $0.lowercased() }
            results = results.filter { entry in
                guard !entry.deviceSupport.isEmpty else { return true }
                let entryLower = entry.deviceSupport.map { $0.lowercased() }
                return lowerFilters.contains { filter in
                    entryLower.contains { device in
                        device == filter || device.hasPrefix(filter + "-") || filter.hasPrefix(device + "-")
                    }
                }
            }
        }

        return Self.sortEntries(results, by: sortBy)
    }

    /// Get all unique system short codes that have at least one skin in the catalog.
    ///
    /// Legacy/invalid system codes (e.g. "unofficial") are excluded. Codes are canonicalised through
    /// ``DeltaSkinSystemDirectory`` (default: lowercased), so mixed-case duplicates collapse.
    ///
    /// - Returns: Sorted array of lowercased system codes.
    func availableSystems() async throws -> [String] {
        let catalog = try await catalog()
        let canonical = DeltaSkinSystemDirectory.current.canonicalCatalogCode
        let systems = Set(catalog.skins.flatMap { $0.systems.map { canonical($0) } })
            .filter { !Self.isLegacySystemCode($0) }
        return systems.sorted()
    }

    /// Get all unique tags present in the catalog.
    ///
    /// - Returns: Sorted array of tags.
    func availableTags() async throws -> [String] {
        let catalog = try await catalog()
        return Set(catalog.skins.flatMap { $0.tags }).sorted()
    }

    /// Resolves an optional system filter into all related catalog codes.
    ///
    /// This expands a single selected system into its skin-layout family
    /// (for example Genesis -> Genesis/Sega CD/32X), while preserving exact
    /// matching behavior for unknown codes.
    internal static func resolvedSystemFilterCodes(_ system: String?) -> Set<String>? {
        guard let system else { return nil }
        let normalized = system.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return DeltaSkinSystemDirectory.current.relatedCatalogSystemCodes(normalized)
    }

    /// Returns `true` when at least one entry system code matches the filter set.
    ///
    /// Entry systems are normalized to lowercase before comparison to tolerate
    /// mixed-case data from remote catalog entries.
    internal static func matchesAnySystemCode(in entrySystems: [String], filterCodes: Set<String>) -> Bool {
        !Set(entrySystems.map { $0.lowercased() }).isDisjoint(with: filterCodes)
    }

    /// Sort entries by the given option.
    internal static func sortEntries(_ entries: [SkinCatalogEntry], by option: SkinSortOption) -> [SkinCatalogEntry] {
        switch option {
        case .popular:
            return entries.sorted { ($0.downloadCount ?? 0) > ($1.downloadCount ?? 0) }
        case .recent:
            return entries.sorted { ($0.lastUpdated ?? .distantPast) > ($1.lastUpdated ?? .distantPast) }
        case .alphabetical:
            return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .rating:
            return entries.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
        }
    }
}
#endif
