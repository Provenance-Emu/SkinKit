import Foundation

/// A player's edit to one node (4.7): an offset in points at reference scale, a scale about the node's centre,
/// an opacity and a hide switch. Stored per skin, per (device, orientation), per node id by the app.
public struct Skin2Edit: Equatable, Hashable, Sendable, Codable {
    public struct Offset: Equatable, Hashable, Sendable, Codable {
        public var x: Double
        public var y: Double
        public init(x: Double = 0, y: Double = 0) { self.x = x; self.y = y }
    }

    public var offset: Offset?
    public var scale: Double?
    public var opacity: Double?
    public var hidden: Bool?

    public init(offset: Offset? = nil, scale: Double? = nil, opacity: Double? = nil, hidden: Bool? = nil) {
        self.offset = offset; self.scale = scale; self.opacity = opacity; self.hidden = hidden
    }
}

/// One node after layout: the node with its `when` patches applied, where it is, and where it takes touches.
public struct Skin2ResolvedNode: Equatable, Sendable {
    /// JSON Pointer of the node in the expanded document (`/root/children/2`).
    public var pointer: String
    /// The node with the `when` patches that held applied (and `when` emptied).
    public var node: Skin2Node
    /// The frame before half-point rounding.
    public var exactFrame: Skin2Rect
    /// The frame rounded to the half point; what renderers draw and the baker writes.
    public var frame: Skin2Rect
    /// Controls only: the frame outset by `hit.extend`, rounded.
    public var hitFrame: Skin2Rect?
    /// The node's own opacity (with the player's edit); the renderer multiplies down the tree.
    public var opacity: Double
    /// `repeat`: one transform per copy in canvas points, copy 0 first (the identity). Empty without `repeat`.
    public var copies: [Skin2Transform]
    /// Thumbsticks only: the knob's travel radius in canvas points.
    public var travel: Double?
    public var children: [Skin2ResolvedNode]

    public var id: String? { node.id }

    /// This node and its descendants, parents first, in document order.
    public var preorder: [Skin2ResolvedNode] { [self] + children.flatMap(\.preorder) }
}

/// A layout warning: a reference the resolver could not follow, so it used the parent instead.
public struct Skin2LayoutWarning: Equatable, Hashable, Sendable {
    public var pointer: String
    public var message: String
}

/// The resolved tree for one environment.
public struct Skin2Resolution: Equatable, Sendable {
    public var root: Skin2ResolvedNode
    public var unit: Double
    public var environment: Skin2Environment
    public var theme: String?
    public var variant: String?
    public var warnings: [Skin2LayoutWarning]

    /// Every visible node, parents first, in document order.
    public var nodes: [Skin2ResolvedNode] { root.preorder }
    public var controls: [Skin2ResolvedNode] { nodes.filter { $0.node.type == .control } }
    public var screens: [Skin2ResolvedNode] { nodes.filter { $0.node.type == .screen } }
    public func node(id: String) -> Skin2ResolvedNode? { nodes.first { $0.node.id == id } }
}

/// The layout resolver (section 4): a pure function of the document, the environment and the player's edits.
///
/// For each node, parents before children, in document order:
/// 1. apply the `when` patches that hold (in order), then evaluate `visible`; a hidden node takes no space;
/// 2. size it (4.2): `frame` → its size; `inset` → the parent minus the inset; a stack or grid group → the
///    packed size of its children; otherwise each axis from `size`, a missing axis from `aspect` (a screen's own
///    `aspect` counts), else the reference area's; then `minSize`/`maxSize` clamp;
/// 3. place it (4.3): `frame` → at its origin in the parent; `inset` → at the inset corner; otherwise at the
///    `anchor` (default centre) of the reference area, moved by `offset` (+x right, +y down);
/// 4. apply the player's edit (offset, scale about the centre, opacity, hidden);
/// 5. record its `#id` (and the first screen as `screen`);
/// 6. lay out the children inside its frame (a stack or grid assigns their frames);
/// 7. expand `repeat` into copy transforms.
///
/// The reference area is the parent, or the area `anchor.to` names; it stands in for the parent in `%` lengths
/// and default sizes, so `{"to": "#bottom", "size": {"width": "100%", "height": "100%"}}` covers `#bottom`.
public struct Skin2Resolver {
    public let document: Skin2Document
    public let environment: Skin2Environment
    public let edits: [String: Skin2Edit]
    public let unit: Double

    private var areas: [String: Skin2Rect] = [:]
    private var screenArea: Skin2Rect?
    private var warnings: [Skin2LayoutWarning] = []

    public init(document: Skin2Document, environment: Skin2Environment, edits: [String: Skin2Edit] = [:]) {
        self.document = document
        self.environment = environment
        self.edits = edits
        unit = document.reference.unit(for: environment.size)
    }

    public static func resolve(_ document: Skin2Document, in environment: Skin2Environment,
                               edits: [String: Skin2Edit] = [:]) -> Skin2Resolution {
        var r = Skin2Resolver(document: document, environment: environment, edits: edits)
        let canvas = environment.canvasRect
        let root = r.resolve(document.root, pointer: "/root", parent: canvas)
            ?? Skin2ResolvedNode(pointer: "/root", node: document.root, exactFrame: canvas, frame: canvas, hitFrame: nil,
                                 opacity: 1, copies: [], travel: nil, children: [])
        return Skin2Resolution(root: root, unit: r.unit, environment: environment, theme: document.theme,
                               variant: document.variant, warnings: r.warnings)
    }

    // MARK: Conditions

    public func matches(_ c: Skin2Condition) -> Bool {
        if let v = c.orientation, v != environment.orientation { return false }
        if let v = c.device, v != environment.device { return false }
        if let v = c.displayType, v != environment.displayType { return false }
        if let v = c.flag, !environment.flags.contains(v) { return false }
        if let v = c.minWidth, environment.size.width < v { return false }
        if let v = c.minHeight, environment.size.height < v { return false }
        if let v = c.theme, v != document.theme { return false }
        if let v = c.variant, v != document.variant { return false }
        return true
    }

    /// The node with its holding `when` patches applied.
    public func effective(_ node: Skin2Node) -> Skin2Node {
        var n = node
        for entry in node.when where matches(entry.condition) { n = entry.patch.apply(to: n) }
        n.when = []
        return n
    }

    public func isVisible(_ node: Skin2Node) -> Bool {
        switch node.visible {
        case nil: return true
        case .always(let b)?: return b
        case .when(let c)?: return matches(c)
        }
    }

    // MARK: Areas

    private mutating func warn(_ pointer: String, _ message: String) {
        let w = Skin2LayoutWarning(pointer: pointer, message: message)
        if !warnings.contains(w) { warnings.append(w) }
    }

    private mutating func area(_ a: Skin2Area, parent: Skin2Rect, pointer: String) -> Skin2Rect {
        switch a {
        case .parent: return parent
        case .canvas: return environment.canvasRect
        case .safeArea: return environment.safeRect
        case .screen:
            if let s = screenArea { return s }
            warn(pointer, "anchors to screen before any screen node is laid out; using the parent")
            return parent
        case .node(let id):
            if let r = areas[id] { return r }
            warn(pointer, "anchors to #\(id), which is not laid out before this node; using the parent")
            return parent
        }
    }

    /// The area a node's `%` lengths, default size and anchor refer to.
    private mutating func referenceArea(_ n: Skin2Node, parent: Skin2Rect, pointer: String) -> Skin2Rect {
        guard let L = n.layout, L.frame == nil, L.inset == nil, let to = L.anchor?.to else { return parent }
        return area(to, parent: parent, pointer: pointer)
    }

    private func length(_ l: Skin2Length?, along: Double) -> Double? {
        l?.resolve(along: along, unit: unit, safeArea: environment.safeArea)
    }

    // MARK: Size

    private mutating func measure(_ n: Skin2Node, parent: Skin2Rect, pointer: String) -> Skin2Size {
        let L = n.layout ?? Skin2Layout()
        let ref = referenceArea(n, parent: parent, pointer: pointer)
        var w: Double, h: Double
        if let f = L.frame {
            w = length(f[2], along: parent.width) ?? 0
            h = length(f[3], along: parent.height) ?? 0
        } else if let inset = L.inset {
            let i = inset.resolve(width: parent.width, height: parent.height, unit: unit, safeArea: environment.safeArea)
            w = parent.width - i.left - i.right
            h = parent.height - i.top - i.bottom
        } else if let stack = n.stack {
            let s = stackMetrics(n, stack: stack, area: ref, pointer: pointer).size
            w = s.width; h = s.height
        } else if let grid = n.grid {
            let s = gridMetrics(n, grid: grid, area: ref, fixed: nil, pointer: pointer).size
            w = s.width; h = s.height
        } else {
            var ow = length(L.size?.width, along: ref.width)
            var oh = length(L.size?.height, along: ref.height)
            if let aspect = L.aspect ?? (n.type == .screen ? n.aspect : nil) {
                if let ww = ow, oh == nil { oh = ww / aspect } else if let hh = oh, ow == nil { ow = hh * aspect }
            }
            w = ow ?? ref.width
            h = oh ?? ref.height
        }
        if let v = length(L.minSize?.width, along: ref.width) { w = max(w, v) }
        if let v = length(L.minSize?.height, along: ref.height) { h = max(h, v) }
        if let v = length(L.maxSize?.width, along: ref.width) { w = min(w, v) }
        if let v = length(L.maxSize?.height, along: ref.height) { h = min(h, v) }
        return Skin2Size(width: max(0, w), height: max(0, h))
    }

    // MARK: Place

    private mutating func place(_ n: Skin2Node, size: Skin2Size, parent: Skin2Rect, pointer: String) -> Skin2Rect {
        let L = n.layout ?? Skin2Layout()
        if let f = L.frame {
            return Skin2Rect(x: parent.minX + (length(f[0], along: parent.width) ?? 0),
                             y: parent.minY + (length(f[1], along: parent.height) ?? 0), width: size.width, height: size.height)
        }
        if let inset = L.inset {
            let i = inset.resolve(width: parent.width, height: parent.height, unit: unit, safeArea: environment.safeArea)
            return Skin2Rect(x: parent.minX + i.left, y: parent.minY + i.top, width: size.width, height: size.height)
        }
        let ref = referenceArea(n, parent: parent, pointer: pointer)
        let x = Self.align(L.anchor?.x ?? .center, start: ref.minX, length: ref.width, size: size.width)
        let y = Self.align(L.anchor?.y ?? .center, start: ref.minY, length: ref.height, size: size.height)
        return Skin2Rect(x: x + (length(L.offset?.x, along: ref.width) ?? 0),
                         y: y + (length(L.offset?.y, along: ref.height) ?? 0), width: size.width, height: size.height)
    }

    static func align(_ a: Skin2HAnchor, start: Double, length: Double, size: Double) -> Double {
        switch a {
        case .leading: return start
        case .center: return start + (length - size) / 2
        case .trailing: return start + length - size
        }
    }

    static func align(_ a: Skin2VAnchor, start: Double, length: Double, size: Double) -> Double {
        switch a {
        case .top: return start
        case .center: return start + (length - size) / 2
        case .bottom: return start + length - size
        }
    }

    static func align(_ a: Skin2Align, start: Double, length: Double, size: Double) -> Double {
        switch a {
        case .leading: return start
        case .center: return start + (length - size) / 2
        case .trailing: return start + length - size
        }
    }

    // MARK: Resolve

    mutating func resolve(_ raw: Skin2Node, pointer: String, parent: Skin2Rect) -> Skin2ResolvedNode? {
        let n = effective(raw)
        guard isVisible(n) else { return nil }
        let size = measure(n, parent: parent, pointer: pointer)
        let frame = place(n, size: size, parent: parent, pointer: pointer)
        let ref = referenceArea(n, parent: parent, pointer: pointer)
        return finish(n, pointer: pointer, frame: frame, measureArea: ref, parent: parent)
    }

    /// Steps 4–7 for a node whose frame is known. `measureArea` is the area the node was measured against (its
    /// stack or grid content is measured against it again); `parent` is the parent's frame.
    private mutating func finish(_ n: Skin2Node, pointer: String, frame placed: Skin2Rect, measureArea: Skin2Rect,
                                 parent: Skin2Rect) -> Skin2ResolvedNode? {
        var frame = placed
        var opacity = n.opacity ?? 1
        if let id = n.id, let edit = edits[id] {
            if edit.hidden == true { return nil }
            if let o = edit.offset { frame.x += o.x * unit; frame.y += o.y * unit }
            if let s = edit.scale, s > 0 {
                frame = Skin2Rect(x: frame.midX - frame.width * s / 2, y: frame.midY - frame.height * s / 2,
                                  width: frame.width * s, height: frame.height * s)
            }
            if let o = edit.opacity { opacity *= o }
        }
        if let id = n.id { areas[id] = frame }
        if n.type == .screen, screenArea == nil { screenArea = frame }

        var hitFrame: Skin2Rect?
        var travel: Double?
        if n.type == .control {
            let e = n.hit?.extend?.resolve(width: frame.width, height: frame.height, unit: unit, safeArea: environment.safeArea) ?? .zero
            hitFrame = frame.outset(e).roundedToHalfPoint
            if n.kind == .thumbstick {
                let short = min(frame.width, frame.height)
                travel = length(n.travel, along: short) ?? 0.35 * short
            }
        }

        var children: [Skin2ResolvedNode] = []
        if let stack = n.stack {
            children = layoutStack(n, stack: stack, frame: frame, area: measureArea, pointer: pointer)
        } else if let grid = n.grid {
            children = layoutGrid(n, grid: grid, frame: frame, area: measureArea, pointer: pointer)
        } else {
            for (i, child) in n.children.enumerated() {
                if let r = resolve(child, pointer: Self.childPointer(pointer, i), parent: frame) { children.append(r) }
            }
        }

        var copies: [Skin2Transform] = []
        if let rep = n.repeat {
            let pivot = rep.pivot == .parent ? (x: parent.midX, y: parent.midY) : (x: frame.midX, y: frame.midY)
            let ox = length(rep.offset?.x, along: parent.width) ?? 0
            let oy = length(rep.offset?.y, along: parent.height) ?? 0
            for i in 0..<rep.count {
                let k = Double(i)
                let t = Skin2Transform.translation(-pivot.x, -pivot.y)
                    .then(.scale(pow(rep.scale ?? 1, k)))
                    .then(.rotation(degrees: (rep.rotate ?? 0) * k))
                    .then(.translation(pivot.x + ox * k, pivot.y + oy * k))
                copies.append(i == 0 ? .identity : t)
            }
        }

        return Skin2ResolvedNode(pointer: pointer, node: n, exactFrame: frame, frame: frame.roundedToHalfPoint, hitFrame: hitFrame,
                                 opacity: opacity, copies: copies, travel: travel, children: children)
    }

    static func childPointer(_ p: String, _ i: Int) -> String { "\(p)/children/\(i)" }

    // MARK: Stacks (4.4)

    private struct Measured {
        var node: Skin2Node
        var index: Int
        var size: Skin2Size
    }

    /// Visible children with their `when` applied and their sizes measured against `area`.
    private mutating func measuredChildren(_ n: Skin2Node, area: Skin2Rect, pointer: String) -> [Measured] {
        var out: [Measured] = []
        for (i, child) in n.children.enumerated() {
            let c = effective(child)
            guard isVisible(c) else { continue }
            // A stacked or gridded child is placed by its group: its own `anchor.to` does not apply.
            var sizing = c
            sizing.layout?.anchor?.to = nil
            out.append(Measured(node: c, index: i, size: measure(sizing, parent: area, pointer: Self.childPointer(pointer, i))))
        }
        return out
    }

    private mutating func stackMetrics(_ n: Skin2Node, stack: Skin2Stack, area: Skin2Rect, pointer: String)
        -> (size: Skin2Size, children: [Measured], spacing: Double) {
        let vertical = stack.axis == .vertical
        let spacing = length(stack.spacing, along: vertical ? area.height : area.width) ?? 0
        let children = measuredChildren(n, area: area, pointer: pointer)
        var main = 0.0, cross = 0.0
        for c in children {
            main += vertical ? c.size.height : c.size.width
            cross = max(cross, vertical ? c.size.width : c.size.height)
        }
        main += spacing * Double(max(0, children.count - 1))
        return (vertical ? Skin2Size(width: cross, height: main) : Skin2Size(width: main, height: cross), children, spacing)
    }

    private mutating func layoutStack(_ n: Skin2Node, stack: Skin2Stack, frame: Skin2Rect, area: Skin2Rect, pointer: String) -> [Skin2ResolvedNode] {
        let m = stackMetrics(n, stack: stack, area: area, pointer: pointer)
        let vertical = stack.axis == .vertical
        let total = m.children.reduce(0) { $0 + (vertical ? $1.size.height : $1.size.width) }
        var gap = m.spacing
        if stack.distribute == .spaceBetween, m.children.count > 1 {
            gap = max(m.spacing, ((vertical ? frame.height : frame.width) - total) / Double(m.children.count - 1))
        }
        var cursor = vertical ? frame.minY : frame.minX
        var out: [Skin2ResolvedNode] = []
        for c in m.children {
            let L = c.node.layout
            var x: Double, y: Double
            if vertical {
                y = cursor
                if let a = L?.anchor?.x {
                    x = Self.align(a, start: frame.minX, length: frame.width, size: c.size.width)
                } else {
                    x = Self.align(stack.align, start: frame.minX, length: frame.width, size: c.size.width)
                }
                cursor += c.size.height + gap
            } else {
                x = cursor
                if let a = L?.anchor?.y {
                    y = Self.align(a, start: frame.minY, length: frame.height, size: c.size.height)
                } else {
                    y = Self.align(stack.align, start: frame.minY, length: frame.height, size: c.size.height)
                }
                cursor += c.size.width + gap
            }
            x += length(L?.offset?.x, along: area.width) ?? 0
            y += length(L?.offset?.y, along: area.height) ?? 0
            let childFrame = Skin2Rect(x: x, y: y, width: c.size.width, height: c.size.height)
            if let r = finish(c.node, pointer: Self.childPointer(pointer, c.index), frame: childFrame, measureArea: area, parent: frame) {
                out.append(r)
            }
        }
        return out
    }

    // MARK: Grids (4.4)

    private struct GridMetrics {
        var size: Skin2Size
        var cell: Skin2Size
        var spacingX: Double
        var spacingY: Double
        var children: [Measured]
        var cells: [(row: Int, column: Int, rows: Int, columns: Int)]
    }

    /// Row-major placement with spans; cells are equal. With `fixed` (a group sized by `frame` or `inset`) the
    /// cells divide it; otherwise a cell is as large as the largest child needs.
    private mutating func gridMetrics(_ n: Skin2Node, grid: Skin2Grid, area: Skin2Rect, fixed: Skin2Size?, pointer: String) -> GridMetrics {
        let columns = grid.columns
        let sx = length(grid.spacingX, along: area.width) ?? 0
        let sy = length(grid.spacingY, along: area.height) ?? 0
        let children = measuredChildren(n, area: area, pointer: pointer)
        var occupied: Set<[Int]> = []
        var cells: [(row: Int, column: Int, rows: Int, columns: Int)] = []
        var rowCount = 0
        for c in children {
            let spanC = min(max(c.node.layout?.span?.columns ?? 1, 1), columns)
            let spanR = max(c.node.layout?.span?.rows ?? 1, 1)
            var row = 0, col = 0
            search: while true {
                for cc in 0...(columns - spanC) {
                    let free = (0..<spanR).allSatisfy { dr in (0..<spanC).allSatisfy { dc in !occupied.contains([row + dr, cc + dc]) } }
                    if free { col = cc; break search }
                }
                row += 1
            }
            for dr in 0..<spanR { for dc in 0..<spanC { occupied.insert([row + dr, col + dc]) } }
            cells.append((row, col, spanR, spanC))
            rowCount = max(rowCount, row + spanR)
        }
        var cell: Skin2Size
        if let fixed {
            cell = Skin2Size(width: (fixed.width - sx * Double(columns - 1)) / Double(columns),
                             height: rowCount > 0 ? (fixed.height - sy * Double(rowCount - 1)) / Double(rowCount) : 0)
        } else {
            cell = Skin2Size(width: 0, height: 0)
            for (c, slot) in zip(children, cells) {
                cell.width = max(cell.width, (c.size.width - sx * Double(slot.columns - 1)) / Double(slot.columns))
                cell.height = max(cell.height, (c.size.height - sy * Double(slot.rows - 1)) / Double(slot.rows))
            }
        }
        let size = Skin2Size(width: Double(columns) * cell.width + sx * Double(columns - 1),
                             height: rowCount > 0 ? Double(rowCount) * cell.height + sy * Double(rowCount - 1) : 0)
        return GridMetrics(size: fixed ?? size, cell: cell, spacingX: sx, spacingY: sy, children: children, cells: cells)
    }

    private mutating func layoutGrid(_ n: Skin2Node, grid: Skin2Grid, frame: Skin2Rect, area: Skin2Rect, pointer: String) -> [Skin2ResolvedNode] {
        let L = n.layout
        let fixed = (L?.frame != nil || L?.inset != nil) ? frame.size : nil
        let m = gridMetrics(n, grid: grid, area: area, fixed: fixed, pointer: pointer)
        var out: [Skin2ResolvedNode] = []
        for (c, slot) in zip(m.children, m.cells) {
            let span = Skin2Rect(
                x: frame.minX + Double(slot.column) * (m.cell.width + m.spacingX),
                y: frame.minY + Double(slot.row) * (m.cell.height + m.spacingY),
                width: Double(slot.columns) * m.cell.width + Double(slot.columns - 1) * m.spacingX,
                height: Double(slot.rows) * m.cell.height + Double(slot.rows - 1) * m.spacingY)
            var sizing = c.node
            sizing.layout?.anchor?.to = nil
            let p = Self.childPointer(pointer, c.index)
            let size = measure(sizing, parent: span, pointer: p)
            let anchor = c.node.layout?.anchor
            var x = anchor?.x.map { Self.align($0, start: span.minX, length: span.width, size: size.width) }
                ?? Self.align(grid.align, start: span.minX, length: span.width, size: size.width)
            var y = Self.align(anchor?.y ?? .center, start: span.minY, length: span.height, size: size.height)
            x += length(c.node.layout?.offset?.x, along: span.width) ?? 0
            y += length(c.node.layout?.offset?.y, along: span.height) ?? 0
            if let r = finish(c.node, pointer: p, frame: Skin2Rect(x: x, y: y, width: size.width, height: size.height),
                              measureArea: span, parent: frame) {
                out.append(r)
            }
        }
        return out
    }
}
