import Foundation
import SkinKit2Core

/// The layout part-way between two resolved layouts of one skin, for a host animating a change (a shelf opening).
public enum Skin2LayoutBlend {
    /// `progress` 0 is `from`, 1 is `to`. A node in both layouts moves and fades in a straight line between its two
    /// frames and opacities. A node in only one of them keeps its place inside its parent, rides along with it,
    /// and fades in or out. Hit frames are not blended: touches follow the layout the host has resolved.
    public static func blend(from: Skin2Resolution, to: Skin2Resolution, progress: Double) -> Skin2Resolution {
        let t = min(max(progress, 0), 1)
        if t >= 1 { return to }
        // The layout with more nodes gives the tree; the other gives where its nodes are heading or came from.
        let toIsFuller = to.nodes.count >= from.nodes.count
        let full = toIsFuller ? to : from, other = toIsFuller ? from : to
        // How much of `full` shows: all of it at its own end.
        let weight = toIsFuller ? t : 1 - t
        var others: [String: Skin2ResolvedNode] = [:]
        for node in other.nodes { others[node.pointer] = node }
        var out = to
        out.root = blend(full.root, others: others, weight: weight, dx: 0, dy: 0)
        return out
    }

    private static func mix(_ a: Double, _ b: Double, _ w: Double) -> Double { a + (b - a) * w }

    private static func mix(_ a: Skin2Rect, _ b: Skin2Rect, _ w: Double) -> Skin2Rect {
        Skin2Rect(x: mix(a.x, b.x, w), y: mix(a.y, b.y, w), width: mix(a.width, b.width, w), height: mix(a.height, b.height, w))
    }

    private static func blend(_ node: Skin2ResolvedNode, others: [String: Skin2ResolvedNode], weight w: Double, dx: Double, dy: Double) -> Skin2ResolvedNode {
        var out = node
        if let other = others[node.pointer] {
            out.frame = mix(other.frame, node.frame, w)
            out.exactFrame = mix(other.exactFrame, node.exactFrame, w)
            out.opacity = mix(other.opacity, node.opacity, w)
        } else {
            out.frame.x += dx; out.frame.y += dy
            out.exactFrame.x += dx; out.exactFrame.y += dy
            out.opacity = node.opacity * w
        }
        let cx = out.frame.x - node.frame.x, cy = out.frame.y - node.frame.y
        out.children = node.children.map { blend($0, others: others, weight: w, dx: cx, dy: cy) }
        return out
    }
}
