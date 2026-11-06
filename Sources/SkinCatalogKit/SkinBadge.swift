import Foundation

/// Who a badge is for (gamification spec §1).
public enum SkinBadgeAudience: String, Sendable, Hashable, CaseIterable {
    case creator
    case user
}

/// One badge in `badges.json` (gamification spec §1): the label, description and SF Symbol that the
/// website and the three apps share.
///
/// Decoding is lenient in the same way as ``SkinCreator``: only `id` is required. A missing or
/// mistyped `title` falls back to one derived from the id, and a missing `for` falls back to the id's
/// prefix (`creator.` or `user.`).
public struct SkinBadgeDefinition: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    /// Nil when the file names neither a known audience nor an id prefix that implies one.
    public var audience: SkinBadgeAudience?
    public var title: String
    public var detail: String?
    /// An SF Symbol name.
    public var symbol: String?
    /// Position within a tiered stem, 1 lowest. Display order only: ``SkinBadgeCatalog/highestTiers(of:)``
    /// ranks by the number the id ends in.
    public var tier: Int?

    public init(
        id: String,
        audience: SkinBadgeAudience? = nil,
        title: String? = nil,
        detail: String? = nil,
        symbol: String? = nil,
        tier: Int? = nil
    ) {
        self.id = id
        self.audience = audience ?? Self.audience(of: id)
        self.title = title ?? Self.fallbackTitle(for: id)
        self.detail = detail
        self.symbol = symbol
        self.tier = tier
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, description, symbol, tier
        case audience = "for"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawID = try container.decode(String.self, forKey: .id).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawID.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Empty badge id")
        }

        func string(_ key: CodingKeys) -> String? {
            (try? container.decodeIfPresent(String.self, forKey: key))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.isEmpty ? nil : $0 }
        }

        self.init(
            id: rawID,
            audience: string(.audience).flatMap { SkinBadgeAudience(rawValue: $0.lowercased()) },
            title: string(.title),
            detail: string(.description),
            symbol: string(.symbol),
            tier: try? container.decodeIfPresent(Int.self, forKey: .tier)
        )
    }

    /// The id without its trailing tier number: `creator.systems.5` and `creator.systems.10` share
    /// the stem `creator.systems`. An id that does not end in `.<digits>` is its own stem.
    public var stem: String {
        Self.split(id).stem
    }

    /// The number the id ends in (`5` for `creator.systems.5`), or nil for an untiered id.
    public var threshold: Int? {
        Self.split(id).threshold
    }

    static func split(_ id: String) -> (stem: String, threshold: Int?) {
        guard let dot = id.lastIndex(of: ".") else { return (id, nil) }
        let tail = id[id.index(after: dot)...]
        guard !tail.isEmpty, tail.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(tail) else {
            return (id, nil)
        }
        return (String(id[..<dot]), value)
    }

    static func audience(of id: String) -> SkinBadgeAudience? {
        guard let prefix = id.split(separator: ".", maxSplits: 1).first else { return nil }
        return SkinBadgeAudience(rawValue: String(prefix))
    }

    /// A readable title for an id nobody labelled: `creator.fancy-new-thing` becomes
    /// "Fancy new thing", `creator.systems.20` becomes "Systems 20". Never empty.
    static func fallbackTitle(for id: String) -> String {
        var parts = id.split(separator: ".").map(String.init)
        if parts.count > 1, SkinBadgeAudience(rawValue: parts[0]) != nil {
            parts.removeFirst()
        }
        let words = parts
            .joined(separator: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
        guard let first = words.first else { return id.isEmpty ? "Badge" : id }
        return first.uppercased() + words.dropFirst()
    }
}

/// Resolves badge ids to a title, description and symbol (gamification spec §1).
///
/// The bundled `badges.json` is the offline source for user badges, and a fallback for creator badges
/// whose record in `creators.json` carries only an id. An id the file does not know resolves to a
/// generic badge with a title derived from the id, so an older app build survives a new badge.
public struct SkinBadgeCatalog: Sendable {
    /// The symbol shown for an id with no definition and no symbol of its own.
    public static let genericSymbol = "rosette"

    public private(set) var version: Int
    public private(set) var definitions: [SkinBadgeDefinition]
    private let byID: [String: SkinBadgeDefinition]

    public init(version: Int = 0, definitions: [SkinBadgeDefinition] = []) {
        var index: [String: SkinBadgeDefinition] = [:]
        var unique: [SkinBadgeDefinition] = []
        for definition in definitions where index[definition.id] == nil {
            index[definition.id] = definition
            unique.append(definition)
        }
        self.version = version
        self.definitions = unique
        byID = index
    }

    /// Decodes `badges.json` bytes. A badge that fails to decode is dropped; a file that is not the
    /// expected object throws.
    public init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        self.init(version: file.version, definitions: file.badges)
    }

    /// The copy bundled with the module (`Resources/badges.json`), empty if the resource is missing.
    public static let bundled: SkinBadgeCatalog = {
        guard let url = bundledURL, let data = try? Data(contentsOf: url),
              let catalog = try? SkinBadgeCatalog(data: data)
        else {
            return SkinBadgeCatalog()
        }
        return catalog
    }()

    /// Where the bundled file lives. Exposed so tests can compare it against the skins repo's copy.
    static var bundledURL: URL? {
        Bundle.module.url(forResource: "badges", withExtension: "json")
    }

    /// The definitions for one audience, in file order.
    public func definitions(for audience: SkinBadgeAudience) -> [SkinBadgeDefinition] {
        definitions.filter { $0.audience == audience }
    }

    /// The definition for an id, or nil when the file does not know it.
    public func definition(for id: String) -> SkinBadgeDefinition? {
        byID[id]
    }

    /// The definition for an id, or a generic badge (title derived from the id, no description,
    /// ``genericSymbol``) when the file does not know it. Never fails.
    public func resolve(_ id: String) -> SkinBadgeDefinition {
        if let known = byID[id] { return known }
        var generic = SkinBadgeDefinition(id: id)
        generic.symbol = Self.genericSymbol
        return generic
    }

    /// What to show for a creator badge from `creators.json`. Labels the build wrote into the record
    /// win, then the bundled definition, then the generic badge.
    public func resolve(_ badge: SkinCreatorBadge) -> SkinBadgeDefinition {
        var result = resolve(badge.id)
        if let title = badge.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            result.title = title
        }
        if let detail = badge.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
            result.detail = detail
        }
        if let symbol = badge.symbol?.trimmingCharacters(in: .whitespacesAndNewlines), !symbol.isEmpty {
            result.symbol = symbol
        }
        if let tier = badge.tier {
            result.tier = tier
        }
        return result
    }

    /// The badges to show for a creator: tiered stems collapsed to the highest earned, resolved.
    public func displayBadges(for creator: SkinCreator) -> [SkinBadgeDefinition] {
        Self.highestTiers(of: creator.badges.map(\.id))
            .compactMap { id in creator.badges.first { $0.id == id } }
            .map(resolve(_:))
    }

    /// Keeps the highest earned badge of each tiered stem (spec §1: "the UI shows only the highest
    /// earned"). Order of the survivors follows the input; untiered ids and duplicates of an id are
    /// kept once.
    public static func highestTiers(of ids: [String]) -> [String] {
        var best: [String: Int] = [:]
        for id in ids {
            let (stem, threshold) = SkinBadgeDefinition.split(id)
            guard let threshold else { continue }
            best[stem] = max(best[stem] ?? threshold, threshold)
        }
        var seen = Set<String>()
        return ids.filter { id in
            let (stem, threshold) = SkinBadgeDefinition.split(id)
            if let threshold, best[stem] != threshold { return false }
            return seen.insert(id).inserted
        }
    }

    private struct File: Decodable {
        var version: Int
        var badges: [SkinBadgeDefinition]

        private enum CodingKeys: String, CodingKey {
            case version, badges
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = (try? container.decodeIfPresent(Int.self, forKey: .version)) ?? 0
            badges = ((try? container.decodeIfPresent([Lossy<SkinBadgeDefinition>].self, forKey: .badges)) ?? [])
                .compactMap(\.value)
        }
    }
}
