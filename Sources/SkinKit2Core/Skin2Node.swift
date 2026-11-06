import Foundation

public enum Skin2NodeType: String, Codable, Sendable, CaseIterable { case group, shape, image, text, control, screen }

public enum Skin2ControlKind: String, Codable, Sendable, CaseIterable { case button, dpad, thumbstick, trigger, touchSurface, action }

/// What a child of a control is for (6.2): the thumbstick's knob, the part that stays, or art drawn only while
/// pressed.
public enum Skin2ArtRole: String, Codable, Sendable, CaseIterable { case knob, base, highlight }
public enum Skin2ScreenRole: String, Codable, Sendable, CaseIterable { case main, top, bottom, touch }
public enum Skin2ScreenPlacement: String, Codable, Sendable, CaseIterable { case app, controller }
public enum Skin2TextAlign: String, Codable, Sendable, CaseIterable { case leading, center, trailing }

/// A d-pad's four inputs.
public struct Skin2Directions: Equatable, Hashable, Sendable, Decodable {
    public var up: String, down: String, left: String, right: String
    public init(up: String, down: String, left: String, right: String) { self.up = up; self.down = down; self.left = left; self.right = right }
    public var all: [String] { [up, down, left, right] }
}

/// A control's `input`: one classic input name, or a d-pad's `{up, down, left, right}`.
public enum Skin2Input: Equatable, Hashable, Sendable, Decodable {
    case name(String)
    case directions(Skin2Directions)

    public init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) { self = .name(s); return }
        self = .directions(try Skin2Directions(from: decoder))
    }

    public var names: [String] {
        switch self {
        case .name(let n): return [n]
        case .directions(let d): return d.all
        }
    }
}

/// `hit`: the hit frame is the resolved frame outset by `extend` (6.3).
public struct Skin2Hit: Equatable, Hashable, Sendable, Decodable {
    public var extend: Skin2EdgeLengths?
}

/// A control state (6.4): a scale and opacity for the control plus patches on its descendants.
public struct Skin2State: Equatable, Hashable, Sendable, Decodable {
    public static let names: Set<String> = ["pressed", "selected", "pressed.up", "pressed.down", "pressed.left", "pressed.right"]

    public var scale: Double?
    public var opacity: Double?
    public var patch: [Skin2Patch]

    enum K: String, CodingKey { case scale, opacity, patch }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        scale = try c.decodeIfPresent(Double.self, forKey: .scale)
        opacity = try c.decodeUnit(.opacity)
        patch = try c.decodeIfPresent([Skin2Patch].self, forKey: .patch) ?? []
        if let scale { try c.ensure(scale > 0, .scale, "a state's scale must be above 0") }
        try c.ensure(patch.allSatisfy { $0.target != nil }, .patch, "every state patch names a target (#id)")
    }
}

public struct Skin2Haptic: Equatable, Hashable, Sendable, Decodable {
    public var style: String?
    public var intensity: Double?

    enum K: String, CodingKey { case style, intensity }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        style = try c.decodeIfPresent(String.self, forKey: .style)
        intensity = try c.decodeUnit(.intensity)
    }
}

/// A classic screen filter (Provenance only).
public struct Skin2ScreenFilter: Equatable, Hashable, Sendable, Decodable {
    public var name: String
    public var params: [String: Skin2JSON]?
}

/// A node (section 3). One struct for every type: fields that don't belong to `type` are left at their defaults,
/// which keeps patching uniform and matches the JSON. `use`/`with` never reach here: the preprocessor expands
/// them first.
public struct Skin2Node: Equatable, Hashable, Sendable, Decodable {
    public var type: Skin2NodeType
    public var id: String?
    public var layout: Skin2Layout?
    public var when: [Skin2Conditional]
    public var visible: Skin2Visibility?
    public var opacity: Double?
    public var effects: [Skin2Effect]
    public var `repeat`: Skin2Repeat?
    /// `role` on anything but a screen.
    public var role: Skin2ArtRole?

    // group and control
    public var children: [Skin2Node]
    // group
    public var stack: Skin2Stack?
    public var grid: Skin2Grid?

    // shape
    public var shape: Skin2Shape?
    public var fills: [Skin2Paint]
    public var strokes: [Skin2Stroke]
    public var material: Skin2Material?

    // image
    public var src: String?
    public var mode: Skin2ImageMode?
    public var tint: Skin2Color?

    // text
    public var text: String?
    public var font: Skin2Font?
    public var color: Skin2Color?
    public var align: Skin2TextAlign?
    public var fit: Bool?

    // control
    public var kind: Skin2ControlKind?
    public var input: Skin2Input?
    public var inputs: [String]?
    public var hit: Skin2Hit?
    public var travel: Skin2Length?
    public var states: [String: Skin2State]
    public var haptic: Skin2Haptic?

    // screen
    public var aspect: Double?
    /// `role` on a screen.
    public var screenRole: Skin2ScreenRole?
    public var filters: [Skin2ScreenFilter]
    public var placement: Skin2ScreenPlacement?

    public init(type: Skin2NodeType, id: String? = nil, layout: Skin2Layout? = nil, children: [Skin2Node] = []) {
        self.type = type; self.id = id; self.layout = layout; self.children = children
        when = []; effects = []; fills = []; strokes = []; states = [:]; filters = []
    }

    public static let idPattern = Skin2Area.idPattern

    enum K: String, CodingKey {
        case type, id, layout, when, visible, opacity, effects, `repeat`, role, children, stack, grid
        case shape, fills, strokes, material, src, mode, tint, text, font, color, align, fit
        case kind, input, inputs, hit, travel, states, haptic, aspect, filters, placement
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        type = try c.decode(Skin2NodeType.self, forKey: .type)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        if let id {
            try c.ensure(id.range(of: Self.idPattern, options: .regularExpression) != nil, .id,
                         "an id starts with a letter or _ and holds letters, digits, _, - and .")
        }
        layout = try c.decodeIfPresent(Skin2Layout.self, forKey: .layout)
        when = try c.decodeIfPresent([Skin2Conditional].self, forKey: .when) ?? []
        visible = try c.decodeIfPresent(Skin2Visibility.self, forKey: .visible)
        opacity = try c.decodeUnit(.opacity)
        effects = try c.decodeIfPresent([Skin2Effect].self, forKey: .effects) ?? []
        self.repeat = try c.decodeIfPresent(Skin2Repeat.self, forKey: .repeat)
        children = []; fills = []; strokes = []; states = [:]; filters = []
        if type == .screen {
            screenRole = try c.decodeIfPresent(Skin2ScreenRole.self, forKey: .role)
        } else {
            role = try c.decodeIfPresent(Skin2ArtRole.self, forKey: .role)
        }

        switch type {
        case .group:
            children = try c.decodeIfPresent([Skin2Node].self, forKey: .children) ?? []
            stack = try c.decodeIfPresent(Skin2Stack.self, forKey: .stack)
            grid = try c.decodeIfPresent(Skin2Grid.self, forKey: .grid)
            try c.ensure(stack == nil || grid == nil, .grid, "a group has a stack or a grid, not both")
        case .shape:
            shape = try c.decode(Skin2Shape.self, forKey: .shape)
            fills = try c.decodeIfPresent([Skin2Paint].self, forKey: .fills) ?? []
            strokes = try c.decodeIfPresent([Skin2Stroke].self, forKey: .strokes) ?? []
            material = try c.decodeIfPresent(Skin2Material.self, forKey: .material)
        case .image:
            src = try c.decode(String.self, forKey: .src)
            mode = try c.decodeIfPresent(Skin2ImageMode.self, forKey: .mode)
            tint = try c.decodeIfPresent(Skin2Color.self, forKey: .tint)
        case .text:
            text = try c.decode(String.self, forKey: .text)
            font = try c.decodeIfPresent(Skin2Font.self, forKey: .font)
            color = try c.decodeIfPresent(Skin2Color.self, forKey: .color)
            align = try c.decodeIfPresent(Skin2TextAlign.self, forKey: .align)
            fit = try c.decodeIfPresent(Bool.self, forKey: .fit)
        case .control:
            children = try c.decodeIfPresent([Skin2Node].self, forKey: .children) ?? []
            kind = try c.decode(Skin2ControlKind.self, forKey: .kind)
            input = try c.decodeIfPresent(Skin2Input.self, forKey: .input)
            inputs = try c.decodeIfPresent([String].self, forKey: .inputs)
            hit = try c.decodeIfPresent(Skin2Hit.self, forKey: .hit)
            travel = try c.decodeIfPresent(Skin2Length.self, forKey: .travel)
            states = try c.decodeIfPresent([String: Skin2State].self, forKey: .states) ?? [:]
            haptic = try c.decodeIfPresent(Skin2Haptic.self, forKey: .haptic)
            if let bad = states.keys.sorted().first(where: { !Skin2State.names.contains($0) }) {
                throw DecodingError.dataCorruptedError(forKey: .states, in: c,
                    debugDescription: "unknown state \"\(bad)\": use pressed, selected or pressed.up/down/left/right")
            }
        case .screen:
            aspect = try c.decodeIfPresent(Double.self, forKey: .aspect)
            filters = try c.decodeIfPresent([Skin2ScreenFilter].self, forKey: .filters) ?? []
            placement = try c.decodeIfPresent(Skin2ScreenPlacement.self, forKey: .placement)
            if let aspect { try c.ensure(aspect > 0, .aspect, "aspect must be above 0") }
        }
    }

    /// Every input name the control sends: `input` (one name or the d-pad's four) plus `inputs`.
    public var inputNames: [String] { (input?.names ?? []) + (inputs ?? []) }

    /// This node and its descendants, depth first, parents before children.
    public func preorder(_ body: (Skin2Node) -> Void) {
        body(self)
        for child in children { child.preorder(body) }
    }

    public var nodeCount: Int { 1 + children.reduce(0) { $0 + $1.nodeCount } }
}
