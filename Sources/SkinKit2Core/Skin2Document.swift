import Foundation

/// Why a skin did not load: where (a JSON Pointer into `skin.json`) and what.
public struct Skin2Error: Error, Equatable, Sendable, CustomStringConvertible {
    public var pointer: String
    public var message: String

    public init(_ pointer: String, _ message: String) { self.pointer = pointer; self.message = message }

    public var description: String { "\(pointer.isEmpty ? "/" : pointer): \(message)" }

    /// A decoding error, with its coding path as the pointer.
    public init(_ error: DecodingError) {
        switch error {
        case .typeMismatch(let type, let ctx):
            self.init(Skin2Pointer.from(codingPath: ctx.codingPath), "expected \(Self.typeName(type)): \(ctx.debugDescription)")
        case .valueNotFound(let type, let ctx):
            self.init(Skin2Pointer.from(codingPath: ctx.codingPath), "expected \(Self.typeName(type)), found null")
        case .keyNotFound(let key, let ctx):
            self.init(Skin2Pointer.from(codingPath: ctx.codingPath), "missing required key \"\(key.stringValue)\"")
        case .dataCorrupted(let ctx):
            self.init(Skin2Pointer.from(codingPath: ctx.codingPath), ctx.debugDescription)
        @unknown default:
            self.init("", "\(error)")
        }
    }

    private static func typeName(_ type: Any.Type) -> String {
        switch type {
        case is String.Type: return "a string"
        case is Double.Type, is Int.Type: return "a number"
        case is Bool.Type: return "a boolean"
        default:
            let name = "\(type)"
            if name.hasPrefix("Array") { return "an array" }
            if name.hasPrefix("Dictionary") { return "an object" }
            return name
        }
    }
}

/// `reference`: the unit rule (section 2). `unit = clamp(min(w, h) / shortSide, minScale, maxScale)`.
public struct Skin2Reference: Equatable, Hashable, Sendable, Decodable {
    public var shortSide: Double
    public var minScale: Double
    public var maxScale: Double

    public init(shortSide: Double, minScale: Double, maxScale: Double) {
        self.shortSide = shortSide; self.minScale = minScale; self.maxScale = maxScale
    }

    enum K: String, CodingKey { case shortSide, minScale, maxScale }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        shortSide = try c.decode(Double.self, forKey: .shortSide)
        minScale = try c.decode(Double.self, forKey: .minScale)
        maxScale = try c.decode(Double.self, forKey: .maxScale)
        try c.ensure(shortSide > 0, .shortSide, "shortSide must be above 0")
        try c.ensure(minScale > 0, .minScale, "minScale must be above 0")
        try c.ensure(maxScale >= minScale, .maxScale, "maxScale must be at least minScale")
    }

    public func unit(for size: Skin2Size) -> Double {
        min(max(size.shortSide / shortSide, minScale), maxScale)
    }
}

/// `bake`: which classic trait sets the baker writes (8.1), as `device.displayType` (both orientations).
public struct Skin2Bake: Equatable, Hashable, Sendable, Decodable {
    public var traits: [String]?
}

/// A variant (section 7): a patch set the app picks by game (`match`), by the player (`match.any`), or by the
/// alternate-layout toggle (`toggle`).
public struct Skin2Variant: Equatable, Hashable, Sendable, Decodable {
    public struct Match: Equatable, Hashable, Sendable, Decodable {
        public var md5: [String]?
        public var crc: [String]?
        public var filename: [String]?
        public var title: [String]?
        public var any: Bool?
    }

    /// One variant patch: `target` (`#id`) and the node fields it sets, as JSON. Applied before decoding.
    public struct Patch: Equatable, Hashable, Sendable, Decodable {
        public static let targetPattern = "^#[A-Za-z_][A-Za-z0-9_.-]*$"
        public var target: String
        public var fields: [String: Skin2JSON]

        public init(from decoder: Decoder) throws {
            var all = try [String: Skin2JSON](from: decoder)
            let c = try decoder.container(keyedBy: Skin2AnyKey.self)
            target = try c.decode(String.self, forKey: Skin2AnyKey("target"))
            try c.ensure(target.range(of: Self.targetPattern, options: .regularExpression) != nil, Skin2AnyKey("target"),
                         "a variant patch targets #id")
            all.removeValue(forKey: "target")
            fields = all
        }
    }

    public var label: String?
    public var match: Match?
    public var toggle: Bool?
    public var patch: [Patch]

    enum K: String, CodingKey { case label, match, toggle, patch }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        match = try c.decodeIfPresent(Match.self, forKey: .match)
        toggle = try c.decodeIfPresent(Bool.self, forKey: .toggle)
        patch = try c.decodeIfPresent([Patch].self, forKey: .patch) ?? []
    }

    public var isPlayerSelectable: Bool { match?.any == true }
}

/// A decoded 2.0 skin with its tokens, parts and the chosen theme and variant already applied.
public struct Skin2Document: Equatable, Sendable, Decodable {
    public static let formatVersionPattern = "^2\\.[0-9]+$"
    /// `skin.json` size limit (section 11).
    public static let maxFileBytes = 512 * 1024
    /// Node limit after part expansion (section 11).
    public static let maxNodes = 2000

    public var formatVersion: String
    public var requires: [String]
    public var identifier: String
    public var name: String
    public var author: String?
    public var gameTypes: [String]
    public var reference: Skin2Reference
    /// Screen ids in display order; nil means document order.
    public var screens: [String]?
    public var bake: Skin2Bake?
    public var root: Skin2Node
    public var variants: [String: Skin2Variant]
    /// Theme names the skin defines.
    public var themeNames: [String]
    /// The theme and variant this document was loaded with (nil: the base).
    public var theme: String?
    public var variant: String?

    enum K: String, CodingKey { case formatVersion, requires, identifier, name, author, gameTypes, reference, screens, bake, root, variants, themes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        formatVersion = try c.decode(String.self, forKey: .formatVersion)
        try c.ensure(formatVersion.range(of: Self.formatVersionPattern, options: .regularExpression) != nil, .formatVersion,
                     "this reader reads format 2.x, found \"\(formatVersion)\"")
        requires = try c.decodeIfPresent([String].self, forKey: .requires) ?? []
        identifier = try c.decode(String.self, forKey: .identifier)
        name = try c.decode(String.self, forKey: .name)
        author = try c.decodeIfPresent(String.self, forKey: .author)
        gameTypes = try c.decode([String].self, forKey: .gameTypes)
        try c.ensure(!gameTypes.isEmpty, .gameTypes, "a skin lists at least one game type")
        reference = try c.decode(Skin2Reference.self, forKey: .reference)
        screens = try c.decodeIfPresent([String].self, forKey: .screens)
        bake = try c.decodeIfPresent(Skin2Bake.self, forKey: .bake)
        root = try c.decode(Skin2Node.self, forKey: .root)
        try c.ensure(root.type == .group, .root, "root is a group")
        variants = try c.decodeIfPresent([String: Skin2Variant].self, forKey: .variants) ?? [:]
        themeNames = (try c.decodeIfPresent([String: Skin2JSON].self, forKey: .themes) ?? [:]).keys.sorted()
        if let traits = bake?.traits {
            for t in traits where Skin2TraitSet.family(named: t) == nil {
                throw DecodingError.dataCorruptedError(forKey: .bake, in: c,
                    debugDescription: "unknown bake trait \"\(t)\": use \(Skin2TraitSet.familyNames.joined(separator: ", "))")
            }
        }
    }

    /// Loads `skin.json`: parses it, expands tokens (with `theme`'s overrides), parts and `variant`'s patches,
    /// then decodes. `library` adds parts the skin may `use` without defining (the standard parts, later).
    public static func load(data: Data, theme: String? = nil, variant: String? = nil,
                            library: [String: Skin2JSON] = [:]) throws -> Skin2Document {
        guard data.count <= maxFileBytes else {
            throw Skin2Error("", "skin.json is \(data.count) bytes; the limit is \(maxFileBytes)")
        }
        let raw: Skin2JSON
        do { raw = try Skin2JSON.parse(data) } catch {
            throw Skin2Error("", "not valid JSON: \(error.localizedDescription)")
        }
        return try load(json: raw, theme: theme, variant: variant, library: library)
    }

    public static func load(json raw: Skin2JSON, theme: String? = nil, variant: String? = nil,
                            library: [String: Skin2JSON] = [:]) throws -> Skin2Document {
        let expanded = try Skin2Preprocessor(source: raw, library: library).expand(theme: theme, variant: variant)
        var doc = try decode(expanded)
        doc.theme = theme
        doc.variant = variant
        return doc
    }

    /// Decodes an already expanded document.
    public static func decode(_ expanded: Skin2JSON) throws -> Skin2Document {
        do {
            return try JSONDecoder().decode(Skin2Document.self, from: expanded.data())
        } catch let e as DecodingError {
            throw Skin2Error(e)
        }
    }

    /// The node with this id, if any.
    public func node(id: String) -> Skin2Node? {
        var found: Skin2Node?
        root.preorder { if found == nil, $0.id == id { found = $0 } }
        return found
    }
}
