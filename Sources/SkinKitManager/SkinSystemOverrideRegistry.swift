//
//  SkinSystemOverrideRegistry.swift
//  SkinKitManager (moved from Provenance's PVUIBase)
//
//  Holds authoritative system mappings for installed skins, sourced from
//  catalog metadata sidecars (`<stem>.skinmeta`) written at install time and
//  from the cached remote catalog.  This lets the UI correctly group skins
//  whose `info.json` `gameTypeIdentifier` is misconfigured by the author
//  (for example a SEGA SG-1000 skin whose `info.json` accidentally declares
//  the GBA game type).
//

import Foundation
import SkinCatalogKit
import SkinKitCore

// MARK: - Sidecar Codable Payload

/// On-disk representation of a `<stem>.skinmeta` JSON file.
///
/// Stored alongside the matching `.deltaskin` / `.manicskin` package under
/// `Documents/DeltaSkins/` so that catalog-derived metadata survives across
/// launches and is replicated by the CloudKit and iCloud Drive non-database
/// syncers (see `DeltaSkinSyncSupport.allowedExtensions`).
public struct SkinCatalogSidecar: Codable, Sendable, Equatable {
    /// Sidecar schema version; bump if the file layout changes.
    public let version: Int
    /// Catalog entry id used to install this skin.
    public let catalogEntryId: String?
    /// The skin's internal identifier from `info.json`, captured at install time.
    public let skinIdentifier: String?
    /// Display name from the catalog entry.
    public let name: String?
    /// Catalog system short codes (lowercase, e.g. `["sg1000"]`).
    public let systems: [String]
    /// Optional original game-type identifier URN from the catalog entry.
    public let gameTypeIdentifier: String?

    public init(
        version: Int = 1,
        catalogEntryId: String?,
        skinIdentifier: String?,
        name: String?,
        systems: [String],
        gameTypeIdentifier: String?
    ) {
        self.version = version
        self.catalogEntryId = catalogEntryId
        self.skinIdentifier = skinIdentifier
        self.name = name
        self.systems = systems
        self.gameTypeIdentifier = gameTypeIdentifier
    }
}

// MARK: - Registry Actor

/// Actor that resolves the authoritative set of catalog system codes for an
/// installed skin.  Lookups are layered:
///
/// 1. In-memory cache populated when the registry first sees a skin or when
///    callers explicitly register a sidecar.
/// 2. `<stem>.skinmeta` sidecar JSON next to the skin package on disk.
/// 3. The catalog from `catalogProvider` (the cached `SkinCatalogService` catalog for
///    ``shared``), matched via the shared
///    ``matchingInstalledSkin(for:in:)`` helper so the same logic that powers
///    the catalog browser drives the override fallback.
///
/// Returning an empty set means "no override available" — callers should fall
/// back to the skin's declared `gameType` / `skinLayoutGroup`.
public actor SkinSystemOverrideRegistry {

    // MARK: - Singleton

    /// Where the registry looks for a catalog entry when a skin has no sidecar. Returns `nil` when
    /// no catalog is available.
    public typealias CatalogProvider = @Sendable () async -> SkinCatalog?

    /// The shared registry. Its catalog fallback is the cached `SkinCatalogService.shared` catalog
    /// (memory, then disk, then the network when stale), which is what Provenance's registry read.
    public static let shared = SkinSystemOverrideRegistry(catalogProvider: SkinSystemOverrideRegistry.sharedServiceCatalog)

    /// `SkinCatalogService.shared`'s catalog, or `nil` when it can't be loaded.
    public static let sharedServiceCatalog: CatalogProvider = {
        do {
            return try await SkinCatalogService.shared.catalog(forceRefresh: false)
        } catch {
            DLOG("SkinSystemOverrideRegistry: Catalog unavailable for override fallback: \(error)")
            return nil
        }
    }

    /// A provider with no catalog: only sidecars and registered overrides count.
    public static let noCatalog: CatalogProvider = { nil }

    private let catalogProvider: CatalogProvider

    /// Public initializer so tests and tooling can spin up a fresh registry
    /// without polluting the singleton's caches.
    ///
    /// - Parameter catalogProvider: the fallback consulted when a skin has no sidecar. The default
    ///   is `noCatalog`, so a fresh registry never touches the network.
    public init(catalogProvider: @escaping CatalogProvider = SkinSystemOverrideRegistry.noCatalog) {
        self.catalogProvider = catalogProvider
    }

    // MARK: - Caches

    /// skin.fileURL.standardizedFileURL.path -> override codes.
    ///
    /// Path is the key because installed skins can share or omit an identifier.
    private var overridesByPath: [String: Set<String>] = [:]

    // MARK: - File Naming

    /// Sidecar files are stored next to the skin package and share its stem
    /// (e.g. `cool-skin.deltaskin` → `cool-skin.skinmeta`).
    public static let sidecarPathExtension = "skinmeta"

    /// Returns the sidecar file URL for a given skin package URL.
    public nonisolated static func sidecarURL(for skinFileURL: URL) -> URL {
        skinFileURL.deletingPathExtension().appendingPathExtension(sidecarPathExtension)
    }

    // MARK: - Public API

    /// Returns the catalog system codes that should be used for `skin`, if any.
    ///
    /// Codes are lowercased to align with Provenance's `SystemIdentifier.skinCatalogSystemCode`.
    public func systemCodes(for skin: any DeltaSkinProtocol) async -> Set<String> {
        let pathKey = skin.fileURL.standardizedFileURL.path
        if let cached = overridesByPath[pathKey], !cached.isEmpty {
            return cached
        }

        if let sidecar = readSidecar(for: skin.fileURL) {
            let codes = Self.normalize(sidecar.systems)
            if !codes.isEmpty {
                overridesByPath[pathKey] = codes
                return codes
            }
        }

        if let codes = await catalogDerivedCodes(for: skin), !codes.isEmpty {
            overridesByPath[pathKey] = codes
            return codes
        }
        return []
    }

    /// Batch lookup that maps each skin's identifier to its override codes
    /// (omitting skins with no override).  Avoids per-skin actor hops in tight
    /// filter loops like `DeltaSkinManager.skins(for:)`.
    public func overrideCodesByIdentifier(for skins: [any DeltaSkinProtocol]) async -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for skin in skins {
            let codes = await systemCodes(for: skin)
            if !codes.isEmpty {
                result[skin.identifier] = codes
            }
        }
        return result
    }

    /// Persist a sidecar for a freshly installed skin and warm the in-memory cache.
    public func writeSidecar(
        for skinFileURL: URL,
        entry: SkinCatalogEntry,
        skinIdentifier: String?
    ) async throws {
        let sidecar = SkinCatalogSidecar(
            catalogEntryId: entry.id,
            skinIdentifier: skinIdentifier,
            name: entry.name,
            systems: Array(Self.normalize(entry.systems)).sorted(),
            gameTypeIdentifier: entry.gameTypeIdentifier
        )
        try writeSidecar(sidecar, to: Self.sidecarURL(for: skinFileURL))

        let codes = Self.normalize(sidecar.systems)
        let pathKey = skinFileURL.standardizedFileURL.path
        overridesByPath[pathKey] = codes
    }

    /// Removes the sidecar (if present) and forgets any in-memory overrides
    /// associated with the skin.  Safe to call even when no sidecar exists.
    public func removeSidecar(for skinFileURL: URL, skinIdentifier _: String?) async {
        let url = Self.sidecarURL(for: skinFileURL)
        try? FileManager.default.removeItem(at: url)
        let pathKey = skinFileURL.standardizedFileURL.path
        overridesByPath.removeValue(forKey: pathKey)
    }

    /// Drops every cached override.  Tests and tooling use this to start fresh.
    public func reset() async {
        overridesByPath.removeAll()
    }

    // MARK: - Sidecar IO

    /// Reads and decodes a sidecar JSON file if it exists for the given skin.
    /// Errors are swallowed (and logged) since a malformed sidecar should not
    /// prevent the rest of the skin system from functioning.
    nonisolated public func readSidecar(for skinFileURL: URL) -> SkinCatalogSidecar? {
        let url = Self.sidecarURL(for: skinFileURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(SkinCatalogSidecar.self, from: data)
        } catch {
            WLOG("SkinSystemOverrideRegistry: Failed to read sidecar at \(url.path): \(error)")
            return nil
        }
    }

    /// Writes the sidecar atomically, creating intermediate directories if needed.
    private func writeSidecar(_ sidecar: SkinCatalogSidecar, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sidecar)
        try data.write(to: url, options: [.atomic])
    }

    // MARK: - Catalog Fallback

    /// Looks up `skin` in the catalog (if any) and, when found,
    /// returns the catalog entry's normalized `systems` list.
    ///
    /// Uses the shared ``matchingInstalledSkin(for:in:)`` helper inverted: we
    /// iterate catalog entries until one matches the skin, so the matching
    /// rules stay aligned with the catalog browser.
    private func catalogDerivedCodes(for skin: any DeltaSkinProtocol) async -> Set<String>? {
        guard let catalog = await catalogProvider() else { return nil }
        let entry = catalog.skins.first { entry in
            matchingInstalledSkin(for: entry, in: [skin]) != nil
        }
        guard let entry else { return [] }
        return Self.normalize(entry.systems)
    }

    // MARK: - Helpers

    private static func normalize(_ codes: [String]) -> Set<String> {
        Set(
            codes
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty && !SkinStorePolicy.defaultPlaceholderSystemCodes.contains($0) }
        )
    }
}

// MARK: - Matching a catalog entry to an installed skin

/// Finds the first locally installed skin that matches a catalog entry.
///
/// Matching is done in priority order:
/// 1. Catalog `id` matches the skin's internal `identifier` (exact match).
/// 2. The on-disk stem matches ``SkinCatalogEntry/preferredLocalDownloadFileName()`` (catalog installs use this name).
/// 3. The download URL filename (without extension) matches the skin's file on disk.
/// 4. The catalog `name` matches the skin's `name` (case-insensitive).
///
/// Moved from Provenance's `SkinCatalogBrowserView.swift`, where the browser and the detail view
/// shared it. The registry uses it too.
public func matchingInstalledSkin(for entry: SkinCatalogEntry, in skins: [any DeltaSkinProtocol]) -> (any DeltaSkinProtocol)? {
    guard !skins.isEmpty else { return nil }

    // 1. Identifier match (most reliable when catalog id == info.json identifier)
    if let match = skins.first(where: { $0.identifier == entry.id }) {
        return match
    }

    // 2. Stem match: file saved as `preferredLocalDownloadFileName()` under DeltaSkins
    let preferredStem = URL(fileURLWithPath: entry.preferredLocalDownloadFileName()).deletingPathExtension().lastPathComponent.lowercased()
    if !preferredStem.isEmpty, let match = skins.first(where: {
        $0.fileURL.deletingPathExtension().lastPathComponent.lowercased() == preferredStem
    }) {
        return match
    }

    // 3. Filename match: compare the download URL stem to the local file stem (manual / legacy installs)
    let catalogStem = entry.downloadURL.deletingPathExtension().lastPathComponent.lowercased()
    if !catalogStem.isEmpty, let match = skins.first(where: {
        $0.fileURL.deletingPathExtension().lastPathComponent.lowercased() == catalogStem
    }) {
        return match
    }

    // 4. Name match (case-insensitive fallback)
    let entryNameLower = entry.name.lowercased()
    return skins.first(where: { $0.name.lowercased() == entryNameLower })
}

/// Checks whether a catalog entry matches any locally installed skin.
///
/// Delegates to `matchingInstalledSkin(for:in:)` for consistent matching logic.
public func isCatalogSkinInstalled(_ entry: SkinCatalogEntry, in skins: [any DeltaSkinProtocol]) -> Bool {
    matchingInstalledSkin(for: entry, in: skins) != nil
}

// MARK: - Import file naming

extension SkinCatalogEntry {
    /// Stable local filename for a catalog download before it is copied into ``Documents/DeltaSkins``.
    ///
    /// Always ends with `.deltaskin` so ``DeltaSkinManager`` includes the file when scanning the import folder,
    /// even when ``downloadURL`` uses a generic last path component (for example GitHub release asset URLs).
    ///
    /// This is Provenance's naming and `matchingInstalledSkin` depends on it. iFly and iCube name
    /// downloads with `SkinStorePolicy.downloadFileName(for:)`, which keeps the entry's extension.
    public func preferredLocalDownloadFileName() -> String {
        let sanitized = Self.sanitizedCatalogSkinIdForFileName(id)
        return "\(sanitized).deltaskin"
    }

    /// Removes characters that are unsafe or misleading in a single path component.
    private static func sanitizedCatalogSkinIdForFileName(_ rawId: String) -> String {
        let trimmed = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "skin" }
        let separators = CharacterSet(charactersIn: "/:\\\n\r\t")
        let collapsed = trimmed.components(separatedBy: separators).filter { !$0.isEmpty }.joined(separator: "-")
        return collapsed.isEmpty ? "skin" : collapsed
    }
}
