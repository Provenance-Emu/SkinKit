import Foundation

/// A JSON value. The preprocessor works on these before typed decoding, so tokens, part parameters and variant
/// patches never leak into the typed model. Unlike `JSONSerialization`'s `Any`, a Bool is never a number.
public enum Skin2JSON: Equatable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([Skin2JSON])
    case object([String: Skin2JSON])

    public static func parse(_ data: Data) throws -> Skin2JSON {
        try JSONDecoder().decode(Skin2JSON.self, from: data)
    }

    /// Sorted keys, so the same value always gives the same bytes.
    public func data(pretty: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public var objectValue: [String: Skin2JSON]? { if case .object(let o) = self { return o } else { return nil } }
    public var arrayValue: [Skin2JSON]? { if case .array(let a) = self { return a } else { return nil } }
    public var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }
    public var numberValue: Double? { if case .number(let n) = self { return n } else { return nil } }
    public var boolValue: Bool? { if case .bool(let b) = self { return b } else { return nil } }
    public var isNull: Bool { self == .null }

    public subscript(key: String) -> Skin2JSON? { objectValue?[key] }

    /// The JSON type name used in messages: `object`, `array`, `string`, `number`, `boolean`, `null`.
    public var typeName: String {
        switch self {
        case .null: return "null"
        case .bool: return "boolean"
        case .number: return "number"
        case .string: return "string"
        case .array: return "array"
        case .object: return "object"
        }
    }
}

extension Skin2JSON: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([Skin2JSON].self) { self = .array(a); return }
        self = .object(try c.decode([String: Skin2JSON].self))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n):
            // Integral values print without a fraction, as JavaScript's JSON.stringify does.
            if n == n.rounded(), abs(n) < 9_007_199_254_740_992 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

extension Skin2JSON: ExpressibleByStringLiteral, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: Skin2JSON...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, Skin2JSON)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
    public init(nilLiteral: ()) { self = .null }
}

/// JSON Pointers (RFC 6901) name places in a skin: `/root/children/2/layout/size/width`. The validator, the
/// preprocessor and decoding errors all report them, as the TypeScript port and JSON Schema validators do.
public enum Skin2Pointer {
    public static func appending(_ pointer: String, _ token: String) -> String {
        pointer + "/" + token.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
    }

    public static func appending(_ pointer: String, _ index: Int) -> String { pointer + "/\(index)" }

    /// A decoding error's coding path as a pointer.
    public static func from(codingPath: [CodingKey]) -> String {
        codingPath.reduce("") { pointer, key in
            if let i = key.intValue { return appending(pointer, i) }
            return appending(pointer, key.stringValue)
        }
    }
}

/// A coding key for any string or index.
struct Skin2AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { stringValue = "\(intValue)"; self.intValue = intValue }
}
