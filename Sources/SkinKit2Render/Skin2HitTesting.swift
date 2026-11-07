import Foundation
import SkinKit2Core

/// Control hit testing (6.1, 6.3): frames only, never shapes. A touch lands on the last control in document order
/// whose hit frame contains it; touch surfaces sit under every other control. Repeat copies are not hit-tested
/// (controls can't repeat).
public struct Skin2HitTester: Equatable, Sendable {
    public struct Control: Equatable, Sendable {
        public var id: String
        public var kind: Skin2ControlKind
        public var frame: Skin2Rect
        public var hitFrame: Skin2Rect
        /// Thumbsticks: travel radius in canvas points.
        public var travel: Double?
        /// Every input the control sends (`input` plus `inputs`; a d-pad's four directions).
        public var inputs: [String]
        public var input: Skin2Input?
        /// The control's `haptic`, or nil for the default.
        public var haptic: Skin2Haptic?
    }

    /// Controls in hit order: the first that contains a point wins.
    public let controls: [Control]

    public init(_ resolution: Skin2Resolution) {
        let all = resolution.controls.compactMap { r -> Control? in
            guard let id = r.node.id, let kind = r.node.kind, let hit = r.hitFrame else { return nil }
            return Control(id: id, kind: kind, frame: r.frame, hitFrame: hit, travel: r.travel, inputs: r.node.inputNames, input: r.node.input,
                               haptic: r.node.haptic)
        }
        let buttons: [Control] = all.filter { $0.kind != .touchSurface }.reversed()
        let surfaces: [Control] = all.filter { $0.kind == .touchSurface }.reversed()
        controls = buttons + surfaces
    }

    public func control(at x: Double, _ y: Double) -> Control? {
        controls.first { Self.contains($0.hitFrame, x, y) }
    }

    public func control(id: String) -> Control? { controls.first { $0.id == id } }

    static func contains(_ r: Skin2Rect, _ x: Double, _ y: Double) -> Bool {
        x >= r.minX && x < r.maxX && y >= r.minY && y < r.maxY
    }

    /// How far a held d-pad direction reaches back into the dead zone before it lets go, as a fraction of the side.
    /// A finger rolling between zones doesn't flicker at the boundary.
    static let dpadHysteresis = 0.03

    /// The d-pad directions a point presses: the hit frame split 3 × 3 around a centre dead zone 20 % of the side
    /// (6.1). A corner zone presses two directions. Points outside the hit frame clamp to its edge, so a finger
    /// that slides off keeps the direction it rolled to. `previous` is what the same touch held a moment ago: a
    /// direction it holds stays held until the finger is `dpadHysteresis` of the side back inside the dead zone.
    public static func dpadDirections(in hitFrame: Skin2Rect, x: Double, y: Double,
                                      previous: Set<Skin2Direction> = []) -> Set<Skin2Direction> {
        guard hitFrame.width > 0, hitFrame.height > 0 else { return [] }
        let dx = (x - hitFrame.midX) / hitFrame.width, dy = (y - hitFrame.midY) / hitFrame.height
        let dead = 0.1
        func edge(_ held: Bool) -> Double { held ? dead - dpadHysteresis : dead }
        var out: Set<Skin2Direction> = []
        if dx < -edge(previous.contains(.left)) { out.insert(.left) } else if dx > edge(previous.contains(.right)) { out.insert(.right) }
        if dy < -edge(previous.contains(.up)) { out.insert(.up) } else if dy > edge(previous.contains(.down)) { out.insert(.down) }
        return out
    }

    /// A thumbstick's value for a touch: the offset from the frame's centre over `travel`, clamped to the unit
    /// circle (6.1).
    public static func stickValue(frame: Skin2Rect, travel: Double, x: Double, y: Double) -> Skin2StickValue {
        guard travel > 0 else { return .zero }
        return Skin2StickValue(x: (x - frame.midX) / travel, y: (y - frame.midY) / travel)
    }

    /// A touch surface's normalised coordinates (0–1 across the frame, clamped).
    public static func surfacePoint(frame: Skin2Rect, x: Double, y: Double) -> (x: Double, y: Double) {
        guard frame.width > 0, frame.height > 0 else { return (0, 0) }
        return (min(max((x - frame.minX) / frame.width, 0), 1), min(max((y - frame.minY) / frame.height, 0), 1))
    }

    /// The state a single touch at a point gives a control: pressed for buttons, triggers and actions, the
    /// directions for a d-pad, the knob value for a thumbstick.
    public static func state(for c: Control, x: Double, y: Double) -> Skin2ControlState {
        switch c.kind {
        case .dpad: return Skin2ControlState(directions: dpadDirections(in: c.hitFrame, x: x, y: y))
        case .thumbstick: return Skin2ControlState(pressed: true, stick: stickValue(frame: c.frame, travel: c.travel ?? 0, x: x, y: y))
        default: return Skin2ControlState(pressed: true)
        }
    }

    /// Whether a drag sample is news for the host: the state changed, or a held touch surface moved. A
    /// touch surface stays `pressed` while the finger moves, so comparing states alone would drop every move.
    public static func isNewSample(_ c: Control, state: Skin2ControlState, previous: Skin2ControlState?) -> Bool {
        state != previous || (c.kind == .touchSurface && state.isPressed)
    }

    /// The input names a control sends for a state: the held directions of a d-pad, else every input while pressed.
    public static func inputs(for c: Control, state: Skin2ControlState) -> [String] {
        if case .directions(let d)? = c.input {
            var out: [String] = []
            for dir in Skin2Direction.allCases where state.directions.contains(dir) {
                switch dir {
                case .up: out.append(d.up)
                case .down: out.append(d.down)
                case .left: out.append(d.left)
                case .right: out.append(d.right)
                }
            }
            return out
        }
        return state.isPressed ? c.inputs : []
    }
}
