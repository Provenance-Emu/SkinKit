import Foundation
import SkinKitCore

// Provenance's `DeltaSkinManager+SystemIdentifier.swift`, with its `SystemIdentifier` parameters
// replaced by the plain values it derived from them:
//
// - `SystemIdentifier` → `SkinSystemID` for selection lookups,
// - `DeltaSkinGameType(systemIdentifier:)` → a `DeltaSkinGameType` argument,
// - `system.relatedSkinCatalogSystemCodes` → a `catalogSystemCodes` set.
//
// Provenance keeps thin `SystemIdentifier` overloads that compute those values and call these.
// Left in Provenance (they need `SystemIdentifier`/PVSystems, issue #6): `skin(for:)`,
// `availableSkins(for:)`, `availableSkinsSync(for:)`, the `skinIdentifier(for:)` switch and
// `defaultSkin(for: SystemIdentifier)`.

public extension DeltaSkinManager {
    /// Get all skins for a game type.
    /// - Parameters:
    ///   - gameType: the game type of the system (Provenance: `DeltaSkinGameType(systemIdentifier:)`).
    ///   - catalogSystemCodes: the lowercased catalog codes related to the system
    ///     (Provenance: `system.relatedSkinCatalogSystemCodes`).
    /// - Returns: Skins compatible with the game type: the same type, the same layout group, or
    ///   whose catalog override (sidecar / catalog cache) names one of `catalogSystemCodes`.
    func skins(for gameType: DeltaSkinGameType, catalogSystemCodes: Set<String> = []) async throws -> [any DeltaSkinProtocol] {
        // Get all skins and filter by game type
        let allSkins = try await availableSkins()
        ILOG("skins: Filtering \(allSkins.count) total skins for game type \(gameType)")

        let requestedGroup = gameType.skinLayoutGroup
        /// Override codes from sidecars / catalog cache, keyed by skin identifier.
        /// Lets us include skins whose `info.json.gameTypeIdentifier` is wrong but
        /// whose catalog metadata says they belong to this system family.
        let overrideCodes = await overrideRegistry.overrideCodesByIdentifier(for: allSkins)

        let filtered = allSkins.filter { skin in
            // Exact match
            if skin.gameType == gameType {
                return true
            }

            // Group-based match: skins in the same layout group are compatible
            // (e.g. a Genesis skin works for Sega CD and 32X; a GBC skin works for GB)
            if skin.gameType.skinLayoutGroup == requestedGroup {
                return true
            }

            /// Authoritative override path: catalog metadata wins over a misconfigured
            /// `gameTypeIdentifier` so SG-1000 skins that were saved with the wrong
            /// game type still surface for the correct system family.
            if let codes = overrideCodes[skin.identifier], !codes.isDisjoint(with: catalogSystemCodes) {
                return true
            }

            return false
        }
        ILOG("skins: Found \(filtered.count) skins for game type \(gameType)")
        return filtered
    }

    /// Get the currently selected skin for a system
    /// - Parameters:
    ///   - system: The system identifier
    ///   - gameType: the system's game type, as for `skins(for:catalogSystemCodes:)`
    ///   - catalogSystemCodes: the system's related catalog codes
    /// - Returns: The selected skin, or nil if none selected (also returns nil when the
    ///   selected skin is a case-companion skin that shouldn't be auto-loaded right now)
    func selectedSkin(
        for system: SkinSystemID,
        gameType: DeltaSkinGameType,
        catalogSystemCodes: Set<String> = []
    ) async throws -> (any DeltaSkinProtocol)? {
        ILOG("skins: selectedSkin(for: \(system.rawValue)) called")
        // Get the selected skin identifier from centralized manager (includes session overrides)
        let orientation: SkinOrientation = .portrait // Default to portrait, could be made dynamic
        guard let selectedIdentifier = selectionManager.effectiveSkinIdentifier(
            for: system,
            gameId: nil,
            orientation: orientation
        ) else {
            ILOG("skins: No selected skin identifier found for system \(system.rawValue)")
            return nil
        }
        ILOG("skins: Selected skin identifier for \(system.rawValue): \(selectedIdentifier)")

        // If the saved preference is a companion skin and it shouldn't be auto-loaded
        // (flag off or no case controller connected), skip it instead of showing the wrong skin
        if !configuration.isAllowedInAutomaticSelection(selectedIdentifier) {
            ILOG("skins: Selected skin '\(selectedIdentifier)' is a companion skin not allowed for auto-selection, skipping")
            return nil
        }

        // Find the skin with this identifier
        let systemSkins = try await skins(for: gameType, catalogSystemCodes: catalogSystemCodes)
        if let skin = systemSkins.first(where: { $0.identifier == selectedIdentifier }) {
            ILOG("skins: Found selected skin '\(skin.name)' for system \(system.rawValue)")
            return skin
        } else {
            WLOG("skins: Selected skin identifier '\(selectedIdentifier)' not found in available skins for system \(system.rawValue)")
            return nil
        }
    }

    /// Get the default skin for a game type (first available, sorted deterministically).
    /// - Returns: The default skin, or nil if none available
    ///
    /// `skins(for:)` ordering varies because the underlying availableSkins cache is
    /// merged concurrently with SkinCatalogService refreshes — that meant the
    /// "default" silently shifted every relaunch/resume when the user hadn't
    /// explicitly chosen a skin. Sort by name (case-insensitive, locale-aware)
    /// then by identifier so the fallback is stable across sessions.
    func defaultSkin(for gameType: DeltaSkinGameType, catalogSystemCodes: Set<String> = []) async throws -> (any DeltaSkinProtocol)? {
        ILOG("skins: defaultSkin(for: \(gameType)) called")
        let systemSkins = try await skins(for: gameType, catalogSystemCodes: catalogSystemCodes)
        let sorted = systemSkins.sorted { lhs, rhs in
            let lhsName = lhs.name.lowercased()
            let rhsName = rhs.name.lowercased()
            if lhsName != rhsName { return lhsName < rhsName }
            return lhs.identifier < rhs.identifier
        }
        if let skin = sorted.first(where: { configuration.isAllowedInAutomaticSelection($0.identifier) }) {
            ILOG("skins: Found default skin '\(skin.name)' for game type \(gameType)")
            return skin
        } else {
            WLOG("skins: No default skin available for game type \(gameType)")
            return nil
        }
    }

    /// Get the skin to use for a system (selected or default)
    /// - Returns: The skin to use, or nil if none available
    func skinToUse(
        for system: SkinSystemID,
        gameType: DeltaSkinGameType,
        catalogSystemCodes: Set<String> = []
    ) async throws -> (any DeltaSkinProtocol)? {
        ILOG("skins: skinToUse(for: \(system.rawValue)) called")
        // Try to get selected skin first
        if let selected = try await selectedSkin(for: system, gameType: gameType, catalogSystemCodes: catalogSystemCodes) {
            ILOG("skins: Using selected skin '\(selected.name)' for system \(system.rawValue)")
            return selected
        }

        // Fall back to default skin
        if let defaultSkin = try await defaultSkin(for: gameType, catalogSystemCodes: catalogSystemCodes) {
            ILOG("skins: Using default skin '\(defaultSkin.name)' for system \(system.rawValue)")
            return defaultSkin
        }

        WLOG("skins: No skin available for system \(system.rawValue)")
        return nil
    }

    /// Get the default skin for a system, by game-type identifier string
    /// (`"gba"`, `"com.rileytestut.delta.game.gba"`, ...), from the already loaded skins.
    func defaultSkin(for systemIdentifier: String) -> (any DeltaSkinProtocol)? {
        return loadedSkins.first { skin in
            let candidates = [skin.gameType.deltaIdentifierString, skin.gameType.manicIdentifierString].compactMap { $0?.lowercased() }
            guard candidates.contains(systemIdentifier.lowercased()) else { return false }
            return configuration.isAllowedInAutomaticSelection(skin.identifier)
        }
    }
}
