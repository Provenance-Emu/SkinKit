import Foundation

// Layout (section 4), conditions (4.6) and the patches `when`, states and variants share.

public enum Skin2HAnchor: String, Codable, Sendable, CaseIterable { case leading, center, trailing }
public enum Skin2VAnchor: String, Codable, Sendable, CaseIterable { case top, center, bottom }

/// The area a node anchors to (section 2): its parent (default), the canvas, the safe area, the first screen
/// node, or `#id`, any node resolved earlier in document order.
public enum Skin2Area: Equatable, Hashable, Sendable, Decodable, CustomStringConvertible {
    case parent, canvas, safeArea, screen
    case node(String)

    /// Node ids: a letter or `_`, then letters, digits, `_`, `-` and `.` (part instances scope inner ids with `.`).
    public static let idBody = "[A-Za-z_][A-Za-z0-9_.-]*"
    public static let idPattern = "^" + idBody + "$"

    public init?(string: String) {
        switch string {
        case "parent": self = .parent
        case "canvas": self = .canvas
        case "safeArea": self = .safeArea
        case "screen": self = .screen
        default:
            guard string.hasPrefix("#"), String(string.dropFirst()).range(of: Self.idPattern, options: .regularExpression) != nil else {
                return nil
            }
            self = .node(String(string.dropFirst()))
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let area = Skin2Area(string: s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "\"\(s)\" is not an area: parent, canvas, safeArea, screen or #id")
        }
        self = area
    }

    public var description: String {
        switch self {
        case .parent: return "parent"
        case .canvas: return "canvas"
        case .safeArea: return "safeArea"
        case .screen: return "screen"
        case .node(let id): return "#" + id
        }
    }
}

/// Which keys of an object were present with an explicit `null`. In a patch, `null` clears the field.
func skin2NullKeys(_ decoder: Decoder) -> Set<String> {
    guard let c = try? decoder.container(keyedBy: Skin2AnyKey.self) else { return [] }
    return Set(c.allKeys.filter { (try? c.decodeNil(forKey: $0)) == true }.map(\.stringValue))
}

public struct Skin2SizeLengths: Equatable, Hashable, Sendable, Decodable {
    public var width: Skin2Length?
    public var height: Skin2Length?
    /// Keys a patch set to `null`.
    public var cleared: Set<String> = []

    public init(width: Skin2Length? = nil, height: Skin2Length? = nil) { self.width = width; self.height = height }

    enum K: String, CodingKey { case width, height }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        width = try c.decodeIfPresent(Skin2Length.self, forKey: .width)
        height = try c.decodeIfPresent(Skin2Length.self, forKey: .height)
        cleared = skin2NullKeys(decoder)
    }

    func merged(with p: Skin2SizeLengths) -> Skin2SizeLengths {
        var out = self
        if let v = p.width { out.width = v } else if p.cleared.contains("width") { out.width = nil }
        if let v = p.height { out.height = v } else if p.cleared.contains("height") { out.height = nil }
        out.cleared = []
        return out
    }
}

public struct Skin2OffsetLengths: Equatable, Hashable, Sendable, Decodable {
    public var x: Skin2Length?
    public var y: Skin2Length?
    public var cleared: Set<String> = []

    public init(x: Skin2Length? = nil, y: Skin2Length? = nil) { self.x = x; self.y = y }

    enum K: String, CodingKey { case x, y }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        x = try c.decodeIfPresent(Skin2Length.self, forKey: .x)
        y = try c.decodeIfPresent(Skin2Length.self, forKey: .y)
        cleared = skin2NullKeys(decoder)
    }

    func merged(with p: Skin2OffsetLengths) -> Skin2OffsetLengths {
        var out = self
        if let v = p.x { out.x = v } else if p.cleared.contains("x") { out.x = nil }
        if let v = p.y { out.y = v } else if p.cleared.contains("y") { out.y = nil }
        out.cleared = []
        return out
    }
}

public struct Skin2Anchor: Equatable, Hashable, Sendable, Decodable {
    public var x: Skin2HAnchor?
    public var y: Skin2VAnchor?
    public var to: Skin2Area?
    public var cleared: Set<String> = []

    public init(x: Skin2HAnchor? = nil, y: Skin2VAnchor? = nil, to: Skin2Area? = nil) { self.x = x; self.y = y; self.to = to }

    enum K: String, CodingKey { case x, y, to }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        x = try c.decodeIfPresent(Skin2HAnchor.self, forKey: .x)
        y = try c.decodeIfPresent(Skin2VAnchor.self, forKey: .y)
        to = try c.decodeIfPresent(Skin2Area.self, forKey: .to)
        cleared = skin2NullKeys(decoder)
    }

    func merged(with p: Skin2Anchor) -> Skin2Anchor {
        var out = self
        if let v = p.x { out.x = v } else if p.cleared.contains("x") { out.x = nil }
        if let v = p.y { out.y = v } else if p.cleared.contains("y") { out.y = nil }
        if let v = p.to { out.to = v } else if p.cleared.contains("to") { out.to = nil }
        out.cleared = []
        return out
    }
}

public struct Skin2Span: Equatable, Hashable, Sendable, Decodable {
    public var columns: Int
    public var rows: Int

    public init(columns: Int = 1, rows: Int = 1) { self.columns = columns; self.rows = rows }

    enum K: String, CodingKey { case columns, rows }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        columns = try c.decodeIfPresent(Int.self, forKey: .columns) ?? 1
        rows = try c.decodeIfPresent(Int.self, forKey: .rows) ?? 1
        try c.ensure(columns >= 1, .columns, "span columns is at least 1")
        try c.ensure(rows >= 1, .rows, "span rows is at least 1")
    }
}

/// A node's layout (4.2–4.4). Absent means "fill the parent".
public struct Skin2Layout: Equatable, Hashable, Sendable, Decodable {
    /// `[x, y, width, height]` in the parent (lengths; numbers are points at reference scale).
    public var frame: [Skin2Length]?
    /// Fill the parent minus this.
    public var inset: Skin2EdgeLengths?
    public var size: Skin2SizeLengths?
    /// width / height; gives the missing axis of `size`.
    public var aspect: Double?
    public var minSize: Skin2SizeLengths?
    public var maxSize: Skin2SizeLengths?
    public var anchor: Skin2Anchor?
    public var offset: Skin2OffsetLengths?
    /// Cells a grid child covers.
    public var span: Skin2Span?
    /// Top-level keys a patch set to `null`.
    public var cleared: Set<String> = []

    public init(frame: [Skin2Length]? = nil, inset: Skin2EdgeLengths? = nil, size: Skin2SizeLengths? = nil, aspect: Double? = nil,
                minSize: Skin2SizeLengths? = nil, maxSize: Skin2SizeLengths? = nil, anchor: Skin2Anchor? = nil,
                offset: Skin2OffsetLengths? = nil, span: Skin2Span? = nil) {
        self.frame = frame; self.inset = inset; self.size = size; self.aspect = aspect; self.minSize = minSize
        self.maxSize = maxSize; self.anchor = anchor; self.offset = offset; self.span = span
    }

    enum K: String, CodingKey { case frame, inset, size, aspect, minSize, maxSize, anchor, offset, span }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        frame = try c.decodeIfPresent([Skin2Length].self, forKey: .frame)
        inset = try c.decodeIfPresent(Skin2EdgeLengths.self, forKey: .inset)
        size = try c.decodeIfPresent(Skin2SizeLengths.self, forKey: .size)
        aspect = try c.decodeIfPresent(Double.self, forKey: .aspect)
        minSize = try c.decodeIfPresent(Skin2SizeLengths.self, forKey: .minSize)
        maxSize = try c.decodeIfPresent(Skin2SizeLengths.self, forKey: .maxSize)
        anchor = try c.decodeIfPresent(Skin2Anchor.self, forKey: .anchor)
        offset = try c.decodeIfPresent(Skin2OffsetLengths.self, forKey: .offset)
        span = try c.decodeIfPresent(Skin2Span.self, forKey: .span)
        cleared = skin2NullKeys(decoder)
        if let frame { try c.ensure(frame.count == 4, .frame, "frame is [x, y, width, height]") }
        if let aspect { try c.ensure(aspect > 0, .aspect, "aspect must be above 0") }
    }

    /// Applies a patch (a `when` entry, a state or a variant). `size`, `minSize`, `maxSize`, `anchor` and
    /// `offset` merge field by field, so `{"size": {"width": 96}}` keeps the height; every other field is
    /// replaced whole. `null` clears a field at either level.
    public func merged(with p: Skin2Layout) -> Skin2Layout {
        var out = self
        func pick<T>(_ base: T?, _ patch: T?, _ key: String, merge: ((T, T) -> T)? = nil) -> T? {
            if let patch {
                if let base, let merge { return merge(base, patch) }
                return patch
            }
            return p.cleared.contains(key) ? nil : base
        }
        out.frame = pick(frame, p.frame, "frame")
        out.inset = pick(inset, p.inset, "inset")
        out.size = pick(size, p.size, "size") { $0.merged(with: $1) }
        out.aspect = pick(aspect, p.aspect, "aspect")
        out.minSize = pick(minSize, p.minSize, "minSize") { $0.merged(with: $1) }
        out.maxSize = pick(maxSize, p.maxSize, "maxSize") { $0.merged(with: $1) }
        out.anchor = pick(anchor, p.anchor, "anchor") { $0.merged(with: $1) }
        out.offset = pick(offset, p.offset, "offset") { $0.merged(with: $1) }
        out.span = pick(span, p.span, "span")
        out.cleared = []
        return out
    }
}

public enum Skin2Orientation: String, Codable, Sendable, CaseIterable { case portrait, landscape }
public enum Skin2Device: String, Codable, Sendable, CaseIterable { case iphone, ipad, tv, mac, web }
public enum Skin2DisplayType: String, Codable, Sendable, CaseIterable { case standard, edgeToEdge, splitView }

/// A condition (4.6): every key present must match. An empty condition always holds.
public struct Skin2Condition: Equatable, Hashable, Sendable, Decodable {
    public var orientation: Skin2Orientation?
    public var device: Skin2Device?
    public var displayType: Skin2DisplayType?
    /// An app-supplied flag (`microphone`, `keypadShown`, `altToggled`).
    public var flag: String?
    public var minWidth: Double?
    public var minHeight: Double?
    public var theme: String?
    public var variant: String?

    public init(orientation: Skin2Orientation? = nil, device: Skin2Device? = nil, displayType: Skin2DisplayType? = nil,
                flag: String? = nil, minWidth: Double? = nil, minHeight: Double? = nil, theme: String? = nil, variant: String? = nil) {
        self.orientation = orientation; self.device = device; self.displayType = displayType; self.flag = flag
        self.minWidth = minWidth; self.minHeight = minHeight; self.theme = theme; self.variant = variant
    }

    static let keys: Set<String> = ["orientation", "device", "displayType", "flag", "minWidth", "minHeight", "theme", "variant"]
}

/// `visible`: a Boolean, or one condition.
public enum Skin2Visibility: Equatable, Hashable, Sendable, Decodable {
    case always(Bool)
    case when(Skin2Condition)

    public init(from decoder: Decoder) throws {
        if let b = try? decoder.singleValueContainer().decode(Bool.self) { self = .always(b); return }
        self = .when(try Skin2Condition(from: decoder))
    }
}

/// A patch: what a `when` entry, a state or a variant may change on a node. `when` and states carry these
/// fields; variants may set any node field (they apply to the JSON before decoding; see `Skin2Preprocessor`).
public struct Skin2Patch: Equatable, Hashable, Sendable, Decodable {
    /// `#id`, or `#id[i]` for copy `i` of a repeated node. States only.
    public var target: String?
    public var layout: Skin2Layout?
    public var visible: Skin2Visibility?
    public var opacity: Double?
    public var fills: [Skin2Paint]?
    public var strokes: [Skin2Stroke]?
    public var text: String?
    /// Top-level keys set to `null` (`"visible": null` restores the default).
    public var cleared: Set<String> = []

    public static let targetPattern = "^#[A-Za-z_][A-Za-z0-9_.-]*(\\[[0-9]+\\])?$"

    enum K: String, CodingKey { case target, layout, visible, opacity, fills, strokes, text }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        target = try c.decodeIfPresent(String.self, forKey: .target)
        layout = try c.decodeIfPresent(Skin2Layout.self, forKey: .layout)
        visible = try c.decodeIfPresent(Skin2Visibility.self, forKey: .visible)
        opacity = try c.decodeUnit(.opacity)
        fills = try c.decodeIfPresent([Skin2Paint].self, forKey: .fills)
        strokes = try c.decodeIfPresent([Skin2Stroke].self, forKey: .strokes)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        cleared = skin2NullKeys(decoder)
        if let target {
            try c.ensure(target.range(of: Self.targetPattern, options: .regularExpression) != nil, .target,
                         "a target is #id or #id[index]")
        }
    }

    /// The target's node id and copy index.
    public var targetID: (id: String, copy: Int?)? {
        guard let target, target.hasPrefix("#") else { return nil }
        let body = target.dropFirst()
        if let open = body.firstIndex(of: "["), body.hasSuffix("]") {
            return (String(body[..<open]), Int(body[body.index(after: open)..<body.index(before: body.endIndex)]))
        }
        return (String(body), nil)
    }

    /// The node with this patch applied.
    public func apply(to node: Skin2Node) -> Skin2Node {
        var n = node
        if let layout { n.layout = (n.layout ?? Skin2Layout()).merged(with: layout) } else if cleared.contains("layout") { n.layout = nil }
        if let visible { n.visible = visible } else if cleared.contains("visible") { n.visible = nil }
        if let opacity { n.opacity = opacity } else if cleared.contains("opacity") { n.opacity = nil }
        if let fills { n.fills = fills }
        if let strokes { n.strokes = strokes }
        if let text { n.text = text }
        return n
    }
}

/// A `when` entry: a condition and the patch to apply when it holds.
public struct Skin2Conditional: Equatable, Hashable, Sendable, Decodable {
    public var condition: Skin2Condition
    public var patch: Skin2Patch

    public init(condition: Skin2Condition, patch: Skin2Patch) { self.condition = condition; self.patch = patch }

    public init(from decoder: Decoder) throws {
        condition = try Skin2Condition(from: decoder)
        patch = try Skin2Patch(from: decoder)
        patch.target = nil
    }
}

public enum Skin2StackAxis: String, Codable, Sendable, CaseIterable { case vertical, horizontal }
public enum Skin2Distribute: String, Codable, Sendable, CaseIterable { case packed, spaceBetween }

/// Cross-axis alignment in a stack, horizontal alignment of a grid cell's content. For a horizontal stack,
/// leading/center/trailing mean top/center/bottom.
public enum Skin2Align: String, Codable, Sendable, CaseIterable { case leading, center, trailing }

public struct Skin2Stack: Equatable, Hashable, Sendable, Decodable {
    public var axis: Skin2StackAxis
    public var spacing: Skin2Length?
    public var align: Skin2Align
    public var distribute: Skin2Distribute

    enum K: String, CodingKey { case axis, spacing, align, distribute }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        axis = try c.decode(Skin2StackAxis.self, forKey: .axis)
        spacing = try c.decodeIfPresent(Skin2Length.self, forKey: .spacing)
        align = try c.decodeIfPresent(Skin2Align.self, forKey: .align) ?? .center
        distribute = try c.decodeIfPresent(Skin2Distribute.self, forKey: .distribute) ?? .packed
    }
}

public struct Skin2Grid: Equatable, Hashable, Sendable, Decodable {
    public var columns: Int
    /// Column and row spacing.
    public var spacingX: Skin2Length?
    public var spacingY: Skin2Length?
    public var align: Skin2Align

    enum K: String, CodingKey { case columns, spacing, align }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        columns = try c.decode(Int.self, forKey: .columns)
        try c.ensure(columns >= 1, .columns, "a grid has at least one column")
        align = try c.decodeIfPresent(Skin2Align.self, forKey: .align) ?? .center
        if let json = try c.decodeIfPresent(Skin2JSON.self, forKey: .spacing),
           case .object(let o) = json, o.keys.contains("x") || o.keys.contains("y") {
            let xy = try c.decode(Skin2OffsetLengths.self, forKey: .spacing)
            spacingX = xy.x; spacingY = xy.y
        } else if let l = try c.decodeIfPresent(Skin2Length.self, forKey: .spacing) {
            spacingX = l; spacingY = l
        }
    }
}

public enum Skin2RepeatPivot: String, Codable, Sendable, CaseIterable { case `self`, parent }

/// `repeat` (4.5): the node drawn `count` times; copy `i` gets the transform applied `i` times.
public struct Skin2Repeat: Equatable, Hashable, Sendable, Decodable {
    public static let maxCount = 64

    public var count: Int
    public var offset: Skin2OffsetLengths?
    public var rotate: Double?
    public var scale: Double?
    public var pivot: Skin2RepeatPivot

    enum K: String, CodingKey { case count, offset, rotate, scale, pivot }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        count = try c.decode(Int.self, forKey: .count)
        offset = try c.decodeIfPresent(Skin2OffsetLengths.self, forKey: .offset)
        rotate = try c.decodeIfPresent(Double.self, forKey: .rotate)
        scale = try c.decodeIfPresent(Double.self, forKey: .scale)
        pivot = try c.decodeIfPresent(Skin2RepeatPivot.self, forKey: .pivot) ?? .self
        try c.ensure((1...Self.maxCount).contains(count), .count, "repeat count is 1 to \(Self.maxCount)")
        if let scale { try c.ensure(scale > 0, .scale, "repeat scale must be above 0") }
    }
}
