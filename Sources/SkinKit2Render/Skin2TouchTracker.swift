import Foundation
import SkinKit2Core

/// A touch surface's touch: 0 to 1 across its frame.
public struct Skin2SurfacePoint: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// What every live touch holds at one moment: each control's state (controls nobody holds are absent) and the
/// held touch surfaces' points.
public struct Skin2TouchSnapshot: Equatable, Sendable {
    public var states: [String: Skin2ControlState]
    public var surfacePoints: [String: Skin2SurfacePoint]
    public init(states: [String: Skin2ControlState] = [:], surfacePoints: [String: Skin2SurfacePoint] = [:]) {
        self.states = states
        self.surfacePoints = surfacePoints
    }
    public static let empty = Skin2TouchSnapshot()
}

/// Which control each live touch presses (6.3): several fingers at once, one finger per d-pad, thumbstick or
/// touch surface, and a finger that can drag across buttons. A pure value type, so the rules are tested without
/// UIKit; the host feeds it touch begin, move and end. Modelled on Provenance's `OverlayTouchTracker`.
///
/// Who owns a touch is decided once, at touch-down:
/// - **Buttons and triggers** (and empty space): the touch is *free*. Every event recomputes what is under it, so a
///   finger sliding from one button onto another releases the first and presses the second, or rolls onto a d-pad.
///   Free touches never reach a thumbstick, action or touch surface they did not start on.
/// - **D-pads, thumbsticks and touch surfaces**: the touch is *latched* to the control for its whole life. A finger
///   rolling between d-pad zones, or dragging a stick past its travel, keeps the control until it lifts.
///   A second finger that lands on a latched control does nothing: one touch per control.
/// - **Actions**: latched at touch-down and held only while the finger stays inside the hit frame. Once it leaves,
///   the touch is inert until it lifts, even if it comes back (the system-control lockout).
public struct Skin2TouchTracker<Key: Hashable> {
    enum Owner: Equatable {
        case free
        case latched(String)
        case inert
    }

    struct Touch {
        var x: Double
        var y: Double
        var owner: Owner
        var order: Int
        var pressure: Double?
    }

    public private(set) var tester: Skin2HitTester
    private var touches: [Key: Touch] = [:]
    private var nextOrder = 0
    /// Directions held last time, for the d-pad's hysteresis.
    private var dpadHeld: [String: Set<Skin2Direction>] = [:]

    public init(tester: Skin2HitTester) { self.tester = tester }

    public var isEmpty: Bool { touches.isEmpty }
    public var keys: Set<Key> { Set(touches.keys) }

    /// A relayout (rotation, resize, safe area): latches whose control moved on can never fire again.
    public mutating func setTester(_ tester: Skin2HitTester) {
        self.tester = tester
        for (key, touch) in touches {
            if case .latched(let id) = touch.owner, tester.control(id: id) == nil { touches[key]?.owner = .inert }
        }
        dpadHeld = dpadHeld.filter { tester.control(id: $0.key) != nil }
    }

    public mutating func began(_ key: Key, x: Double, y: Double, pressure: Double? = nil) {
        var owner = Owner.free
        if let c = tester.control(at: x, y) {
            switch c.kind {
            case .dpad, .thumbstick, .touchSurface, .action:
                // One touch per control.
                owner = isLatched(c.id) ? .inert : .latched(c.id)
            case .button, .trigger:
                owner = .free
            }
        }
        touches[key] = Touch(x: x, y: y, owner: owner, order: nextOrder, pressure: pressure)
        nextOrder += 1
    }

    public mutating func moved(_ key: Key, x: Double, y: Double, pressure: Double? = nil) {
        guard var touch = touches[key] else { return }
        touch.x = x
        touch.y = y
        touch.pressure = pressure
        if case .latched(let id) = touch.owner, let c = tester.control(id: id), c.kind == .action,
           !Skin2HitTester.contains(c.hitFrame, x, y) {
            touch.owner = .inert
        }
        touches[key] = touch
    }

    public mutating func ended(_ key: Key) { touches[key] = nil }

    public mutating func removeAll() {
        touches.removeAll()
        dpadHeld.removeAll()
    }

    private func isLatched(_ id: String) -> Bool {
        touches.values.contains { $0.owner == .latched(id) }
    }

    /// What the live touches hold now. Updates the d-pad hysteresis.
    public mutating func snapshot() -> Skin2TouchSnapshot {
        var states: [String: Skin2ControlState] = [:]
        var points: [String: Skin2SurfacePoint] = [:]
        // Oldest touch first, so a stick's owner is the first finger down.
        for touch in touches.values.sorted(by: { $0.order < $1.order }) {
            switch touch.owner {
            case .inert:
                continue
            case .latched(let id):
                guard let c = tester.control(id: id) else { continue }
                if c.kind == .action, !Skin2HitTester.contains(c.hitFrame, touch.x, touch.y) { continue }
                merge(c, touch, into: &states, points: &points)
            case .free:
                // Sliding reaches buttons, triggers and d-pads; a stick, action or surface needs a touch-down.
                guard let c = tester.control(at: touch.x, touch.y),
                      c.kind == .button || c.kind == .trigger || c.kind == .dpad else { continue }
                merge(c, touch, into: &states, points: &points)
            }
        }
        var held: [String: Set<Skin2Direction>] = [:]
        for (id, s) in states where !s.directions.isEmpty { held[id] = s.directions }
        dpadHeld = held
        return Skin2TouchSnapshot(states: states, surfacePoints: points)
    }

    private func merge(_ c: Skin2HitTester.Control, _ touch: Touch, into states: inout [String: Skin2ControlState],
                       points: inout [String: Skin2SurfacePoint]) {
        switch c.kind {
        case .dpad:
            let dirs = Skin2HitTester.dpadDirections(in: c.hitFrame, x: touch.x, y: touch.y, previous: dpadHeld[c.id] ?? [])
            // Two fingers on one free d-pad hold the union of their directions.
            var s = states[c.id] ?? Skin2ControlState()
            s.directions.formUnion(dirs)
            states[c.id] = s
        case .touchSurface:
            states[c.id] = Skin2ControlState(pressed: true)
            let p = Skin2HitTester.surfacePoint(frame: c.frame, x: touch.x, y: touch.y)
            points[c.id] = Skin2SurfacePoint(x: p.x, y: p.y)
        case .thumbstick:
            // TODO(#123): a tap on the stick sends its `click` input (L3/R3).
            states[c.id] = Skin2HitTester.state(for: c, x: touch.x, y: touch.y)
        case .trigger:
            // Several fingers on a trigger have ambiguous force ownership. Match the host's
            // binary fallback until only one finger remains.
            let pressure = states[c.id] == nil ? (touch.pressure ?? 1) : 1
            states[c.id] = Skin2ControlState(pressed: true, pressure: pressure)
        default:
            states[c.id] = Skin2ControlState(pressed: true)
        }
    }
}
