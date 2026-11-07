import Foundation
import SkinKit2Core

/// A control's input changed: the control, its new state, and the input names it now holds (a d-pad's held
/// directions, every input of a pressed button, nothing on release).
public struct Skin2InputEvent: Equatable, Sendable {
    public var control: Skin2HitTester.Control
    public var state: Skin2ControlState
    public var inputs: [String]
    /// Touch surfaces: the touch in 0–1 across the frame; nil on release.
    public var surfacePoint: Skin2SurfacePoint?

    public init(control: Skin2HitTester.Control, state: Skin2ControlState, inputs: [String], surfacePoint: Skin2SurfacePoint? = nil) {
        self.control = control
        self.state = state
        self.inputs = inputs
        self.surfacePoint = surfacePoint
    }
}

/// The events that take `old` to `new`: one per control whose state changed (a release carries the empty state), and
/// one per move of a held touch surface. Controls are visited in hit order, so the output is deterministic.
public func skin2InputEvents(from old: Skin2TouchSnapshot, to new: Skin2TouchSnapshot, tester: Skin2HitTester) -> [Skin2InputEvent] {
    var out: [Skin2InputEvent] = []
    for c in tester.controls {
        let before = old.states[c.id], after = new.states[c.id]
        let point = new.surfacePoints[c.id]
        let moved = c.kind == .touchSurface && after != nil && point != old.surfacePoints[c.id]
        guard before != after || moved else { continue }
        let state = after ?? Skin2ControlState()
        out.append(Skin2InputEvent(control: c, state: state, inputs: Skin2HitTester.inputs(for: c, state: state), surfacePoint: point))
    }
    // Releases first, so a finger handing over from one control to the next lets go before it presses.
    return out.filter { !$0.state.isPressed } + out.filter { $0.state.isPressed }
}

/// Where a host sends input. Sticks are in screen axes (+y down); a sink for a y-up engine negates `y`.
public protocol Skin2InputSink: AnyObject {
    func press(_ input: String)
    func release(_ input: String)
    /// A thumbstick's value, -1...1 inside the unit circle; `(0, 0)` on release.
    func stick(_ input: String, x: Double, y: Double)
    /// A touch surface (`touchScreen`, `pointer`, ...): the touch across its frame, or nil once it lifts.
    func surface(_ input: String, point: Skin2SurfacePoint?)
    /// An `action` control fired (touch-down only).
    func action(_ name: String)
}

/// Turns control events into press, release, stick, surface and action calls. It remembers what each control held,
/// so a d-pad rolling up, then up + right, then right releases `up` and nothing else.
public struct Skin2InputBridge {
    private var held: [String: [String]] = [:]
    private var sticks: [String: (input: String, value: Skin2StickValue)] = [:]
    private var firedActions: Set<String> = []

    public init() {}

    public mutating func handle(_ event: Skin2InputEvent, sink: Skin2InputSink) {
        let c = event.control
        switch c.kind {
        case .action:
            // Fires once on touch-down, nothing on release.
            if event.state.isPressed {
                if firedActions.insert(c.id).inserted { for name in c.inputs { sink.action(name) } }
            } else {
                firedActions.remove(c.id)
            }
        case .thumbstick:
            let name = c.inputs.first ?? c.id
            let value = event.state.isPressed ? event.state.stick : .zero
            if sticks[c.id]?.value != value {
                sticks[c.id] = value == .zero ? nil : (name, value)
                sink.stick(name, x: value.x, y: value.y)
            }
        case .touchSurface:
            for name in c.inputs { sink.surface(name, point: event.state.isPressed ? event.surfacePoint : nil) }
        default:
            let before = held[c.id] ?? [], after = event.inputs
            for name in before where !after.contains(name) { sink.release(name) }
            for name in after where !before.contains(name) { sink.press(name) }
            held[c.id] = after.isEmpty ? nil : after
        }
    }

    /// Lets go of everything (rotation, edit mode, the view going away).
    public mutating func releaseAll(sink: Skin2InputSink) {
        for names in held.values { for name in names { sink.release(name) } }
        held.removeAll()
        for entry in sticks.values { sink.stick(entry.input, x: 0, y: 0) }
        sticks.removeAll()
        firedActions.removeAll()
    }
}

/// The haptic a state change earns: a button, trigger, action or thumbstick going down, or a d-pad gaining a
/// direction. Touch surfaces are silent.
public struct Skin2HapticRequest: Equatable, Sendable {
    public var controlID: String
    public var style: String
    public var intensity: Double
}

public enum Skin2Haptics {
    public static let defaultStyle = "medium"
    public static let defaultIntensity = 1.0

    public static func requests(from old: Skin2TouchSnapshot, to new: Skin2TouchSnapshot, tester: Skin2HitTester) -> [Skin2HapticRequest] {
        var out: [Skin2HapticRequest] = []
        for c in tester.controls where c.kind != .touchSurface {
            guard let after = new.states[c.id], after.isPressed else { continue }
            let before = old.states[c.id]
            let newlyPressed = !(before?.isPressed ?? false)
            let newDirection = c.kind == .dpad && !after.directions.subtracting(before?.directions ?? []).isEmpty
            guard newlyPressed || newDirection else { continue }
            out.append(Skin2HapticRequest(controlID: c.id, style: c.haptic?.style ?? defaultStyle,
                                          intensity: c.haptic?.intensity ?? defaultIntensity))
        }
        return out
    }
}

/// The 80 ms pressed-scale ease (6.4), per control. Everything else in a state switches at once. Pressing again
/// while a control is still easing out turns around from where it is rather than jumping.
public struct Skin2ScaleEasing: Equatable, Sendable {
    public static let duration: TimeInterval = 0.08

    struct Track: Equatable, Sendable {
        var from: Double
        var to: Double
        var start: TimeInterval
    }

    private var tracks: [String: Track] = [:]
    public init() {}

    /// Ease-out quadratic, 0 to 1.
    static func curve(_ t: Double) -> Double {
        let c = min(max(t, 0), 1)
        return 1 - (1 - c) * (1 - c)
    }

    /// The control's scale progress now: 0 at rest, 1 fully pressed. Nil when it isn't being eased.
    public func progress(_ id: String, at now: TimeInterval) -> Double? {
        guard let t = tracks[id] else { return nil }
        return t.from + (t.to - t.from) * Self.curve((now - t.start) / Self.duration)
    }

    /// Tells the easing which controls are pressed now; call whenever the held set changes.
    public mutating func update(pressed: Set<String>, at now: TimeInterval) {
        for id in pressed where tracks[id]?.to != 1 {
            tracks[id] = Track(from: progress(id, at: now) ?? 0, to: 1, start: now)
        }
        for (id, t) in tracks where t.to == 1 && !pressed.contains(id) {
            tracks[id] = Track(from: progress(id, at: now) ?? 1, to: 0, start: now)
        }
    }

    public func isAnimating(at now: TimeInterval) -> Bool {
        tracks.values.contains { now - $0.start < Self.duration }
    }

    /// Drops finished releases.
    public mutating func prune(at now: TimeInterval) {
        tracks = tracks.filter { $0.value.to == 1 || now - $0.value.start < Self.duration }
    }

    /// `states` with `scaleProgress` set from the easing. A control just released and still easing out appears
    /// with its remaining state (or the empty one) and `easingOut`, so only its pressed scale is drawn.
    public func apply(to states: [String: Skin2ControlState], at now: TimeInterval) -> [String: Skin2ControlState] {
        var out = states
        for id in tracks.keys {
            guard let p = progress(id, at: now) else { continue }
            var s = out[id] ?? Skin2ControlState()
            if s.isPressed {
                s.scaleProgress = p
            } else if p > 0 {
                s.scaleProgress = p
                s.easingOut = true
            } else {
                continue
            }
            out[id] = s
        }
        return out
    }
}
