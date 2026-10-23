import Foundation

/// A system, by the string the app already uses for it.
///
/// Provenance keys skin selection by `SystemIdentifier` (an enum in `PVPrimitives`). SkinKitManager
/// can't depend on that, so selection and preferences take this wrapper over its `rawValue`. The
/// stored form is the same string, so existing `UserDefaults` data reads back unchanged.
///
/// It is deliberately not `ExpressibleByStringLiteral`: system and game keys are both strings, and a
/// literal must never silently pick the wrong one of `setSelectedSkin(_:for:)`'s overloads.
///
/// Provenance adopts it with one extension:
///
///     extension SystemIdentifier { var skinSystemID: SkinSystemID { SkinSystemID(rawValue) } }
public struct SkinSystemID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}
