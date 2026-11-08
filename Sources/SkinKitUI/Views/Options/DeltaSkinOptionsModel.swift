import Foundation
import SkinKitCore

/// Which rows of ``DeltaSkinOptionsView`` show, and the pure lookups behind them. No UI, so it runs in
/// `swift test` on the host.
struct DeltaSkinOptionsModel: Equatable {
    var hasThemes: Bool
    var hasAltRepresentations: Bool
    /// The game keys the alternate-layout choice is stored under, primary first. Empty without a game.
    var altGameKeys: [String]
    /// The `gameOverrides` key that matched the running game, if any.
    var matchedOverrideKey: String?
    /// The game's display name, when the host has one (the matched key can be a hash).
    var gameTitle: String?
    var canEditControls: Bool
    var canExport: Bool
    var hasEdits: Bool

    var showsThemePicker: Bool { hasThemes }

    /// The toggle needs a game to store the choice under.
    var showsAltToggle: Bool { hasAltRepresentations && !altGameKeys.isEmpty }

    /// "Layout for: Doom", or `nil` when no override matched.
    var gameOverrideLine: String? {
        guard let key = matchedOverrideKey else { return nil }
        let name = gameTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Layout for: \((name?.isEmpty == false ? name : nil) ?? key)"
    }

    var showsEditControls: Bool { canEditControls }
    var showsExport: Bool { canExport }

    /// The reset row always shows; it is disabled while nothing is edited.
    var resetEnabled: Bool { hasEdits }

    // MARK: Lookups

    /// The keys the alternate-layout choice is read and written under: `gameId` first, then the traits'
    /// game candidates (md5, crc, ...), without empties or repeats. Empty when there is no game.
    static func altGameKeys(gameId: String?, traitGameKeys: [String]) -> [String] {
        var seen = Set<String>()
        return ([gameId].compactMap { $0 } + traitGameKeys)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// The `gameOverrides` key that applies to a game, the way `DeltaSkin` resolves it.
    ///
    /// Candidates are tried in order; for each, an exact key match first, then a case-insensitive one. A key
    /// counts only if it has an entry for `device`. (It does not check display type and orientation: the
    /// override may still fall through to the normal layout in an orientation it does not cover.)
    static func matchedOverrideKey<V>(
        candidates: [String],
        overrides: [String: [String: V]],
        device: DeltaSkinDevice
    ) -> String? {
        for candidate in candidates {
            if overrides[candidate]?[device.rawValue] != nil { return candidate }
            let lowered = candidate.lowercased()
            // Sorted so two keys differing only by case always resolve the same way.
            for key in overrides.keys.sorted() where key.lowercased() == lowered && overrides[key]?[device.rawValue] != nil {
                return key
            }
        }
        return nil
    }

    /// The matched override key of a skin for these traits. `nil` for a skin that is not a `DeltaSkin`
    /// (other conformers expose no `gameOverrides`) or has no match.
    static func matchedOverrideKey(skin: any DeltaSkinProtocol, traits: DeltaSkinTraits) -> String? {
        guard let overrides = (skin as? DeltaSkin)?.info.gameOverrides else { return nil }
        return matchedOverrideKey(candidates: traits.gameIdentifiers, overrides: overrides, device: traits.device)
    }
}
