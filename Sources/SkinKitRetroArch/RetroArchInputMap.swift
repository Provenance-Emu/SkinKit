import Foundation

/// The Delta/Manic to RetroArch input table: `Resources/retroarch-input-map.json`.
///
/// Tokens on the left are what a skin's `inputs` say (`a`, `menu`, `cUp`, `touchScreen`). Values on the right are
/// RetroArch bind ids (`input_config_bind_map` in `configuration.c`), the words an overlay descriptor takes.
/// Lookup order for a token: `systems[<system>].map`, `systems[<system>].aliases`, `common`, `systems.default.map`.
/// Anything else is unconvertible. A value of `null` in the file marks a token RetroArch has nothing to bind it to;
/// that is a different report line from a token the table has never heard of.
///
/// The JSON is canonical here and vendored into the website converter (skins `docs/js/skin/retroarch-input-map.json`).
/// Keep the two byte-identical.
public struct RetroArchInputMap: Sendable {

    /// What the table says about one token.
    public enum Lookup: Equatable, Sendable {
        /// RetroArch bind id(s) are `bind`, e.g. `"a"`, `"menu_toggle"`, `"analog_left"`.
        case bind(String)
        /// A known token that RetroArch cannot bind (`null` in the file), e.g. DS `touchScreen`.
        case noEquivalent
        /// The table has no entry for the token.
        case unknown

        /// The bind id, or nil when the token cannot be converted.
        public var bindID: String? {
            if case .bind(let id) = self, !id.isEmpty { return id }
            return nil
        }
    }

    /// One system's row: the bind overrides for a core's default RetroPad layout.
    public struct System: Sendable {
        /// The core whose default RetroPad binding the row matches, e.g. "Mupen64Plus-Next default (...)".
        public let assumes: String?
        /// Skin token to bind. `nil` values (JSON `null`) are known tokens with no RetroArch equivalent.
        public let map: [String: String?]
        /// Alternate spellings of a token in `map`, e.g. `c-up` for `cUp`.
        public let aliases: [String: String]
    }

    public let version: Int
    /// Free-text provenance of the file (the `source` key); informational.
    public let source: String?
    public let common: [String: String?]
    public let unconvertibleReasons: [String: String]
    public let systems: [String: System]
    /// Full `gameTypeIdentifier` (lowercased) to system key.
    public let gameTypes: [String: String]
    /// Last component of a `gameTypeIdentifier` to system key.
    public let gameTypeSuffixes: [String: String]

    public enum LoadError: Error, Equatable {
        case missingResource
        case invalidJSON
    }

    // MARK: Loading

    /// The table bundled with this module (`Resources/retroarch-input-map.json`).
    public static func bundled() throws -> RetroArchInputMap {
        guard let url = bundledURL else { throw LoadError.missingResource }
        return try RetroArchInputMap(data: try Data(contentsOf: url))
    }

    /// Where the bundled JSON lives.
    static var bundledURL: URL? { Bundle.module.url(forResource: "retroarch-input-map", withExtension: "json") }

    public init(data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["common"] is [String: Any] else {
            throw LoadError.invalidJSON
        }
        func stringTable(_ value: Any?) -> [String: String?] {
            var out: [String: String?] = [:]
            for (key, raw) in (value as? [String: Any]) ?? [:] {
                // updateValue keeps "present but null" distinct from "absent".
                if let s = raw as? String { out.updateValue(s, forKey: key) } else if raw is NSNull { out.updateValue(nil, forKey: key) }
            }
            return out
        }
        func strings(_ value: Any?) -> [String: String] {
            ((value as? [String: Any]) ?? [:]).compactMapValues { $0 as? String }
        }

        version = (root["version"] as? Int) ?? 1
        source = root["source"] as? String
        common = stringTable(root["common"])
        unconvertibleReasons = strings(root["unconvertibleReasons"])
        gameTypes = Dictionary(strings(root["gameTypes"]).map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        gameTypeSuffixes = strings(root["gameTypeSuffixes"])

        var systems: [String: System] = [:]
        for (key, raw) in (root["systems"] as? [String: Any]) ?? [:] {
            guard let row = raw as? [String: Any] else { continue }
            systems[key] = System(assumes: row["assumes"] as? String, map: stringTable(row["map"]), aliases: strings(row["aliases"]))
        }
        self.systems = systems
    }

    // MARK: Systems

    /// The system key for a skin: the `gameTypes` table, else the last component of the identifier through
    /// `gameTypeSuffixes`, else that component itself; `"unknown"` for an empty identifier.
    public func system(forGameTypeIdentifier identifier: String?) -> String {
        let id = (identifier ?? "").lowercased()
        if let hit = gameTypes[id] { return hit }
        let last = id.split(separator: ".", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        if let hit = gameTypeSuffixes[last] { return hit }
        return last.isEmpty ? "unknown" : last
    }

    /// The "assumes" note of a system row (which core's defaults the buttons follow).
    public func assumes(system: String) -> String? {
        guard let text = systems[system]?.assumes, !text.isEmpty else { return nil }
        return text
    }

    // MARK: Tokens

    /// What RetroArch binds a skin token to on `system`.
    public func lookup(_ token: String, system: String) -> Lookup {
        lookup(token, system: system, depth: 0)
    }

    private func lookup(_ token: String, system: String, depth: Int) -> Lookup {
        let row = systems[system]
        if let hit = row?.map[token] { return Self.lookup(from: hit) }
        if depth < 8, let alias = row?.aliases[token] { return lookup(alias, system: system, depth: depth + 1) }
        if let hit = common[token] { return Self.lookup(from: hit) }
        if let hit = systems["default"]?.map[token] { return Self.lookup(from: hit) }
        return .unknown
    }

    private static func lookup(from value: String?) -> Lookup {
        value.map(Lookup.bind) ?? .noEquivalent
    }

    /// The sentence the README gives for a token that did not convert.
    public func reason(forUnconvertible token: String, system: String) -> String {
        if let reason = unconvertibleReasons[token] { return reason }
        if lookup(token, system: system) == .unknown { return "No RetroArch bind known for \"\(token)\" on \(system)." }
        return "\"\(token)\" has no RetroArch equivalent."
    }
}
