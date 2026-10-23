import Foundation

/// Decides which catalog entries a store shows, where, and how each downloads.
///
/// Configuration, not code: each app builds one (or uses `.iFly` / `.iCube`) and injects it.
/// Value-typed and `Sendable`, pure, and cheap enough to run over the whole feed (~1,300 entries).
public struct SkinStorePolicy: Sendable {
    /// Leftover codes from before the feed's systems were cleaned up. They say nothing about the
    /// layout, so they never place an entry in a shelf.
    public static let defaultPlaceholderSystemCodes: Set<String> = ["unofficial", "unsupported", "unknown"]

    /// Archive formats both apps can import. `.zip` is hidden because it is often a folder of
    /// skins, and extensionless Google Drive links because they can't be identified before download.
    public static let defaultInstallableExtensions: Set<String> = ["deltaskin", "manicskin"]

    /// The shelves, in display order. The order is also the claim order: when an entry's systems
    /// match several shelves, the first one wins.
    public var sections: [SkinStoreSection]
    public var placeholderSystemCodes: Set<String>
    /// Entries hidden despite matching a shelf.
    public var hiddenEntryIds: Set<String>
    public var installableExtensions: Set<String>
    /// Maps the lowercased last component of an entry's `gameTypeIdentifier` to a system code, so
    /// an entry with no (or the wrong) `systems` still lands on a shelf. The code is added to the
    /// entry's own codes. Empty means `gameTypeIdentifier` is ignored (iFly).
    public var gameTypeSuffixSystemCodes: [String: String]

    public init(
        sections: [SkinStoreSection],
        placeholderSystemCodes: Set<String> = SkinStorePolicy.defaultPlaceholderSystemCodes,
        hiddenEntryIds: Set<String> = [],
        installableExtensions: Set<String> = SkinStorePolicy.defaultInstallableExtensions,
        gameTypeSuffixSystemCodes: [String: String] = [:]
    ) {
        self.sections = sections
        self.placeholderSystemCodes = Set(placeholderSystemCodes.map { $0.lowercased() })
        self.hiddenEntryIds = hiddenEntryIds
        self.installableExtensions = Set(installableExtensions.map { $0.lowercased() })
        self.gameTypeSuffixSystemCodes = gameTypeSuffixSystemCodes
    }

    // MARK: - Presets

    /// iFly: Dreamcast, arcade (MAME) and other systems retargeted to the Dreamcast pad.
    ///
    /// Entries hidden: `b88c501e8689debb` Sharp X1, filed under `mame` but a Japanese home
    /// computer keyboard layout, not an arcade panel. `gameTypeIdentifier` is not consulted.
    public static let iFly = SkinStorePolicy(
        sections: [.dreamcast, .arcade, .otherSystems],
        hiddenEntryIds: ["b88c501e8689debb"]
    )

    /// iCube: GameCube, Wii and N64 (rewritten to the GameCube pad).
    ///
    /// An entry's `gameTypeIdentifier` also places it (`ngc`, `gc`, `gamecube`, `wii`, `n64`), the
    /// way iCube's `SkinGameType` resolves the suffix.
    public static let iCube = SkinStorePolicy(
        sections: [.gameCube, .wii, .nintendo64],
        gameTypeSuffixSystemCodes: [
            "ngc": "gamecube",
            "gc": "gamecube",
            "gamecube": "gamecube",
            "wii": "wii",
            "n64": "n64",
        ]
    )

    // MARK: - Classification

    /// The lowercased skin extension of `url`'s last path component, or `nil` when it isn't one
    /// the app can import.
    public func installableExtension(for url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        return installableExtensions.contains(ext) ? ext : nil
    }

    /// The system codes an entry claims: its `systems` minus placeholders, plus the code its game
    /// type identifier implies when `gameTypeSuffixSystemCodes` has one.
    public func systemCodes(for entry: SkinCatalogEntry) -> Set<String> {
        var codes = Set(entry.normalizedSystems).subtracting(placeholderSystemCodes)
        if let suffix = entry.gameTypeSuffix, let code = gameTypeSuffixSystemCodes[suffix] {
            codes.insert(code)
        }
        return codes
    }

    /// The shelf for `entry`, or `nil` when the store hides it. When an entry matches several
    /// shelves the first in `sections` wins.
    public func section(for entry: SkinCatalogEntry) -> SkinStoreSection? {
        guard !hiddenEntryIds.contains(entry.id),
              installableExtension(for: entry.downloadURL) != nil
        else {
            return nil
        }
        let codes = systemCodes(for: entry)
        return sections.first { !codes.isDisjoint(with: $0.systemCodes) }
    }

    /// Visible entries grouped by shelf, shelves in display order, empty shelves omitted. Entries
    /// keep feed order within a shelf.
    public func sections(for entries: [SkinCatalogEntry]) -> [(
        section: SkinStoreSection,
        entries: [SkinCatalogEntry]
    )] {
        var grouped: [SkinStoreSection: [SkinCatalogEntry]] = [:]
        for entry in entries {
            guard let section = section(for: entry) else { continue }
            grouped[section, default: []].append(entry)
        }
        return sections.compactMap { section in
            guard let list = grouped[section], !list.isEmpty else { return nil }
            return (section, list)
        }
    }

    // MARK: - Install routing

    /// The retarget id to apply to a downloaded skin from `section`, or `nil` to install as-is.
    ///
    /// - Parameter isSupportedGameType: whether the downloaded skin already declares a game type
    ///   the app shows. Only `.unlessSupported` shelves look at it. The caller computes it (iFly:
    ///   `SkinCompatibility.Inspection.isSupportedGameType`), because inspecting a skin needs
    ///   SkinKitCore and this module doesn't depend on it.
    public func retarget(for section: SkinStoreSection, isSupportedGameType: Bool) -> String? {
        switch section.retarget {
        case .asIs: nil
        case let .always(target): target
        case let .unlessSupported(target): isSupportedGameType ? nil : target
        }
    }

    // MARK: - Download

    /// Local file name for a download: `<entry id>.<deltaskin|manicskin>`. The importer keys off
    /// the extension, and many feed URLs end in a name that is unsafe or ambiguous as a path
    /// component.
    public func downloadFileName(for entry: SkinCatalogEntry) -> String? {
        guard let ext = installableExtension(for: entry.downloadURL) else { return nil }
        let unsafe = CharacterSet(charactersIn: "/:\\\n\r\t")
        let stem = entry.id
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: unsafe)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return "\(stem.isEmpty ? "skin" : stem).\(ext)"
    }
}
