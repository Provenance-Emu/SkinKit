// SkinKit2Spike: THROWAWAY code for the format 2.0 spike (SkinKit#24). Not shipped.
// Resolves the node tree to absolute frames for one canvas/safe area/orientation.

import CoreGraphics
import Foundation

public struct Skin2Insets: Equatable {
    public var top: Double, left: Double, bottom: Double, right: Double
    public init(top: Double = 0, left: Double = 0, bottom: Double = 0, right: Double = 0) {
        self.top = top; self.left = left; self.bottom = bottom; self.right = right
    }
}

public struct Skin2Canvas {
    public var size: CGSize
    public var safeArea: Skin2Insets
    public var flags: Set<String>

    public init(size: CGSize, safeArea: Skin2Insets, flags: Set<String> = []) {
        self.size = size; self.safeArea = safeArea; self.flags = flags
    }

    public var orientation: String { size.height >= size.width ? "portrait" : "landscape" }
    public var safeRect: CGRect {
        CGRect(x: safeArea.left, y: safeArea.top,
               width: size.width - safeArea.left - safeArea.right, height: size.height - safeArea.top - safeArea.bottom)
    }
}

public final class Skin2ResolvedNode {
    public let node: Skin2Node
    public var frame: CGRect
    /// For repeated nodes: the extra copies' transforms (about the canvas origin).
    public var copies: [CGAffineTransform] = []
    public var children: [Skin2ResolvedNode] = []

    init(node: Skin2Node, frame: CGRect) { self.node = node; self.frame = frame }

    public var hitFrame: CGRect {
        guard node.type == .control else { return frame }
        let e = CGFloat(node.hit?.extend ?? 0)
        return frame.insetBy(dx: -e, dy: -e)
    }

    public func controls() -> [Skin2ResolvedNode] {
        (node.type == .control ? [self] : []) + children.flatMap { $0.controls() }
    }

    public func first(id: String) -> Skin2ResolvedNode? {
        if node.id == id { return self }
        for c in children { if let f = c.first(id: id) { return f } }
        return nil
    }
}

public struct Skin2Layouter {
    public let document: Skin2Document
    public let canvas: Skin2Canvas
    public let unit: Double
    private var byID: [String: CGRect] = [:]

    public init(document: Skin2Document, canvas: Skin2Canvas) {
        self.document = document
        self.canvas = canvas
        let r = document.reference
        unit = min(max(Double(min(canvas.size.width, canvas.size.height)) / r.shortSide, r.minScale), r.maxScale)
    }

    public static func resolve(_ document: Skin2Document, canvas: Skin2Canvas) -> Skin2ResolvedNode {
        var l = Skin2Layouter(document: document, canvas: canvas)
        return l.resolve(document.root, in: CGRect(origin: .zero, size: canvas.size))!
    }

    // MARK: Conditionals

    func effective(_ node: Skin2Node) -> (layout: Skin2Layout, hidden: Bool) {
        var layout = node.layout ?? Skin2Layout()
        var hidden = false
        for cond in node.when ?? [] {
            if let o = cond.orientation, o != canvas.orientation { continue }
            if let patch = cond.layout { layout = layout.merged(with: patch, clearing: cond.clears) }
            if cond.hidden == true { hidden = true }
        }
        if let flag = node.requiresFlag, !canvas.flags.contains(flag) { hidden = true }
        return (layout, hidden)
    }

    // MARK: Sizing

    func size(of node: Skin2Node, layout: Skin2Layout, parent: CGRect) -> CGSize {
        if let f = layout.frame, f.count == 4 { return CGSize(width: f[2] * unit, height: f[3] * unit) }
        if let inset = layout.inset {
            let i = inset.resolve(parent: Double(min(parent.width, parent.height)), unit: unit)
            return CGSize(width: parent.width - 2 * i, height: parent.height - 2 * i)
        }
        if let stack = node.stack { return stackSize(node, stack: stack, parent: parent) }
        var w = layout.size?.width.map { $0.resolve(parent: Double(parent.width), unit: unit) }
        var h = layout.size?.height.map { $0.resolve(parent: Double(parent.height), unit: unit) }
        if let aspect = layout.aspect ?? node.aspect, node.type == .screen || layout.aspect != nil {
            if let ww = w, h == nil { h = ww / aspect } else if let hh = h, w == nil { w = hh * aspect }
        }
        return CGSize(width: w ?? Double(parent.width), height: h ?? Double(parent.height))
    }

    func stackSize(_ node: Skin2Node, stack: Skin2Stack, parent: CGRect) -> CGSize {
        let spacing = (stack.spacing ?? .points(0)).resolve(parent: 0, unit: unit)
        var main = 0.0, cross = 0.0, n = 0
        for child in node.children ?? [] {
            let (cl, hidden) = effective(child)
            if hidden { continue }
            let s = size(of: child, layout: cl, parent: parent)
            if stack.axis == "vertical" { main += s.height; cross = max(cross, s.width) } else { main += s.width; cross = max(cross, s.height) }
            n += 1
        }
        main += spacing * Double(max(0, n - 1))
        return stack.axis == "vertical" ? CGSize(width: cross, height: main) : CGSize(width: main, height: cross)
    }

    // MARK: Placement

    func reference(_ anchor: Skin2Anchor?, parent: CGRect) -> CGRect {
        switch anchor?.to {
        case "safeArea"?: return canvas.safeRect
        case let id? where id.hasPrefix("#"): return byID[String(id.dropFirst())] ?? parent
        default: return parent
        }
    }

    func place(size: CGSize, layout: Skin2Layout, parent: CGRect) -> CGRect {
        if let f = layout.frame, f.count == 4 {
            return CGRect(x: parent.minX + f[0] * unit, y: parent.minY + f[1] * unit, width: size.width, height: size.height)
        }
        if layout.inset != nil {
            return CGRect(x: parent.midX - size.width / 2, y: parent.midY - size.height / 2, width: size.width, height: size.height)
        }
        let ref = reference(layout.anchor, parent: parent)
        var x: Double, y: Double
        switch layout.anchor?.x ?? .center {
        case .leading: x = ref.minX
        case .center: x = ref.midX - size.width / 2
        case .trailing: x = ref.maxX - size.width
        }
        switch layout.anchor?.y ?? .center {
        case .top: y = ref.minY
        case .center: y = ref.midY - size.height / 2
        case .bottom: y = ref.maxY - size.height
        }
        x += layout.offset?.x?.resolve(parent: Double(ref.width), unit: unit) ?? 0
        y += layout.offset?.y?.resolve(parent: Double(ref.height), unit: unit) ?? 0
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    mutating func resolve(_ node: Skin2Node, in parent: CGRect) -> Skin2ResolvedNode? {
        let (layout, hidden) = effective(node)
        if hidden { return nil }
        let s = size(of: node, layout: layout, parent: parent)
        let frame = node.id == "canvas" ? parent : place(size: s, layout: layout, parent: parent)
        let resolved = Skin2ResolvedNode(node: node, frame: frame)
        if let id = node.id { byID[id] = frame }

        if let rep = node.repeat, rep.count > 1 {
            let pivot = rep.pivot == "parent" ? CGPoint(x: parent.midX, y: parent.midY) : CGPoint(x: frame.midX, y: frame.midY)
            for i in 1..<rep.count {
                let angle = CGFloat((rep.rotate ?? 0) * Double(i) * .pi / 180)
                let t = CGAffineTransform(translationX: pivot.x, y: pivot.y).rotated(by: angle).translatedBy(x: -pivot.x, y: -pivot.y)
                resolved.copies.append(t)
            }
        }

        if let stack = node.stack {
            resolved.children = resolveStack(node, stack: stack, frame: frame)
        } else {
            resolved.children = (node.children ?? []).compactMap { resolve($0, in: frame) }
        }
        return resolved
    }

    mutating func resolveStack(_ node: Skin2Node, stack: Skin2Stack, frame: CGRect) -> [Skin2ResolvedNode] {
        let spacing = (stack.spacing ?? .points(0)).resolve(parent: 0, unit: unit)
        let vertical = stack.axis == "vertical"
        var cursor = vertical ? frame.minY : frame.minX
        var out: [Skin2ResolvedNode] = []
        for child in node.children ?? [] {
            let (cl, hidden) = effective(child)
            if hidden { continue }
            let s = size(of: child, layout: cl, parent: frame)
            var origin = CGPoint.zero
            if vertical {
                origin.y = cursor
                switch cl.anchor?.x.map({ $0.rawValue }) ?? stack.align ?? "center" {
                case "leading": origin.x = frame.minX
                case "trailing": origin.x = frame.maxX - s.width
                default: origin.x = frame.midX - s.width / 2
                }
                cursor += s.height + spacing
            } else {
                origin.x = cursor
                switch cl.anchor?.y.map({ $0.rawValue }) ?? stack.align ?? "center" {
                case "top": origin.y = frame.minY
                case "bottom": origin.y = frame.maxY - s.height
                default: origin.y = frame.midY - s.height / 2
                }
                cursor += s.width + spacing
            }
            origin.x += cl.offset?.x?.resolve(parent: Double(frame.width), unit: unit) ?? 0
            origin.y += cl.offset?.y?.resolve(parent: Double(frame.height), unit: unit) ?? 0
            let childFrame = CGRect(origin: origin, size: s)
            // Re-run the child with its frame fixed: children of a stacked child lay out inside it.
            var pinned = child
            pinned.layout = Skin2Layout(frame: [Double(childFrame.minX - frame.minX) / unit, Double(childFrame.minY - frame.minY) / unit,
                                                Double(s.width) / unit, Double(s.height) / unit])
            pinned.when = nil
            if let r = resolve(pinned, in: frame) { out.append(r) }
        }
        return out
    }
}
