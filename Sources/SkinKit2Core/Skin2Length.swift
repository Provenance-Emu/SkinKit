import Foundation

/// A canvas edge, the one variable a length may read (`{"safe": "left"}`).
public enum Skin2Edge: String, Codable, Sendable, CaseIterable {
    case top, left, bottom, right
}

/// A length (section 2).
///
/// | JSON | Case |
/// |---|---|
/// | `8` | `.pt(8)`: points at reference scale, times the unit |
/// | `"50%"` | `.frac(0.5)`: of the parent's size along the axis (or of the named area a node anchors to) |
/// | `{"pt": 8}`, `{"frac": 0.5}` | the same, explicit; part parameters of type `length` must use these |
/// | `{"max": [L, L]}`, `{"min": …}`, `{"sum": …}` | the only operators, nested at most 4 deep |
/// | `{"safe": "left"}` | the safe-area inset on that edge, in canvas points (not scaled); `offset`/`inset` only |
public indirect enum Skin2Length: Equatable, Hashable, Sendable {
    case pt(Double)
    case frac(Double)
    case max([Skin2Length])
    case min([Skin2Length])
    case sum([Skin2Length])
    case safe(Skin2Edge)

    public static let zero = Skin2Length.pt(0)
    public static let maxDepth = 4
    /// `"50%"`, `"-12.5%"`. The schema uses the same pattern.
    public static let percentPattern = "^-?[0-9]+(\\.[0-9]+)?%$"

    /// Operator nesting: a value is 0, `{"max": [8, 4]}` is 1.
    public var depth: Int {
        switch self {
        case .pt, .frac, .safe: return 0
        case .max(let a), .min(let a), .sum(let a): return 1 + (a.map(\.depth).max() ?? 0)
        }
    }

    public var usesSafeArea: Bool {
        switch self {
        case .safe: return true
        case .pt, .frac: return false
        case .max(let a), .min(let a), .sum(let a): return a.contains { $0.usesSafeArea }
        }
    }

    /// Resolves to canvas points. `along` is the size `%` refers to; `unit` scales points.
    public func resolve(along: Double, unit: Double, safeArea: Skin2Insets = .zero) -> Double {
        switch self {
        case .pt(let p): return p * unit
        case .frac(let f): return f * along
        case .safe(let e): return safeArea.value(e)
        case .max(let a): return a.map { $0.resolve(along: along, unit: unit, safeArea: safeArea) }.max() ?? 0
        case .min(let a): return a.map { $0.resolve(along: along, unit: unit, safeArea: safeArea) }.min() ?? 0
        case .sum(let a): return a.reduce(0) { $0 + $1.resolve(along: along, unit: unit, safeArea: safeArea) }
        }
    }

    /// Parses the JSON forms above. Errors name what was wrong; the caller adds the location.
    public init(json: Skin2JSON) throws {
        switch json {
        case .number(let n):
            self = .pt(n)
        case .string(let s):
            guard s.range(of: Self.percentPattern, options: .regularExpression) != nil, let v = Double(s.dropLast()) else {
                throw Skin2LengthError("\"\(s)\" is not a length: use a number of points, \"N%\", or {\"pt\": N}")
            }
            self = .frac(v / 100)
        case .object(let o):
            guard o.count == 1, let (key, value) = o.first else {
                throw Skin2LengthError("a length object has exactly one key: pt, frac, max, min, sum or safe")
            }
            switch key {
            case "pt":
                guard let n = value.numberValue else { throw Skin2LengthError("\"pt\" takes a number") }
                self = .pt(n)
            case "frac":
                guard let n = value.numberValue else { throw Skin2LengthError("\"frac\" takes a number") }
                self = .frac(n)
            case "safe":
                guard let s = value.stringValue, let e = Skin2Edge(rawValue: s) else {
                    throw Skin2LengthError("\"safe\" takes top, left, bottom or right")
                }
                self = .safe(e)
            case "max", "min", "sum":
                guard let items = value.arrayValue, items.count >= 2 else {
                    throw Skin2LengthError("\"\(key)\" takes an array of at least two lengths")
                }
                let parts = try items.map { try Skin2Length(json: $0) }
                self = key == "max" ? .max(parts) : key == "min" ? .min(parts) : .sum(parts)
            default:
                throw Skin2LengthError("unknown length operator \"\(key)\": the only ones are pt, frac, max, min, sum, safe")
            }
        default:
            throw Skin2LengthError("expected a length (number, \"N%\" or a length object), found \(json.typeName)")
        }
        if depth > Self.maxDepth {
            throw Skin2LengthError("length expressions nest at most \(Self.maxDepth) operators deep")
        }
    }
}

public struct Skin2LengthError: Error, CustomStringConvertible {
    public var description: String
    init(_ d: String) { description = d }
}

extension Skin2Length: Decodable {
    public init(from decoder: Decoder) throws {
        let json = try Skin2JSON(from: decoder)
        do { try self.init(json: json) } catch let e as Skin2LengthError {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: e.description))
        }
    }
}

/// Lengths per edge: one length for all four, or `{top, left, bottom, right}` (missing edges are 0).
public struct Skin2EdgeLengths: Equatable, Hashable, Sendable, Decodable {
    public var top: Skin2Length?, left: Skin2Length?, bottom: Skin2Length?, right: Skin2Length?

    public init(top: Skin2Length? = nil, left: Skin2Length? = nil, bottom: Skin2Length? = nil, right: Skin2Length? = nil) {
        self.top = top; self.left = left; self.bottom = bottom; self.right = right
    }

    public init(uniform l: Skin2Length) { self.init(top: l, left: l, bottom: l, right: l) }

    public var all: [Skin2Length] { [top, left, bottom, right].compactMap { $0 } }

    public init(from decoder: Decoder) throws {
        let json = try Skin2JSON(from: decoder)
        if case .object(let o) = json, o.keys.contains(where: { Skin2Edge(rawValue: $0) != nil }) {
            let c = try decoder.container(keyedBy: Skin2AnyKey.self)
            self.init(top: try c.decodeIfPresent(Skin2Length.self, forKey: Skin2AnyKey("top")),
                      left: try c.decodeIfPresent(Skin2Length.self, forKey: Skin2AnyKey("left")),
                      bottom: try c.decodeIfPresent(Skin2Length.self, forKey: Skin2AnyKey("bottom")),
                      right: try c.decodeIfPresent(Skin2Length.self, forKey: Skin2AnyKey("right")))
        } else {
            self.init(uniform: try Skin2Length(from: decoder))
        }
    }

    /// Top and bottom resolve against `height`, left and right against `width`.
    public func resolve(width: Double, height: Double, unit: Double, safeArea: Skin2Insets) -> Skin2Insets {
        Skin2Insets(
            top: top?.resolve(along: height, unit: unit, safeArea: safeArea) ?? 0,
            left: left?.resolve(along: width, unit: unit, safeArea: safeArea) ?? 0,
            bottom: bottom?.resolve(along: height, unit: unit, safeArea: safeArea) ?? 0,
            right: right?.resolve(along: width, unit: unit, safeArea: safeArea) ?? 0)
    }
}
