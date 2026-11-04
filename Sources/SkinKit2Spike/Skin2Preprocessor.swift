// SkinKit2Spike: THROWAWAY code for the format 2.0 spike (SkinKit#24). Not shipped.
//
// Expands a raw 2.0 JSON tree before typed decoding:
//   - `$name`  token references (tokens, then the active theme's overrides)
//   - `@name`  part parameters
//   - `{ "use": "part", "with": {...}, ...extra }` part instantiation; extra keys (id, layout,
//     when, requiresFlag) are merged over the part's node.
// Working on `Any` JSON keeps the typed model free of substitution concerns.

import Foundation

public enum Skin2PreprocessError: Error, CustomStringConvertible {
    case unknownToken(String)
    case unknownParam(String)
    case unknownPart(String)
    case notAnObject

    public var description: String {
        switch self {
        case .unknownToken(let t): return "unknown token $\(t)"
        case .unknownParam(let p): return "unknown part parameter @\(p)"
        case .unknownPart(let p): return "unknown part \(p)"
        case .notAnObject: return "skin root is not a JSON object"
        }
    }
}

public struct Skin2Preprocessor {
    let tokens: [String: Any]
    let parts: [String: Any]

    public init(document: [String: Any], theme: String? = nil) throws {
        var tokens = document["tokens"] as? [String: Any] ?? [:]
        if let theme, let themes = document["themes"] as? [String: Any], let overrides = themes[theme] as? [String: Any] {
            overrides.forEach { tokens[$0.key] = $0.value }
        }
        self.tokens = tokens
        self.parts = document["parts"] as? [String: Any] ?? [:]
    }

    /// The document with tokens, params and parts expanded; `tokens`, `themes` and `parts` removed.
    public static func expand(_ raw: Any, theme: String? = nil) throws -> [String: Any] {
        guard var document = raw as? [String: Any] else { throw Skin2PreprocessError.notAnObject }
        let pre = try Skin2Preprocessor(document: document, theme: theme)
        document["root"] = try pre.expand(document["root"] as Any, params: [:])
        document.removeValue(forKey: "tokens")
        document.removeValue(forKey: "themes")
        document.removeValue(forKey: "parts")
        return document
    }

    func expand(_ value: Any, params: [String: Any]) throws -> Any {
        if let string = value as? String {
            return try substitute(string, params: params)
        }
        if let array = value as? [Any] {
            return try array.map { try expand($0, params: params) }
        }
        guard var object = value as? [String: Any] else { return value }
        if let partName = object["use"] as? String {
            guard let part = parts[partName] as? [String: Any], let node = part["node"] as? [String: Any] else {
                throw Skin2PreprocessError.unknownPart(partName)
            }
            var callParams = part["params"] as? [String: Any] ?? [:]
            let with = object["with"] as? [String: Any] ?? [:]
            // Arguments are evaluated in the caller's scope (they may use the caller's @params and $tokens).
            for (key, arg) in with { callParams[key] = try expand(arg, params: params) }
            for (key, def) in callParams where with[key] == nil { callParams[key] = try expand(def, params: params) }
            var expanded = try expand(node, params: callParams) as? [String: Any] ?? [:]
            object.removeValue(forKey: "use")
            object.removeValue(forKey: "with")
            for (key, extra) in object { expanded[key] = try expand(extra, params: params) }
            return expanded
        }
        for (key, child) in object { object[key] = try expand(child, params: params) }
        return object
    }

    /// `$token`, `-$token`, `@param` → the referenced value (numbers stay numbers).
    func substitute(_ string: String, params: [String: Any]) throws -> Any {
        if string.hasPrefix("@") {
            let name = String(string.dropFirst())
            guard let value = params[name] else { throw Skin2PreprocessError.unknownParam(name) }
            return value
        }
        if string.hasPrefix("$") {
            let name = String(string.dropFirst())
            guard let value = tokens[name] else { throw Skin2PreprocessError.unknownToken(name) }
            return value
        }
        if string.hasPrefix("-$") {
            let name = String(string.dropFirst(2))
            guard let value = tokens[name] else { throw Skin2PreprocessError.unknownToken(name) }
            if let number = value as? NSNumber { return -number.doubleValue }
            return value
        }
        return string
    }
}
