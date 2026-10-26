#if canImport(UIKit)
import Foundation
@preconcurrency import SkinKitCore
import SkinKitManager

/// A system, as the picker and catalog views need to show it.
///
/// Provenance described systems with `SystemIdentifier` (PVPrimitives): an enum with a display name,
/// a catalog code and a mapping to `DeltaSkinGameType`. SkinKitUI can't depend on it, so the views take
/// this plain value, and the app builds one per `SystemIdentifier`:
///
///     DeltaSkinSystem(id: SkinSystemID(system.rawValue), fullName: system.fullName,
///                     gameType: DeltaSkinGameType(systemIdentifier: system),
///                     skinCatalogSystemCode: system.skinCatalogSystemCode,
///                     relatedSkinCatalogSystemCodes: system.relatedSkinCatalogSystemCodes)
public struct DeltaSkinSystem: Hashable, Identifiable, Sendable {
    public let id: SkinSystemID
    /// `SystemIdentifier.fullName`.
    public let fullName: String
    /// `DeltaSkinGameType(systemIdentifier:)`, or `nil` for systems that no Delta skin targets.
    public let gameType: DeltaSkinGameType?
    /// `SystemIdentifier.skinCatalogSystemCode`, or `nil` for systems with no catalog code (CPS1-3, DOOM,
    /// ZX Spectrum, ...). The picker's "Get More" link then opens the catalog with no system filter.
    public let skinCatalogSystemCode: String?
    /// `SystemIdentifier.relatedSkinCatalogSystemCodes` (lowercased catalog codes of the system and its family).
    public let relatedSkinCatalogSystemCodes: Set<String>

    public init(id: SkinSystemID, fullName: String, gameType: DeltaSkinGameType?,
                skinCatalogSystemCode: String? = nil, relatedSkinCatalogSystemCodes: Set<String> = []) {
        self.id = id
        self.fullName = fullName
        self.gameType = gameType
        self.skinCatalogSystemCode = skinCatalogSystemCode
        self.relatedSkinCatalogSystemCodes = relatedSkinCatalogSystemCodes
    }

    public var rawValue: String { id.rawValue }
}

/// The systems the host app knows, and the lookups the skin views make on them.
///
/// Replaces the `SystemIdentifier` calls in Provenance's views: `SystemIdentifier.allCases`,
/// `SystemIdentifier.displayName(forCatalogCode:)`, `SystemIdentifier.relatedCatalogSystemCodes(forCatalogCode:)`
/// and `DeltaSkinGameType.systemIdentifier`. Set ``current`` once at launch. The default knows no systems,
/// so names fall back to the catalog code or the game type's identifier string.
public struct DeltaSkinSystemDirectory: Sendable {
    /// `SystemIdentifier.allCases` that have a ``DeltaSkinSystem``.
    public var systems: [DeltaSkinSystem]
    /// `SystemIdentifier.displayName(forCatalogCode:)`.
    public var displayNameForCatalogCode: @Sendable (String) -> String
    /// `SystemIdentifier.relatedCatalogSystemCodes(forCatalogCode:)`.
    public var relatedCatalogSystemCodes: @Sendable (String) -> Set<String>
    /// `SystemIdentifier.canonicalSkinCatalogCode(_:)`: the catalog code folded to the form the app uses.
    public var canonicalCatalogCode: @Sendable (String) -> String
    /// `DeltaSkinGameType.systemIdentifier`, as a ``DeltaSkinSystem``.
    public var systemForGameType: @Sendable (DeltaSkinGameType) -> DeltaSkinSystem?

    public init(
        systems: [DeltaSkinSystem] = [],
        displayNameForCatalogCode: @escaping @Sendable (String) -> String = { $0.uppercased() },
        relatedCatalogSystemCodes: @escaping @Sendable (String) -> Set<String> = { [$0.lowercased()] },
        canonicalCatalogCode: @escaping @Sendable (String) -> String = { $0.lowercased() },
        systemForGameType: (@Sendable (DeltaSkinGameType) -> DeltaSkinSystem?)? = nil
    ) {
        self.systems = systems
        self.canonicalCatalogCode = canonicalCatalogCode
        self.displayNameForCatalogCode = displayNameForCatalogCode
        self.relatedCatalogSystemCodes = relatedCatalogSystemCodes
        self.systemForGameType = systemForGameType ?? { gameType in systems.first { $0.gameType == gameType } }
    }

    private static let lock = NSLock()
    private static var _current = DeltaSkinSystemDirectory()

    /// The directory in effect. Set once at launch.
    public static var current: DeltaSkinSystemDirectory {
        get { lock.withLock { _current } }
        set { lock.withLock { _current = newValue } }
    }

    /// The name to show for a skin's game type: the system's full name when the app knows the system,
    /// otherwise the game type's Delta or Manic identifier.
    public static func displayName(for gameType: DeltaSkinGameType) -> String {
        current.systemForGameType(gameType)?.fullName
            ?? (gameType.deltaIdentifierString ?? gameType.manicIdentifierString ?? String(describing: gameType))
    }
}

/// A game, as the per-game skin picker needs it (Provenance: `PVGame`).
public struct DeltaSkinGameContext: Hashable, Sendable {
    /// `PVGame.id`: the key per-game and session picks are stored under.
    public let id: String
    public let title: String
    public let md5Hash: String
    public let crc: String

    public init(id: String, title: String, md5Hash: String = "", crc: String = "") {
        self.id = id
        self.title = title
        self.md5Hash = md5Hash
        self.crc = crc
    }
}

public extension DeltaSkinManager {
    /// `skins(for:catalogSystemCodes:)` for a ``DeltaSkinSystem`` (Provenance: `skins(for: SystemIdentifier)`).
    /// Empty when the system has no Delta game type.
    func skins(for system: DeltaSkinSystem) async throws -> [any DeltaSkinProtocol] {
        guard let gameType = system.gameType else {
            WLOG("skins: No game type found for system \(system.rawValue)")
            return []
        }
        return try await skins(for: gameType, catalogSystemCodes: system.relatedSkinCatalogSystemCodes)
    }
}
#endif
