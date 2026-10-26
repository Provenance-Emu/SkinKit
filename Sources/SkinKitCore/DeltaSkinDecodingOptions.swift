import CoreGraphics
import Foundation

public extension DeltaSkin {
    /// Opt-in rules for reading an `info.json`.
    ///
    /// The default is `[]` (no options), which is exactly how SkinKitCore has always decoded: strict, one
    /// defect rejects the skin. Provenance and iFly pass nothing. iCube passes `.lenient`, the rules its own
    /// decoder had before it moved onto SkinKitCore. Each rule is its own option so another app can pick some.
    ///
    /// Options that validate (`dropsInvalidElements`, `limitsFrames`, `requiresCompleteDirections`) mark a
    /// representation, item or screen invalid. With `dropsInvalidElements` that element is dropped and the rest of
    /// the skin loads; without it the load throws `DeltaSkinError.invalidInfoFile`.
    struct DecodingOptions: OptionSet, Hashable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// Strip `//` comments (whole-line or trailing) before parsing. A `//` inside a string, such as a URL, is
        /// kept. Without it a commented file throws `invalidInfoFile`, and `sanitizeJSON` (the default path) cuts any
        /// line at the first `//`, strings included.
        public static let stripsComments = DecodingOptions(rawValue: 1 << 0)

        /// Drop a representation, item or screen that does not decode, on its own, instead of rejecting the
        /// whole skin. Throws `DeltaSkinInfoError.noUsableRepresentation` only when no representation is left. An
        /// optional extra that does not decode (`haptic`, `states`, screen `filters` / `placement`,
        /// `backgroundAnimation`, `keyboardOverlay`, `themes`, `gameOverrides`, `debug`, `caseController`) is
        /// ignored rather than failing the element that holds it.
        public static let dropsInvalidElements = DecodingOptions(rawValue: 1 << 1)

        /// Reject frames, sizes, edges and thumbstick sizes that are not finite or exceed
        /// `maxFrameMagnitude`, sizes that are negative, and a `mappingSize` that is not positive.
        public static let limitsFrames = DecodingOptions(rawValue: 1 << 2)

        /// An item's `extendedEdges` side with no value takes the representation's side, then 0. The default
        /// fills an absent side with 0 and does not inherit. A representation's partial `extendedEdges` also
        /// fills with 0 instead of being ignored.
        public static let inheritsEdges = DecodingOptions(rawValue: 1 << 3)

        /// A directional item (d-pad, thumbstick) needs all four of `up`, `down`, `left` and `right`. The default
        /// accepts any string-to-string dictionary.
        public static let requiresCompleteDirections = DecodingOptions(rawValue: 1 << 4)

        /// Keep the Manic per-item `asset` (`normal`) on `ItemRepresentation.asset`. Without it the key is ignored
        /// and `asset` is nil. A malformed `asset` makes the item invalid.
        public static let keepsItemAssets = DecodingOptions(rawValue: 1 << 5)

        /// Read `gameTypeIdentifier` the way iCube did: the last dot component must match as written. The extra
        /// GameCube aliases `gcn` and `nintendogamecube`, and spellings with `-`, `_` or a space, are refused
        /// with `DeltaSkinInfoError.unsupportedGameType`. The default accepts them (`DeltaSkinGameType.fromAnyString`).
        public static let canonicalGameTypes = DecodingOptions(rawValue: 1 << 6)

        /// Every rule above: iCube's reading of an `info.json`.
        public static let lenient: DecodingOptions = [
            .stripsComments, .dropsInvalidElements, .limitsFrames, .inheritsEdges,
            .requiresCompleteDirections, .keepsItemAssets, .canonicalGameTypes,
        ]

        /// Largest magnitude a coordinate, size or edge may have under `limitsFrames` (mapping points; real
        /// skins use a few thousand). JSON allows values like `1e308` that are finite but overflow layout math.
        public static let maxFrameMagnitude: CGFloat = 100_000

        /// Key under which the options travel in `Decoder.userInfo`, for the model types that depend on them.
        static let userInfoKey = CodingUserInfoKey(rawValue: "SkinKitCore.DeltaSkin.DecodingOptions")!

        /// The rules that rewrite the JSON before it reaches the model (all but `stripsComments` and `keepsItemAssets`).
        var rewritesJSON: Bool {
            !isDisjoint(with: [.dropsInvalidElements, .limitsFrames, .inheritsEdges, .requiresCompleteDirections, .canonicalGameTypes])
        }
    }

    /// The Manic per-item art: `"asset": {"normal": "btn-a.pdf"}`. Decoded only with `DecodingOptions.keepsItemAssets`.
    struct ItemAsset: Codable, Equatable, Sendable {
        public let normal: String?

        public init(normal: String?) {
            self.normal = normal
        }
    }
}

/// Why an `info.json` was refused under `DeltaSkin.DecodingOptions` (the default decoding throws `DecodingError`).
public enum DeltaSkinInfoError: Error, Equatable {
    /// `dropsInvalidElements` left the skin with no representation.
    case noUsableRepresentation
    /// `canonicalGameTypes` refused the `gameTypeIdentifier` (carries it as written).
    case unsupportedGameType(String)
}
