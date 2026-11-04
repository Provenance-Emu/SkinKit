// SkinKit2Spike: THROWAWAY code for the format 2.0 spike (SkinKit#24). Not shipped.
// The typed draft-2.0 model. Decoded after `Skin2Preprocessor` has expanded tokens and parts.

import Foundation

public struct Skin2Document: Decodable {
    public var formatVersion: String
    public var requires: [String]?
    public var identifier: String
    public var name: String
    public var gameTypes: [String]
    public var reference: Reference
    public var root: Skin2Node

    public struct Reference: Decodable {
        public var shortSide: Double
        public var minScale: Double
        public var maxScale: Double
    }

    /// Loads, preprocesses and decodes a 2.0 JSON file.
    public static func load(data: Data, theme: String? = nil) throws -> Skin2Document {
        let raw = try JSONSerialization.jsonObject(with: data)
        let expanded = try Skin2Preprocessor.expand(raw, theme: theme)
        let data = try JSONSerialization.data(withJSONObject: expanded)
        return try JSONDecoder().decode(Skin2Document.self, from: data)
    }

    public static func loadBundledGameCube(theme: String? = nil) throws -> Skin2Document {
        guard let url = Bundle.module.url(forResource: "gamecube.skin2", withExtension: "json") else {
            throw Skin2PreprocessError.unknownPart("gamecube.skin2.json")
        }
        return try load(data: Data(contentsOf: url), theme: theme)
    }
}

public enum Skin2NodeType: String, Decodable { case group, shape, image, text, control, screen }
public enum Skin2ControlKind: String, Decodable { case button, dpad, thumbstick, trigger, touchSurface }

/// A length: points at reference scale (multiplied by the device unit), or a fraction of the parent.
public enum Skin2Dimension: Decodable, Equatable {
    case points(Double)
    case fraction(Double)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(Double.self) { self = .points(n); return }
        let s = try c.decode(String.self)
        if s.hasSuffix("%"), let f = Double(s.dropLast()) { self = .fraction(f / 100); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "bad dimension \(s)")
    }

    func resolve(parent: Double, unit: Double) -> Double {
        switch self {
        case .points(let p): return p * unit
        case .fraction(let f): return f * parent
        }
    }
}

public struct Skin2Size: Decodable { public var width: Skin2Dimension?; public var height: Skin2Dimension? }
public struct Skin2Offset: Decodable { public var x: Skin2Dimension?; public var y: Skin2Dimension? }

public enum Skin2HAlign: String, Decodable { case leading, center, trailing }
public enum Skin2VAlign: String, Decodable { case top, center, bottom }

public struct Skin2Anchor: Decodable {
    public var x: Skin2HAlign?
    public var y: Skin2VAlign?
    /// "parent" (default), "safeArea", or "#nodeId" (must resolve earlier in document order).
    public var to: String?
}

public struct Skin2Layout: Decodable {
    public var size: Skin2Size?
    public var aspect: Double?
    public var anchor: Skin2Anchor?
    public var offset: Skin2Offset?
    /// Explicit [x, y, w, h] in the parent's coordinates at reference scale (the classic way).
    public var frame: [Double]?
    /// Uniform inset from the parent (fill minus inset).
    public var inset: Skin2Dimension?

    /// `patch` wins field by field. A `null` in the patch (`aspect: null`) clears the field.
    func merged(with patch: Skin2Layout, clearing: Set<String>) -> Skin2Layout {
        var out = self
        if let v = patch.size { out.size = v }
        if let v = patch.aspect { out.aspect = v } else if clearing.contains("aspect") { out.aspect = nil }
        if let v = patch.anchor { out.anchor = v }
        if let v = patch.offset { out.offset = v }
        if let v = patch.frame { out.frame = v }
        if let v = patch.inset { out.inset = v }
        return out
    }
}

public struct Skin2Conditional: Decodable {
    public var orientation: String?
    public var device: String?
    public var layout: Skin2Layout?
    public var hidden: Bool?
    /// Keys the patch explicitly nulls (JSON `null`), recorded so `merged` can clear them.
    public var clears: Set<String> = []

    enum CodingKeys: String, CodingKey { case orientation, device, layout, hidden }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        orientation = try c.decodeIfPresent(String.self, forKey: .orientation)
        device = try c.decodeIfPresent(String.self, forKey: .device)
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden)
        layout = try c.decodeIfPresent(Skin2Layout.self, forKey: .layout)
        if let nested = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: .layout) {
            for key in nested.allKeys where (try? nested.decodeNil(forKey: key)) == true { clears.insert(key.stringValue) }
        }
    }
}

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

public struct Skin2Stack: Decodable {
    public var axis: String
    public var spacing: Skin2Dimension?
    public var align: String?
}

public struct Skin2Repeat: Decodable {
    public var count: Int
    public var rotate: Double?
    public var pivot: String?
}

public struct Skin2Shape: Decodable {
    public var kind: String
    public var cornerRadius: Double?
    public var sides: Int?
    public var rotation: Double?
    public var points: Int?
    public var innerRatio: Double?
    public var d: String?
    public var box: [Double]?
}

public struct Skin2Color: Decodable, Equatable {
    public var r: Double, g: Double, b: Double, a: Double

    public init(r: Double, g: Double, b: Double, a: Double) { self.r = r; self.g = g; self.b = b; self.a = a }

    public init(hex: String) throws {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad color \(hex)"))
        }
        let hasAlpha = s.count == 8
        let shift = hasAlpha ? 8 : 0
        r = Double((v >> (16 + shift)) & 0xFF) / 255
        g = Double((v >> (8 + shift)) & 0xFF) / 255
        b = Double((v >> shift) & 0xFF) / 255
        a = hasAlpha ? Double(v & 0xFF) / 255 : 1
    }

    public init(from decoder: Decoder) throws {
        self = try Skin2Color(hex: try decoder.singleValueContainer().decode(String.self))
    }

    func withOpacity(_ o: Double?) -> Skin2Color {
        guard let o else { return self }
        var c = self; c.a *= o; return c
    }
}

/// `[color, at]` or `[color, opacity, at]`.
public struct Skin2Stop: Decodable {
    public var color: Skin2Color
    public var at: Double

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        let color = try c.decode(Skin2Color.self)
        let first = try c.decode(Double.self)
        if c.isAtEnd { self.color = color; at = first } else { self.color = color.withOpacity(first); at = try c.decode(Double.self) }
    }
}

public struct Skin2Paint: Decodable {
    public var type: String
    public var color: Skin2Color?
    public var opacity: Double?
    public var stops: [Skin2Stop]?
    public var start: [Double]?
    public var end: [Double]?
    public var center: [Double]?
    public var radius: Double?
}

public struct Skin2Stroke: Decodable {
    public var color: Skin2Color
    public var opacity: Double?
    public var width: Double
    public var align: String?
}

public struct Skin2Effect: Decodable {
    public var type: String
    public var color: Skin2Color?
    public var opacity: Double?
    public var radius: Double?
    public var offset: [Double]?
}

public struct Skin2Font: Decodable { public var size: Double; public var weight: String? }
public struct Skin2Hit: Decodable { public var extend: Double? }

public struct Skin2Node: Decodable {
    public var type: Skin2NodeType
    public var id: String?
    public var role: String?
    public var layout: Skin2Layout?
    public var when: [Skin2Conditional]?
    public var requiresFlag: String?
    public var opacity: Double?
    public var stack: Skin2Stack?
    public var `repeat`: Skin2Repeat?
    public var shape: Skin2Shape?
    public var fills: [Skin2Paint]?
    public var strokes: [Skin2Stroke]?
    public var effects: [Skin2Effect]?
    public var text: String?
    public var font: Skin2Font?
    public var color: Skin2Color?
    public var kind: Skin2ControlKind?
    public var input: String?
    public var hit: Skin2Hit?
    public var aspect: Double?
    public var children: [Skin2Node]?
    // `states` (pressed patches) is carried but not rendered by the spike.
}
