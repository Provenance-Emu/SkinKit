import Foundation

public enum Skin2PanelPresentation: String, Codable, Sendable, CaseIterable { case fixed, shelf }

/// `panel` on a group: a named accessory area the skin shows only while the app can supply what it needs.
///
/// A `fixed` panel is always shown. A `shelf` has two states: the skin view owns the state and exposes it as the
/// flag `panel.<name>.open`, which the skin's own `when` entries read. While a shelf is closed everything in the
/// group except its handle (and the groups that hold the handle) is absent. The handle is a control of kind
/// `action` whose input is `togglePanel`; its touch toggles the shelf and never reaches the app.
public struct Skin2Panel: Equatable, Hashable, Sendable, Decodable {
    public static let maxNameLength = 64
    /// The most panels a skin may have.
    public static let maxPanels = 6
    /// A name appears inside a flag (`panel.<name>.open`), so it has no dots.
    public static let namePattern = "^[A-Za-z_][A-Za-z0-9_-]*$"
    public static let handlePattern = "^#" + Skin2Area.idBody + "$"
    /// Flags with this prefix belong to the skin view; an app may not supply them.
    public static let flagPrefix = "panel."
    /// The app action a shelf's handle sends. The skin view takes it; it never reaches the app.
    public static let toggleInput = "togglePanel"

    /// Unique in the document; used in flags and reports.
    public var name: String
    /// Spoken by VoiceOver for the panel and its handle.
    public var label: String?
    /// Capabilities the app must supply; without any of them the whole group is absent.
    public var needs: [String]
    public var presentation: Skin2PanelPresentation
    /// `#id` of the shelf's handle, a control inside the group.
    public var handle: String?
    /// A shelf's state the first time the skin is shown.
    public var open: Bool

    public init(name: String, label: String? = nil, needs: [String] = [], presentation: Skin2PanelPresentation = .fixed,
                handle: String? = nil, open: Bool = false) {
        self.name = name; self.label = label; self.needs = needs; self.presentation = presentation; self.handle = handle; self.open = open
    }

    enum K: String, CodingKey { case name, label, needs, presentation, handle, open }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        name = try c.decode(String.self, forKey: .name)
        try c.ensure(name.count <= Self.maxNameLength, .name, "a panel name is at most \(Self.maxNameLength) characters")
        try c.ensure(name.range(of: Self.namePattern, options: .regularExpression) != nil, .name,
                     "a panel name starts with a letter or _ and holds letters, digits, _ and -")
        label = try c.decodeIfPresent(String.self, forKey: .label)
        needs = try c.decodeIfPresent([String].self, forKey: .needs) ?? []
        presentation = try c.decodeIfPresent(Skin2PanelPresentation.self, forKey: .presentation) ?? .fixed
        handle = try c.decodeIfPresent(String.self, forKey: .handle)
        if let handle {
            try c.ensure(handle.range(of: Self.handlePattern, options: .regularExpression) != nil, .handle, "a handle is #id")
        }
        open = try c.decodeIfPresent(Bool.self, forKey: .open) ?? false
    }

    /// The handle's node id.
    public var handleID: String? { handle.map { String($0.dropFirst()) } }

    /// The flag that is on while the shelf named `name` is open: `panel.<name>.open`.
    public static func openFlag(_ name: String) -> String { flagPrefix + name + ".open" }
    public var openFlag: String { Self.openFlag(name) }
}

/// What a `when` entry may change on a panel: its presentation (fixed on an iPad, a shelf on a phone).
public struct Skin2PanelPatch: Equatable, Hashable, Sendable, Decodable {
    public var presentation: Skin2PanelPresentation?
}

/// A panel that is present in a resolved layout.
public struct Skin2ResolvedPanel: Equatable, Sendable {
    public var panel: Skin2Panel
    /// The presentation after the `when` entries that held.
    public var presentation: Skin2PanelPresentation
    /// A shelf: its open flag is on. A fixed panel is always open.
    public var isOpen: Bool
    /// A shelf whose handle is present and whose hit frame lies inside the safe area, so the player can reach it.
    public var handleReachable: Bool
    /// The panel group's frame.
    public var frame: Skin2Rect
}

extension Skin2Node {
    /// True when the panel is a shelf here or any `when` entry can make it one.
    public var panelCanBeShelf: Bool {
        guard let panel else { return false }
        return panel.presentation == .shelf || when.contains { $0.patch.panel?.presentation == .shelf }
    }
}

extension Skin2Document {
    /// Every panel the skin declares, in document order.
    public var panels: [Skin2Panel] {
        var out: [Skin2Panel] = []
        root.preorder { if let p = $0.panel { out.append(p) } }
        return out
    }

    /// The open flags a skin view starts with the first time the skin is shown: shelves whose `open` is true.
    public var initialPanelFlags: Set<String> {
        var out: Set<String> = []
        root.preorder { if let p = $0.panel, p.open, $0.panelCanBeShelf { out.insert(p.openFlag) } }
        return out
    }

    /// Every registered capability the skin's content names (`has`, a panel's `needs`): what an app could supply
    /// to change the layout. The validator resolves the layout with all of them on as well as with none.
    public var mentionedCapabilities: Set<String> {
        var out: Set<String> = []
        func add(_ c: Skin2Condition?) { out.formUnion(c?.has ?? []) }
        func add(_ v: Skin2Visibility?) { if case .when(let c)? = v { add(c) } }
        root.preorder { n in
            add(n.visible)
            for w in n.when { add(w.condition); add(w.patch.visible) }
            for s in n.states.values { for p in s.patch { add(p.visible) } }
            out.formUnion(n.panel?.needs ?? [])
        }
        return out.filter(Skin2Capabilities.isKnown)
    }
}
