import Foundation

/// One variant packed inside a single-file skin, as the catalog lists it (`variants[]`).
///
/// The catalog computes these from each archive's `info.json` (spec §1): one `alt` entry when the
/// skin has `altRepresentations`, one `theme` per `themes[]` item, one `game` per `gameOverrides`
/// key. A split-file family member is a separate `SkinCatalogEntry`, never one of these.
public struct SkinCatalogVariant: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable, Codable {
        /// `altRepresentations`: a second full layout toggled during play.
        case alt
        /// One of the skin's `themes` (artwork swap).
        case theme
        /// One of the skin's `gameOverrides` (a per-game layout).
        case game
        /// A kind this build doesn't know. Kept so a newer catalog still decodes.
        case other(String)

        public init(rawValue: String) {
            switch rawValue.lowercased() {
            case "alt": self = .alt
            case "theme": self = .theme
            case "game": self = .game
            default: self = .other(rawValue)
            }
        }

        public var rawValue: String {
            switch self {
            case .alt: "alt"
            case .theme: "theme"
            case .game: "game"
            case let .other(value): value
            }
        }

        public init(from decoder: Decoder) throws {
            self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    public var kind: Kind
    public var key: String
    public var label: String

    public var id: String { "\(kind.rawValue):\(key)" }

    public init(kind: Kind, key: String, label: String) {
        self.kind = kind
        self.key = key
        self.label = label
    }

    private enum CodingKeys: String, CodingKey {
        case kind, key, label
    }

    /// `kind` and `key` are required; a missing `label` falls back to `key`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        key = try container.decode(String.self, forKey: .key)
        let rawLabel = (try? container.decodeIfPresent(String.self, forKey: .label))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        label = (rawLabel?.isEmpty == false ? rawLabel : nil) ?? key
    }
}

public extension SkinCatalogEntry {
    /// The tag the catalog puts on its generated sample skins (spec §4).
    static let sampleTag = "sample"
    /// The tag the catalog puts on adult skins (`Provenance-Emu/skins#30`, SkinKit#13).
    static let matureTag = "mature"

    /// A generated sample skin, hidden unless "Show test skins" is on.
    var isTestSkin: Bool { hasTag(Self.sampleTag) }

    /// An adult skin, hidden unless "Show mature skins" is on.
    var isMature: Bool { hasTag(Self.matureTag) }

    /// Whether this file carries variants of its own (a single-file skin with `variants`).
    var hasPackedVariants: Bool { !variants.isEmpty }

    /// Case-insensitive tag check.
    func hasTag(_ tag: String) -> Bool {
        tags.contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(tag) == .orderedSame
        }
    }
}
