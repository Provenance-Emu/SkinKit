import Foundation

// Shapes, paint, strokes, effects, materials and fonts (sections 3 and 5). The resolver does not read these; the
// renderer (#92) and the baker (#94) do. Ranges the schema states are enforced here too, so a skin the schema
// rejects never decodes.

extension KeyedDecodingContainer {
    func ensure(_ ok: Bool, _ key: Key, _ message: @autoclosure () -> String) throws {
        if !ok { throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: message()) }
    }

    func decodeUnit(_ key: Key) throws -> Double? {
        let v = try decodeIfPresent(Double.self, forKey: key)
        if let v { try ensure((0...1).contains(v), key, "must be between 0 and 1, found \(v)") }
        return v
    }
}

/// `#RRGGBB` or `#RRGGBBAA`, sRGB.
public struct Skin2Color: Equatable, Hashable, Sendable, Decodable, CustomStringConvertible {
    public static let pattern = "^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"
    public var red: Double, green: Double, blue: Double, alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    public init?(hex: String) {
        guard hex.range(of: Self.pattern, options: .regularExpression) != nil, let v = UInt64(hex.dropFirst(), radix: 16) else {
            return nil
        }
        let hasAlpha = hex.count == 9
        let shift: UInt64 = hasAlpha ? 8 : 0
        red = Double((v >> (16 + shift)) & 0xFF) / 255
        green = Double((v >> (8 + shift)) & 0xFF) / 255
        blue = Double((v >> shift) & 0xFF) / 255
        alpha = hasAlpha ? Double(v & 0xFF) / 255 : 1
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let color = Skin2Color(hex: s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "\"\(s)\" is not a colour: use #RRGGBB or #RRGGBBAA")
        }
        self = color
    }

    public var description: String {
        let b = [red, green, blue, alpha].map { String(format: "%02X", Int(($0 * 255).rounded())) }
        return "#" + b.joined()
    }
}

/// `[x, y]` as fractions of a node's frame.
public struct Skin2UnitPoint: Equatable, Hashable, Sendable, Decodable {
    public var x: Double, y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        guard c.count == 2 else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "a point is [x, y] with two numbers")
        }
        x = try c.decode(Double.self)
        y = try c.decode(Double.self)
    }
}

/// `[colour, at]` or `[colour, opacity, at]`.
public struct Skin2Stop: Equatable, Hashable, Sendable, Decodable {
    public var color: Skin2Color
    public var opacity: Double?
    public var at: Double

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        guard let n = c.count, n == 2 || n == 3 else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "a stop is [colour, at] or [colour, opacity, at]")
        }
        color = try c.decode(Skin2Color.self)
        if n == 3 { opacity = try c.decode(Double.self) }
        at = try c.decode(Double.self)
        guard (0...1).contains(at), (0...1).contains(opacity ?? 0) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "stop opacity and position are between 0 and 1")
        }
    }
}

public enum Skin2PaintType: String, Codable, Sendable, CaseIterable { case solid, linear, radial, angular, image }
public enum Skin2ImageMode: String, Codable, Sendable, CaseIterable { case fit, fill, stretch, tile }

/// A fill (5.1). Fields beyond `type` depend on it; the decoder requires the ones each type needs.
public struct Skin2Paint: Equatable, Hashable, Sendable, Decodable {
    public var type: Skin2PaintType
    public var color: Skin2Color?
    public var opacity: Double?
    public var start: Skin2UnitPoint?
    public var end: Skin2UnitPoint?
    public var center: Skin2UnitPoint?
    /// Radial: fraction of the frame's longer side.
    public var radius: Double?
    /// Angular: degrees, clockwise from +x.
    public var startAngle: Double?
    public var stops: [Skin2Stop]
    public var src: String?
    /// Image paint: `tile`, `fit` or `fill`.
    public var mode: Skin2ImageMode?
    public var scale: Double?

    enum K: String, CodingKey { case type, color, opacity, start, end, center, radius, startAngle, stops, src, mode, scale }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        type = try c.decode(Skin2PaintType.self, forKey: .type)
        color = try c.decodeIfPresent(Skin2Color.self, forKey: .color)
        opacity = try c.decodeUnit(.opacity)
        start = try c.decodeIfPresent(Skin2UnitPoint.self, forKey: .start)
        end = try c.decodeIfPresent(Skin2UnitPoint.self, forKey: .end)
        center = try c.decodeIfPresent(Skin2UnitPoint.self, forKey: .center)
        radius = try c.decodeIfPresent(Double.self, forKey: .radius)
        startAngle = try c.decodeIfPresent(Double.self, forKey: .startAngle)
        stops = try c.decodeIfPresent([Skin2Stop].self, forKey: .stops) ?? []
        src = try c.decodeIfPresent(String.self, forKey: .src)
        mode = try c.decodeIfPresent(Skin2ImageMode.self, forKey: .mode)
        scale = try c.decodeIfPresent(Double.self, forKey: .scale)
        if let radius { try c.ensure(radius > 0, .radius, "radius must be above 0") }
        if let scale { try c.ensure(scale > 0, .scale, "scale must be above 0") }
        switch type {
        case .solid:
            try c.ensure(color != nil, .color, "a solid paint needs a color")
        case .linear:
            try c.ensure(start != nil, .start, "a linear paint needs start")
            try c.ensure(end != nil, .end, "a linear paint needs end")
            try c.ensure(stops.count >= 2, .stops, "a gradient needs at least two stops")
        case .radial:
            try c.ensure(center != nil, .center, "a radial paint needs center")
            try c.ensure(radius != nil, .radius, "a radial paint needs radius")
            try c.ensure(stops.count >= 2, .stops, "a gradient needs at least two stops")
        case .angular:
            try c.ensure(center != nil, .center, "an angular paint needs center")
            try c.ensure(stops.count >= 2, .stops, "a gradient needs at least two stops")
        case .image:
            try c.ensure(src != nil, .src, "an image paint needs src")
            try c.ensure(mode != .stretch, .mode, "an image paint's mode is tile, fit or fill")
        }
    }
}

public enum Skin2StrokeAlign: String, Codable, Sendable, CaseIterable { case center, inner, outer }
public enum Skin2LineCap: String, Codable, Sendable, CaseIterable { case butt, round, square }
public enum Skin2LineJoin: String, Codable, Sendable, CaseIterable { case miter, round, bevel }

/// A stroke (5.2). Inner and outer strokes are a double-width stroke clipped to, or out of, the path.
public struct Skin2Stroke: Equatable, Hashable, Sendable, Decodable {
    public var color: Skin2Color
    public var opacity: Double?
    public var width: Skin2Length
    public var align: Skin2StrokeAlign
    public var dash: [Skin2Length]
    public var cap: Skin2LineCap
    public var join: Skin2LineJoin

    enum K: String, CodingKey { case color, opacity, width, align, dash, cap, join }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        color = try c.decode(Skin2Color.self, forKey: .color)
        opacity = try c.decodeUnit(.opacity)
        width = try c.decode(Skin2Length.self, forKey: .width)
        align = try c.decodeIfPresent(Skin2StrokeAlign.self, forKey: .align) ?? .center
        dash = try c.decodeIfPresent([Skin2Length].self, forKey: .dash) ?? []
        cap = try c.decodeIfPresent(Skin2LineCap.self, forKey: .cap) ?? .butt
        join = try c.decodeIfPresent(Skin2LineJoin.self, forKey: .join) ?? .miter
    }
}

public enum Skin2EffectType: String, Codable, Sendable, CaseIterable { case shadow, blur, blend, ci }
public enum Skin2BlendMode: String, Codable, Sendable, CaseIterable { case normal, multiply, screen, overlay, softLight, plus }

/// An effect (5.3). Order: every shadow (listed order, under the content), the content, blur, then blend.
public struct Skin2Effect: Equatable, Hashable, Sendable, Decodable {
    public var type: Skin2EffectType
    public var color: Skin2Color?
    public var opacity: Double?
    /// Shadow or blur radius; a Gaussian with σ = radius / 2.
    public var radius: Skin2Length?
    /// Shadow offset `[x, y]`.
    public var offset: [Skin2Length]
    public var spread: Skin2Length?
    public var inner: Bool
    public var mode: Skin2BlendMode?
    /// Core Image filter name and parameters (`effects.ci`, Apple platforms only).
    public var name: String?
    public var params: [String: Skin2JSON]

    enum K: String, CodingKey { case type, color, opacity, radius, offset, spread, inner, mode, name, params }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        type = try c.decode(Skin2EffectType.self, forKey: .type)
        color = try c.decodeIfPresent(Skin2Color.self, forKey: .color)
        opacity = try c.decodeUnit(.opacity)
        radius = try c.decodeIfPresent(Skin2Length.self, forKey: .radius)
        offset = try c.decodeIfPresent([Skin2Length].self, forKey: .offset) ?? []
        spread = try c.decodeIfPresent(Skin2Length.self, forKey: .spread)
        inner = try c.decodeIfPresent(Bool.self, forKey: .inner) ?? false
        mode = try c.decodeIfPresent(Skin2BlendMode.self, forKey: .mode)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        params = try c.decodeIfPresent([String: Skin2JSON].self, forKey: .params) ?? [:]
        try c.ensure(offset.isEmpty || offset.count == 2, .offset, "offset is [x, y]")
        switch type {
        case .shadow: try c.ensure(color != nil, .color, "a shadow needs a color")
        case .blur: try c.ensure(radius != nil, .radius, "a blur needs a radius")
        case .blend: try c.ensure(mode != nil, .mode, "a blend needs a mode")
        case .ci: try c.ensure(name != nil, .name, "a Core Image effect needs a filter name")
        }
    }
}

public enum Skin2MaterialName: String, Codable, Sendable, CaseIterable { case gloss, brushedMetal, plasticGrain, crt }

/// A named material (5.4), applied after fills and before strokes.
public struct Skin2Material: Equatable, Hashable, Sendable, Decodable {
    public var name: Skin2MaterialName
    public var intensity: Double
    public var params: [String: Skin2JSON]

    enum K: String, CodingKey { case name, intensity, params }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        name = try c.decode(Skin2MaterialName.self, forKey: .name)
        intensity = try c.decodeUnit(.intensity) ?? 1
        params = try c.decodeIfPresent([String: Skin2JSON].self, forKey: .params) ?? [:]
    }
}

public enum Skin2FontWeight: String, Codable, Sendable, CaseIterable { case regular, medium, semibold, bold }

public struct Skin2Font: Equatable, Hashable, Sendable, Decodable {
    /// A font file name in `assets/fonts/`, or nil for the renderer's bundled default.
    public var family: String?
    /// Points times the unit; never scaled by the frame.
    public var size: Skin2Length
    public var weight: Skin2FontWeight

    enum K: String, CodingKey { case family, size, weight }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        family = try c.decodeIfPresent(String.self, forKey: .family)
        size = try c.decode(Skin2Length.self, forKey: .size)
        weight = try c.decodeIfPresent(Skin2FontWeight.self, forKey: .weight) ?? .regular
    }
}

public enum Skin2ShapeKind: String, Codable, Sendable, CaseIterable {
    case rect, squircle, ellipse, capsule, polygon, star, arc, line, cross, kidney, trapezoid, path
}

/// A shape (section 3). `circle` decodes as `ellipse`. Parameters the kind doesn't use are ignored.
public struct Skin2Shape: Equatable, Hashable, Sendable, Decodable {
    public static let maxPathBytes = 4096

    public var kind: Skin2ShapeKind
    public var cornerRadius: Skin2Length?
    /// `rect`: per-corner radii `[topLeft, topRight, bottomRight, bottomLeft]`.
    public var corners: [Skin2Length]?
    public var sides: Int?
    /// Degrees, clockwise.
    public var rotation: Double?
    public var points: Int?
    public var innerRatio: Double?
    public var startAngle: Double?
    public var endAngle: Double?
    /// `arc`: inner radius as a fraction; a ring sector when above 0.
    public var inner: Double?
    public var from: Skin2UnitPoint?
    public var to: Skin2UnitPoint?
    public var armRatio: Double?
    public var bulge: Double?
    public var taper: Double?
    /// `path`: SVG path data, stretched from `box` to the frame.
    public var d: String?
    public var box: [Double]?

    enum K: String, CodingKey {
        case kind, cornerRadius, corners, sides, rotation, points, innerRatio, startAngle, endAngle, inner, from, to,
             armRatio, bulge, taper, d, box
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        let raw = try c.decode(String.self, forKey: .kind)
        guard let k = raw == "circle" ? .ellipse : Skin2ShapeKind(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unknown shape kind \"\(raw)\"")
        }
        kind = k
        cornerRadius = try c.decodeIfPresent(Skin2Length.self, forKey: .cornerRadius)
        corners = try c.decodeIfPresent([Skin2Length].self, forKey: .corners)
        sides = try c.decodeIfPresent(Int.self, forKey: .sides)
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation)
        points = try c.decodeIfPresent(Int.self, forKey: .points)
        innerRatio = try c.decodeUnit(.innerRatio)
        startAngle = try c.decodeIfPresent(Double.self, forKey: .startAngle)
        endAngle = try c.decodeIfPresent(Double.self, forKey: .endAngle)
        inner = try c.decodeUnit(.inner)
        from = try c.decodeIfPresent(Skin2UnitPoint.self, forKey: .from)
        to = try c.decodeIfPresent(Skin2UnitPoint.self, forKey: .to)
        armRatio = try c.decodeUnit(.armRatio)
        bulge = try c.decodeUnit(.bulge)
        taper = try c.decodeIfPresent(Double.self, forKey: .taper)
        d = try c.decodeIfPresent(String.self, forKey: .d)
        box = try c.decodeIfPresent([Double].self, forKey: .box)

        if let corners { try c.ensure(corners.count == 4, .corners, "corners is [topLeft, topRight, bottomRight, bottomLeft]") }
        if let sides { try c.ensure(sides >= 3, .sides, "a polygon has at least 3 sides") }
        if let points { try c.ensure(points >= 3, .points, "a star has at least 3 points") }
        if let taper { try c.ensure(taper >= 0 && taper < 0.5, .taper, "taper is at least 0 and below 0.5") }
        if let d { try c.ensure(d.utf8.count <= Self.maxPathBytes, .d, "path data is at most \(Self.maxPathBytes) bytes") }
        if let box {
            try c.ensure(box.count == 4 && box[2] > 0 && box[3] > 0, .box, "box is [x, y, width, height] with a positive size")
        }
        switch kind {
        case .polygon: try c.ensure(sides != nil, .sides, "a polygon needs sides")
        case .star: try c.ensure(points != nil, .points, "a star needs points")
        case .arc:
            try c.ensure(startAngle != nil, .startAngle, "an arc needs startAngle")
            try c.ensure(endAngle != nil, .endAngle, "an arc needs endAngle")
        case .line:
            try c.ensure(from != nil, .from, "a line needs from")
            try c.ensure(to != nil, .to, "a line needs to")
        case .path:
            try c.ensure(d != nil, .d, "a path needs d")
            try c.ensure(box != nil, .box, "a path needs box")
        default: break
        }
    }
}
