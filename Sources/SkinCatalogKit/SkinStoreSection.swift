import Foundation

/// How a downloaded skin from a shelf is rewritten on install.
///
/// The target is an opaque id the app understands (iFly: `"dreamcast"`, `"arcade"`; iCube:
/// `"gamecube"`). SkinCatalogKit does not know what a game type is; the installer in the app (or in
/// SkinKitManager) resolves the id. See `SkinStorePolicy.retarget(for:isSupportedGameType:)`.
public enum SkinStoreRetarget: Hashable, Sendable {
    /// Install the skin as downloaded.
    case asIs
    /// Always rewrite to the target.
    case always(String)
    /// Rewrite to the target only when the skin does not already declare a game type the app shows
    /// (iFly's Dreamcast shelf: several Dreamcast skins in the wild declare a Delta type).
    case unlessSupported(String)
}

/// One shelf of the skin store.
///
/// Shelves are configuration: each app lists its own in `SkinStorePolicy.sections`, in display
/// order, which is also the order they claim an entry that matches several. Equality and hashing
/// use `id` only.
public struct SkinStoreSection: Hashable, Sendable, Identifiable {
    public let id: String
    /// Plain English; an app that localizes maps `id` to its own copy.
    public var title: String
    /// Lowercased catalog system codes this shelf accepts (`dreamcast`, `mame`, `n64`).
    public var systemCodes: Set<String>
    public var retarget: SkinStoreRetarget

    public init(
        id: String,
        title: String,
        systemCodes: Set<String>,
        retarget: SkinStoreRetarget = .asIs
    ) {
        self.id = id
        self.title = title
        self.systemCodes = Set(systemCodes.map { $0.lowercased() })
        self.retarget = retarget
    }

    public static func == (lhs: SkinStoreSection, rhs: SkinStoreSection) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - iFly shelves

public extension SkinStoreSection {
    /// Dreamcast skins install as-is unless they declare a type iFly doesn't show.
    static let dreamcast = SkinStoreSection(
        id: "dreamcast",
        title: "Dreamcast",
        systemCodes: ["dreamcast"],
        retarget: .unlessSupported("dreamcast")
    )

    /// MAME layouts become iFly arcade skins used by Naomi / Naomi 2 / Atomiswave. The feed has no
    /// `naomi` or `atomiswave` codes; MAME layouts are the closest thing that exists.
    static let arcade = SkinStoreSection(
        id: "arcade",
        title: "Arcade",
        systemCodes: ["mame"],
        retarget: .always("arcade")
    )

    /// Console layouts that map cleanly enough onto a Dreamcast pad to retarget (Joe, 2026-10-07).
    static let otherSystems = SkinStoreSection(
        id: "otherSystems",
        title: "From Other Systems",
        systemCodes: ["saturn", "n64", "gamecube", "psx", "genesis"],
        retarget: .always("dreamcast")
    )
}

// MARK: - iCube shelves

public extension SkinStoreSection {
    static let gameCube = SkinStoreSection(id: "gameCube", title: "GameCube", systemCodes: ["gamecube"])

    static let wii = SkinStoreSection(id: "wii", title: "Wii", systemCodes: ["wii"])

    /// N64 layouts are rewritten to the GameCube pad on install.
    static let nintendo64 = SkinStoreSection(
        id: "nintendo64",
        title: "Nintendo 64",
        systemCodes: ["n64"],
        retarget: .always("gamecube")
    )
}
