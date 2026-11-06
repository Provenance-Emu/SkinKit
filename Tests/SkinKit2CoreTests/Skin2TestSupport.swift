import Foundation
import Testing
@testable import SkinKit2Core

/// Paths into the source tree. The fixtures live outside the test target (`Tests/Format2Fixtures/`) because the
/// TypeScript port vendors the same files, so they are read through `#filePath` rather than as resources.
enum Skin2Paths {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let fixtures = repo.appendingPathComponent("Tests/Format2Fixtures", isDirectory: true)
    static let schema = repo.appendingPathComponent("docs/schema/skin-2.0.schema.json")

    /// `SKIN2_RECORD=1` rewrites the recorded files (and fails the run, so it can't pass in CI).
    static var recording: Bool { ProcessInfo.processInfo.environment["SKIN2_RECORD"] == "1" }

    static let fixtureNames: [String] = {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: fixtures.path)) ?? []
        return names.filter { FileManager.default.fileExists(atPath: fixtures.appendingPathComponent("\($0)/skin.json").path) }.sorted()
    }()

    static func skinData(_ name: String) throws -> Data {
        try Data(contentsOf: fixtures.appendingPathComponent("\(name)/skin.json"))
    }
}

extension Skin2Document {
    static func fixture(_ name: String, theme: String? = nil, variant: String? = nil) throws -> Skin2Document {
        try Skin2Document.load(data: Skin2Paths.skinData(name), theme: theme, variant: variant)
    }

    /// Loads an inline test skin.
    static func inline(_ json: String, theme: String? = nil, variant: String? = nil) throws -> Skin2Document {
        try Skin2Document.load(data: Data(json.utf8), theme: theme, variant: variant)
    }
}

/// A minimal valid skin around `root`'s children, for unit tests.
func skinJSON(children: String, extra: String = "", gameTypes: String = "[\"com.rileytestut.delta.game.snes\"]",
              requires: String = "[\"layout.anchors\", \"layout.stack\", \"layout.grid\", \"layout.repeat\", \"shapes.parametric\"]") -> String {
    """
    { "formatVersion": "2.0", "requires": \(requires), "identifier": "test", "name": "Test", "gameTypes": \(gameTypes),
      "reference": { "shortSide": 390, "minScale": 1, "maxScale": 1.35 } \(extra.isEmpty ? "" : ", " + extra),
      "root": { "type": "group", "children": [ \(children) ] } }
    """
}

extension Skin2Rect {
    func isClose(to other: Skin2Rect, accuracy: Double = 0.001) -> Bool {
        abs(x - other.x) <= accuracy && abs(y - other.y) <= accuracy && abs(width - other.width) <= accuracy && abs(height - other.height) <= accuracy
    }
}

/// A small JSON Schema (draft 2020-12) validator implementing exactly `Skin2Schema.keywords`, so the tests can
/// check fixtures against the published schema without a dependency. `SchemaTests` fails if the schema starts
/// using a keyword this doesn't implement.
struct SchemaValidator {
    let root: Skin2JSON

    func errors(_ instance: Skin2JSON) -> [String] {
        var out: [String] = []
        check(root, instance, "", &out)
        return out
    }

    private func resolve(_ ref: String) -> Skin2JSON {
        precondition(ref.hasPrefix("#/$defs/"), "only local $defs refs: \(ref)")
        return root["$defs"]?[String(ref.dropFirst("#/$defs/".count))] ?? .object([:])
    }

    private func passes(_ schema: Skin2JSON, _ v: Skin2JSON, _ p: String) -> Bool {
        var e: [String] = []
        check(schema, v, p, &e)
        return e.isEmpty
    }

    private static func matchesType(_ t: String, _ v: Skin2JSON) -> Bool {
        switch (t, v) {
        case ("object", .object), ("array", .array), ("string", .string), ("boolean", .bool), ("null", .null), ("number", .number): return true
        case ("integer", .number(let n)): return n == n.rounded()
        default: return false
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func check(_ schema: Skin2JSON, _ v: Skin2JSON, _ p: String, _ errs: inout [String]) {
        guard case .object(let s) = schema else { return }
        if let ref = s["$ref"]?.stringValue { check(resolve(ref), v, p, &errs) }
        if let t = s["type"] {
            let types = t.arrayValue?.compactMap(\.stringValue) ?? [t.stringValue ?? ""]
            if !types.contains(where: { Self.matchesType($0, v) }) { errs.append("\(p): expected \(types.joined(separator: "|")), found \(v.typeName)"); return }
        }
        if let c = s["const"], c != v { errs.append("\(p): expected const \(c)") }
        if let e = s["enum"]?.arrayValue, !e.contains(v) { errs.append("\(p): not one of \(e.compactMap(\.stringValue))") }
        if case .string(let str) = v {
            if let pattern = s["pattern"]?.stringValue, str.range(of: pattern, options: .regularExpression) == nil {
                errs.append("\(p): \"\(str)\" does not match \(pattern)")
            }
            let n = str.unicodeScalars.count
            if let m = s["minLength"]?.numberValue, Double(n) < m { errs.append("\(p): shorter than \(m)") }
            if let m = s["maxLength"]?.numberValue, Double(n) > m { errs.append("\(p): longer than \(m)") }
        }
        if case .number(let n) = v {
            if let m = s["minimum"]?.numberValue, n < m { errs.append("\(p): \(n) < minimum \(m)") }
            if let m = s["maximum"]?.numberValue, n > m { errs.append("\(p): \(n) > maximum \(m)") }
            if let m = s["exclusiveMinimum"]?.numberValue, n <= m { errs.append("\(p): \(n) <= exclusiveMinimum \(m)") }
            if let m = s["exclusiveMaximum"]?.numberValue, n >= m { errs.append("\(p): \(n) >= exclusiveMaximum \(m)") }
        }
        if case .object(let o) = v {
            let props = s["properties"]?.objectValue ?? [:]
            for (k, sub) in props { if let value = o[k] { check(sub, value, Skin2Pointer.appending(p, k), &errs) } }
            for r in s["required"]?.arrayValue?.compactMap(\.stringValue) ?? [] where o[r] == nil { errs.append("\(p): missing \(r)") }
            if let ap = s["additionalProperties"] {
                for (k, value) in o where props[k] == nil {
                    if ap == .bool(false) { errs.append("\(p): unexpected \(k)") } else { check(ap, value, Skin2Pointer.appending(p, k), &errs) }
                }
            }
            if let pn = s["propertyNames"] { for k in o.keys { check(pn, .string(k), Skin2Pointer.appending(p, k), &errs) } }
            if let m = s["minProperties"]?.numberValue, Double(o.count) < m { errs.append("\(p): fewer than \(m) properties") }
            if let m = s["maxProperties"]?.numberValue, Double(o.count) > m { errs.append("\(p): more than \(m) properties") }
        }
        if case .array(let a) = v {
            let prefix = s["prefixItems"]?.arrayValue ?? []
            for (i, sub) in prefix.enumerated() where i < a.count { check(sub, a[i], Skin2Pointer.appending(p, i), &errs) }
            if let items = s["items"] { for i in a.indices where i >= prefix.count { check(items, a[i], Skin2Pointer.appending(p, i), &errs) } }
            if let m = s["minItems"]?.numberValue, Double(a.count) < m { errs.append("\(p): fewer than \(m) items") }
            if let m = s["maxItems"]?.numberValue, Double(a.count) > m { errs.append("\(p): more than \(m) items") }
        }
        if let any = s["anyOf"]?.arrayValue, !any.contains(where: { passes($0, v, p) }) {
            errs.append("\(p): matches none of anyOf")
        }
        if let one = s["oneOf"]?.arrayValue {
            let n = one.filter { passes($0, v, p) }.count
            if n != 1 { errs.append("\(p): matches \(n) of oneOf") }
        }
        if let not = s["not"], passes(not, v, p) { errs.append("\(p): matches not") }
    }

    /// Every keyword used anywhere a schema is expected.
    static func keywords(in schema: Skin2JSON) -> Set<String> {
        var out: Set<String> = []
        func walk(_ s: Skin2JSON) {
            guard case .object(let o) = s else { return }
            out.formUnion(o.keys)
            for key in ["properties", "$defs"] { for sub in o[key]?.objectValue?.values ?? [:].values { walk(sub) } }
            for key in ["anyOf", "oneOf", "prefixItems"] { for sub in o[key]?.arrayValue ?? [] { walk(sub) } }
            for key in ["items", "not", "additionalProperties", "propertyNames"] { if let sub = o[key] { walk(sub) } }
        }
        walk(schema)
        return out
    }
}
