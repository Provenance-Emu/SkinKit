import Foundation

public enum Skin2TokenType: String, Codable, Sendable, CaseIterable { case color, length, number, string }
public enum Skin2ParamType: String, Codable, Sendable, CaseIterable { case string, number, length, color, shape, paint }

/// A token's type and value. Length values are stored in their explicit form (`{"pt": 8}`), so a length token can
/// fill a part parameter of type `length`.
public struct Skin2Token: Equatable, Sendable {
    public var type: Skin2TokenType
    public var value: Skin2JSON
}

/// Expands a 2.0 source document before typed decoding (sections 3.9 and 7):
///
/// - `"$name"` (a whole string) becomes the token's value, with the active theme's overrides.
/// - `"@name"` (a whole string, inside a part's node) becomes the part argument.
/// - `{"use": "part", "with": {…}, "id", "layout", "when", "visible"}` becomes the part's node with its parameters
///   substituted, then the caller's keys merged over it. Parts may use parts, 8 deep, never recursively.
/// - Ids inside a part instance are scoped to it: a part node's descendant `id: "body"` becomes `"<instance>.body"`
///   and `#body` references inside the part (state targets, anchors) follow, so a part used seven times still
///   gives unique ids. The caller must give an instance id when the part has inner ids.
/// - The chosen variant's patches apply to the nodes they target (variants apply before `when`).
///
/// The output drops `tokens` and `parts`; everything else (including `variants` and `themes`) stays.
public struct Skin2Preprocessor {
    public static let maxPartDepth = 8
    public static let referencePattern = "^[$@][A-Za-z_][A-Za-z0-9_]*$"
    public static let tokenNamePattern = "^[A-Za-z_][A-Za-z0-9_]*$"
    public static let partNamePattern = "^[A-Za-z_][A-Za-z0-9_.]*$"
    /// Keys a part instance may carry besides `use` and `with`.
    public static let instanceKeys: Set<String> = ["id", "layout", "when", "visible"]
    /// Layout fields that merge one level deep in patches; the rest are replaced.
    static let mergedLayoutKeys: Set<String> = ["size", "minSize", "maxSize", "anchor", "offset"]

    public let source: [String: Skin2JSON]
    let library: [String: Skin2JSON]

    public init(source: Skin2JSON, library: [String: Skin2JSON] = [:]) throws {
        guard case .object(let o) = source else { throw Skin2Error("", "a skin is a JSON object") }
        self.source = o
        // The standard parts come first; a caller's library entries win (tests, tools).
        self.library = Skin2StdParts.library.merging(library) { _, caller in caller }
    }

    // MARK: Tokens

    /// The token table, with `theme`'s overrides when given.
    public func tokens(theme: String? = nil) throws -> [String: Skin2Token] {
        var out: [String: Skin2Token] = [:]
        if let raw = source["tokens"] {
            guard case .object(let o) = raw else { throw Skin2Error("/tokens", "tokens is an object") }
            for (name, value) in o {
                let p = Skin2Pointer.appending("/tokens", name)
                guard name.range(of: Self.tokenNamePattern, options: .regularExpression) != nil else {
                    throw Skin2Error(p, "a token name holds letters, digits and _")
                }
                out[name] = try Self.parseToken(value, at: p)
            }
        }
        let themes = try themeTable()
        for (themeName, overrides) in themes {
            for (name, value) in overrides {
                let p = Skin2Pointer.appending(Skin2Pointer.appending("/themes", themeName), name)
                guard let base = out[name] else { throw Skin2Error(p, "theme sets $\(name), which is not a token") }
                var t = try Self.parseToken(value, at: p)
                if base.type == .length, t.type == .number, let n = t.value.numberValue { t = Skin2Token(type: .length, value: ["pt": .number(n)]) }
                guard t.type == base.type else {
                    throw Skin2Error(p, "theme gives $\(name) a \(t.type.rawValue), but the token is a \(base.type.rawValue)")
                }
                if themeName == theme { out[name] = t }
            }
        }
        if let theme, themes[theme] == nil { throw Skin2Error("/themes", "no theme named \"\(theme)\"") }
        return out
    }

    func themeTable() throws -> [String: [String: Skin2JSON]] {
        guard let raw = source["themes"] else { return [:] }
        guard case .object(let o) = raw else { throw Skin2Error("/themes", "themes is an object") }
        var out: [String: [String: Skin2JSON]] = [:]
        for (name, value) in o {
            guard case .object(let overrides) = value else {
                throw Skin2Error(Skin2Pointer.appending("/themes", name), "a theme is an object of token values")
            }
            out[name] = overrides
        }
        return out
    }

    /// `"#RRGGBB"` (colour), a number, or the typed form `{"color" | "length" | "number" | "string": value}`.
    static func parseToken(_ value: Skin2JSON, at p: String) throws -> Skin2Token {
        switch value {
        case .number:
            return Skin2Token(type: .number, value: value)
        case .string(let s):
            guard Skin2Color(hex: s) != nil else {
                throw Skin2Error(p, "a short token is a colour (#RRGGBB[AA]) or a number; write {\"string\": …} for text")
            }
            return Skin2Token(type: .color, value: value)
        case .object(let o):
            guard o.count == 1, let (key, inner) = o.first, let type = Skin2TokenType(rawValue: key) else {
                throw Skin2Error(p, "a typed token is {\"color\" | \"length\" | \"number\" | \"string\": value}")
            }
            switch type {
            case .color:
                guard let s = inner.stringValue, Skin2Color(hex: s) != nil else { throw Skin2Error(p, "a color token is #RRGGBB or #RRGGBBAA") }
                return Skin2Token(type: .color, value: inner)
            case .number:
                guard inner.numberValue != nil else { throw Skin2Error(p, "a number token holds a number") }
                return Skin2Token(type: .number, value: inner)
            case .string:
                guard inner.stringValue != nil else { throw Skin2Error(p, "a string token holds a string") }
                return Skin2Token(type: .string, value: inner)
            case .length:
                let length: Skin2Length
                do { length = try Skin2Length(json: inner) } catch { throw Skin2Error(p, "\(error)") }
                switch length {
                case .pt(let n) where inner.numberValue != nil: return Skin2Token(type: .length, value: ["pt": .number(n)])
                case .frac(let f) where inner.stringValue != nil: return Skin2Token(type: .length, value: ["frac": .number(f)])
                default: return Skin2Token(type: .length, value: inner)
                }
            }
        default:
            throw Skin2Error(p, "a token is a colour string, a number or a typed token object")
        }
    }

    // MARK: Parts

    struct Part {
        var name: String
        var params: [String: (type: Skin2ParamType, defaultValue: Skin2JSON?)]
        var node: Skin2JSON
        var pointer: String
    }

    func part(named name: String, at p: String) throws -> Part {
        let local = source["parts"]?.objectValue
        let pointer: String
        let raw: Skin2JSON
        if let def = local?[name] {
            raw = def; pointer = Skin2Pointer.appending("/parts", name)
        } else if let def = library[name] {
            raw = def; pointer = "library:\(name)"
        } else if name.hasPrefix(Skin2StdParts.prefix) {
            throw Skin2Error(p, "no part named \"\(name)\" in the standard parts library (\(Skin2StdParts.featureName)), which has \(Skin2StdParts.names.joined(separator: ", "))")
        } else {
            throw Skin2Error(p, "no part named \"\(name)\"")
        }
        guard case .object(let o) = raw else { throw Skin2Error(pointer, "a part is {\"params\": {…}, \"node\": {…}}") }
        guard let node = o["node"], node.objectValue != nil else { throw Skin2Error(pointer, "a part needs a node object") }
        var params: [String: (Skin2ParamType, Skin2JSON?)] = [:]
        if let rawParams = o["params"] {
            guard case .object(let po) = rawParams else { throw Skin2Error(pointer + "/params", "params is an object") }
            for (pname, spec) in po {
                let pp = Skin2Pointer.appending(pointer + "/params", pname)
                guard pname.range(of: Self.tokenNamePattern, options: .regularExpression) != nil else {
                    throw Skin2Error(pp, "a parameter name holds letters, digits and _")
                }
                guard let t = spec["type"]?.stringValue, let type = Skin2ParamType(rawValue: t) else {
                    throw Skin2Error(pp, "a parameter has a type: string, number, length, color, shape or paint")
                }
                params[pname] = (type, spec["default"])
            }
        }
        return Part(name: name, params: params, node: node, pointer: pointer)
    }

    /// A message when `value` is not a valid argument of `type`, else nil.
    static func typeError(_ value: Skin2JSON, _ type: Skin2ParamType) -> String? {
        switch type {
        case .string: return value.stringValue != nil ? nil : "expected a string"
        case .number: return value.numberValue != nil ? nil : "expected a number"
        case .color: return value.stringValue.flatMap(Skin2Color.init(hex:)) != nil ? nil : "expected a colour (#RRGGBB[AA])"
        case .shape: return value["kind"]?.stringValue != nil ? nil : "expected a shape object with a kind"
        case .paint: return value["type"]?.stringValue != nil ? nil : "expected a paint object with a type"
        case .length:
            guard case .object = value else {
                return "a length argument is explicit: {\"pt\": N}, {\"frac\": F} or a max/min/sum (a bare number would be ambiguous)"
            }
            do { _ = try Skin2Length(json: value); return nil } catch { return "\(error)" }
        }
    }

    // MARK: Expansion

    /// Counts nodes as one expansion builds them. The part depth limit doesn't bound branching (a part with ten
    /// children that each use a part with ten children…), so expansion stops at the node limit instead of
    /// building the whole tree and counting afterwards.
    final class NodeBudget {
        let limit: Int
        private(set) var count = 0
        init(limit: Int = Skin2Document.maxNodes) { self.limit = limit }

        func take(at pointer: String) throws {
            count += 1
            if count > limit {
                throw Skin2Error(pointer, "the skin has more than \(limit) nodes after expanding parts; the limit is \(limit)")
            }
        }
    }

    struct Scope {
        var params: [String: Skin2JSON]?
        var parts: [String] = []
        /// Shared by every scope of one expansion.
        var budget: NodeBudget
        /// The outermost part instance being expanded, in the document's own tree: where a budget error points.
        var site: String?

        init(params: [String: Skin2JSON]? = nil, parts: [String] = [], budget: NodeBudget, site: String? = nil) {
            self.params = params; self.parts = parts; self.budget = budget; self.site = site
        }
    }

    /// The expanded document.
    public func expand(theme: String? = nil, variant: String? = nil) throws -> Skin2JSON {
        if let v = source["formatVersion"]?.stringValue,
           v.range(of: Skin2Document.formatVersionPattern, options: .regularExpression) == nil {
            throw Skin2Error("/formatVersion", "this reader reads format 2.x, found \"\(v)\"")
        }
        let tokens = try tokens(theme: theme)
        if let reserved = source["parts"]?.objectValue?.keys.sorted().first(where: { $0.hasPrefix(Skin2StdParts.prefix) }) {
            throw Skin2Error(Skin2Pointer.appending("/parts", reserved),
                             "part names starting with \"std.\" belong to the standard parts library; pick another name")
        }
        var out = source
        out.removeValue(forKey: "tokens")
        out.removeValue(forKey: "parts")
        guard let root = source["root"] else { throw Skin2Error("", "missing required key \"root\"") }
        let budget = NodeBudget()
        var expandedRoot = try expand(root, at: "/root", scope: Scope(budget: budget), tokens: tokens, isNode: true)
        if let variants = source["variants"] {
            let expandedVariants = try expand(variants, at: "/variants", scope: Scope(budget: budget), tokens: tokens)
            out["variants"] = expandedVariants
            if let variant {
                try Self.apply(variant: variant, from: expandedVariants, to: &expandedRoot)
            }
        } else if let variant {
            throw Skin2Error("/variants", "no variant named \"\(variant)\"")
        }
        out["root"] = expandedRoot
        return .object(out)
    }

    /// `isNode`: `value` sits where a node goes (the root, a part's node, an element of `children`).
    func expand(_ value: Skin2JSON, at p: String, scope: Scope, tokens: [String: Skin2Token], isNode: Bool = false) throws -> Skin2JSON {
        switch value {
        case .string(let s):
            guard s.range(of: Self.referencePattern, options: .regularExpression) != nil else { return value }
            let name = String(s.dropFirst())
            if s.hasPrefix("$") {
                guard let t = tokens[name] else { throw Skin2Error(p, "unknown token $\(name)") }
                return t.value
            }
            guard let params = scope.params else {
                throw Skin2Error(p, "@\(name) is a part parameter; it only means something inside a part's node")
            }
            guard let arg = params[name] else { throw Skin2Error(p, "part \(scope.parts.last ?? "") has no parameter @\(name)") }
            return arg
        case .array(let a):
            return .array(try a.enumerated().map { try expand($1, at: Skin2Pointer.appending(p, $0), scope: scope, tokens: tokens) })
        case .object(let o):
            if o["use"] != nil { return try instantiate(o, at: p, scope: scope, tokens: tokens) }
            if isNode { try scope.budget.take(at: scope.site ?? p) }
            var out: [String: Skin2JSON] = [:]
            // Children first, so a runaway tree stops before the rest of each node is expanded.
            if case .array(let children)? = o["children"] {
                let cp = Skin2Pointer.appending(p, "children")
                out["children"] = .array(try children.enumerated().map {
                    try expand($1, at: Skin2Pointer.appending(cp, $0), scope: scope, tokens: tokens, isNode: true)
                })
            }
            for (k, v) in o where out[k] == nil {
                out[k] = try expand(v, at: Skin2Pointer.appending(p, k), scope: scope, tokens: tokens)
            }
            return .object(out)
        default:
            return value
        }
    }

    func instantiate(_ o: [String: Skin2JSON], at p: String, scope: Scope, tokens: [String: Skin2Token]) throws -> Skin2JSON {
        guard let name = o["use"]?.stringValue else { throw Skin2Error(p + "/use", "use names a part") }
        if let extra = o.keys.sorted().first(where: { $0 != "use" && $0 != "with" && !Self.instanceKeys.contains($0) }) {
            throw Skin2Error(Skin2Pointer.appending(p, extra), "a part instance takes only use, with, id, layout, when and visible")
        }
        if scope.parts.contains(name) {
            throw Skin2Error(p + "/use", "part \(name) uses itself (\((scope.parts + [name]).joined(separator: " → ")))")
        }
        if scope.parts.count >= Self.maxPartDepth {
            throw Skin2Error(p + "/use", "parts nest at most \(Self.maxPartDepth) deep")
        }
        let part = try part(named: name, at: p + "/use")
        let site = scope.site ?? p

        // Arguments in the caller's scope, then defaults (tokens only), then type checks.
        var args: [String: Skin2JSON] = [:]
        let with = o["with"] ?? .object([:])
        guard case .object(let given) = with else { throw Skin2Error(p + "/with", "with is an object of arguments") }
        for (key, raw) in given {
            let ap = Skin2Pointer.appending(p + "/with", key)
            guard part.params[key] != nil else { throw Skin2Error(ap, "part \(name) has no parameter \"\(key)\"") }
            args[key] = try expand(raw, at: ap, scope: scope, tokens: tokens)
        }
        for (key, spec) in part.params where args[key] == nil {
            let dp = Skin2Pointer.appending(part.pointer + "/params", key)
            guard let def = spec.defaultValue else { throw Skin2Error(p + "/with", "part \(name) needs \"\(key)\"") }
            args[key] = try expand(def, at: dp + "/default", scope: Scope(budget: scope.budget, site: site), tokens: tokens)
        }
        for (key, value) in args {
            if let message = Self.typeError(value, part.params[key]!.type) {
                let ap = given[key] != nil ? Skin2Pointer.appending(p + "/with", key)
                    : Skin2Pointer.appending(part.pointer + "/params", key) + "/default"
                throw Skin2Error(ap, "\(name).\(key) is a \(part.params[key]!.type.rawValue): \(message)")
            }
        }

        var body = try expand(part.node, at: part.pointer + "/node",
                              scope: Scope(params: args, parts: scope.parts + [name], budget: scope.budget, site: site), tokens: tokens, isNode: true)
        guard case .object(var node) = body else { throw Skin2Error(part.pointer + "/node", "a part's node is an object") }

        // Scope the part's inner ids to this instance.
        var instanceID: String?
        if let rawID = o["id"] { instanceID = try expand(rawID, at: p + "/id", scope: scope, tokens: tokens).stringValue }
        var inner: Set<String> = []
        for child in node["children"]?.arrayValue ?? [] { Self.collectIDs(child, into: &inner) }
        if !inner.isEmpty {
            guard let instanceID else {
                throw Skin2Error(p, "part \(name) names inner nodes (\(inner.sorted().joined(separator: ", "))); give this instance an id")
            }
            body = Self.qualify(.object(node), ids: inner, prefix: instanceID, isRoot: true)
            node = body.objectValue ?? node
        }

        for key in Self.instanceKeys.sorted() {
            guard let raw = o[key] else { continue }
            let value = try expand(raw, at: Skin2Pointer.appending(p, key), scope: scope, tokens: tokens)
            if key == "layout", let base = node["layout"] {
                node["layout"] = Self.mergeLayout(base, value)
            } else if value.isNull {
                node.removeValue(forKey: key)
            } else {
                node[key] = value
            }
        }
        return .object(node)
    }

    static func collectIDs(_ v: Skin2JSON, into ids: inout Set<String>) {
        guard case .object(let o) = v else { return }
        if o["type"] != nil, let id = o["id"]?.stringValue { ids.insert(id) }
        for child in o["children"]?.arrayValue ?? [] { collectIDs(child, into: &ids) }
    }

    /// Prefixes inner node ids and the `#id` references (`to`, `target`) that point at them.
    static func qualify(_ v: Skin2JSON, ids: Set<String>, prefix: String, isRoot: Bool) -> Skin2JSON {
        switch v {
        case .array(let a):
            return .array(a.map { qualify($0, ids: ids, prefix: prefix, isRoot: false) })
        case .object(let o):
            var out: [String: Skin2JSON] = [:]
            let isNode = o["type"] != nil
            for (k, value) in o {
                if k == "id", isNode, !isRoot, let id = value.stringValue, ids.contains(id) {
                    out[k] = .string(prefix + "." + id)
                } else if k == "to" || k == "target", let s = value.stringValue, s.hasPrefix("#") {
                    let body = s.dropFirst()
                    let name = body.split(separator: "[", maxSplits: 1).first.map(String.init) ?? String(body)
                    out[k] = ids.contains(name) ? .string("#" + prefix + "." + body) : value
                } else {
                    out[k] = qualify(value, ids: ids, prefix: prefix, isRoot: false)
                }
            }
            return .object(out)
        default:
            return v
        }
    }

    // MARK: Patches on JSON

    /// Layout merge, as `Skin2Layout.merged(with:)` does on typed values.
    static func mergeLayout(_ base: Skin2JSON, _ patch: Skin2JSON) -> Skin2JSON {
        guard case .object(var out) = base, case .object(let p) = patch else { return patch }
        for (k, v) in p {
            if v.isNull {
                out.removeValue(forKey: k)
            } else if mergedLayoutKeys.contains(k), case .object(var sub) = out[k] ?? .null, case .object(let ps) = v {
                for (sk, sv) in ps { if sv.isNull { sub.removeValue(forKey: sk) } else { sub[sk] = sv } }
                out[k] = .object(sub)
            } else {
                out[k] = v
            }
        }
        return .object(out)
    }

    /// Sets node fields from a variant patch: `layout` merges, `null` removes a field, anything else replaces it.
    static func applyFields(_ fields: [String: Skin2JSON], to node: inout [String: Skin2JSON]) {
        for (k, v) in fields {
            if k == "layout", let base = node["layout"], !v.isNull {
                node["layout"] = mergeLayout(base, v)
            } else if v.isNull {
                node.removeValue(forKey: k)
            } else {
                node[k] = v
            }
        }
    }

    static func apply(variant name: String, from variants: Skin2JSON, to root: inout Skin2JSON) throws {
        let vp = Skin2Pointer.appending("/variants", name)
        guard let variant = variants[name] else { throw Skin2Error("/variants", "no variant named \"\(name)\"") }
        guard let patches = (variant["patch"] ?? .array([])).arrayValue else { throw Skin2Error(vp + "/patch", "patch is an array") }
        for (i, patch) in patches.enumerated() {
            let pp = Skin2Pointer.appending(vp + "/patch", i)
            guard case .object(var fields) = patch, let target = fields["target"]?.stringValue, target.hasPrefix("#") else {
                throw Skin2Error(pp, "a variant patch is {\"target\": \"#id\", …fields}")
            }
            fields.removeValue(forKey: "target")
            let id = String(target.dropFirst())
            guard patchNode(&root, id: id, fields: fields) else { throw Skin2Error(pp + "/target", "no node with id \"\(id)\"") }
        }
    }

    static func patchNode(_ v: inout Skin2JSON, id: String, fields: [String: Skin2JSON]) -> Bool {
        guard case .object(var o) = v else { return false }
        if o["id"]?.stringValue == id {
            applyFields(fields, to: &o)
            v = .object(o)
            return true
        }
        guard case .array(var children) = o["children"] ?? .null else { return false }
        for i in children.indices where patchNode(&children[i], id: id, fields: fields) {
            o["children"] = .array(children)
            v = .object(o)
            return true
        }
        return false
    }
}
