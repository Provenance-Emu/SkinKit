import Foundation
import SkinKit2Core

/// A d-pad direction (6.1).
public enum Skin2Direction: String, Sendable, CaseIterable, Hashable {
    case up, down, left, right
}

/// What a control is doing right now, for drawing its states (6.4) and moving its knob (6.2).
public struct Skin2ControlState: Equatable, Hashable, Sendable {
    /// A button, trigger or action is held; a d-pad counts as pressed while any direction is.
    public var pressed: Bool
    public var selected: Bool
    /// D-pads: the directions held (a diagonal holds two).
    public var directions: Set<Skin2Direction>
    /// Thumbsticks: the knob's displacement as a fraction of `travel`, inside the unit circle; +x right, +y down.
    public var stick: Skin2StickValue
    /// How far the pressed `scale` has eased in, 0 to 1. Hosts animate it over 80 ms (6.4); everything else in a
    /// state switches at once.
    public var scaleProgress: Double

    public init(pressed: Bool = false, selected: Bool = false, directions: Set<Skin2Direction> = [],
                stick: Skin2StickValue = .zero, scaleProgress: Double = 1) {
        self.pressed = pressed; self.selected = selected; self.directions = directions; self.stick = stick
        self.scaleProgress = scaleProgress
    }

    /// Pressed, or a d-pad with a direction held.
    public var isPressed: Bool { pressed || !directions.isEmpty }

    /// The `states` entries that apply, in the order they apply: `selected`, `pressed`, then `pressed.up`,
    /// `pressed.down`, `pressed.left`, `pressed.right`. Later patches win; scales and opacities multiply.
    public var stateNames: [String] {
        var out: [String] = []
        if selected { out.append("selected") }
        if isPressed { out.append("pressed") }
        for d in Skin2Direction.allCases where directions.contains(d) { out.append("pressed.\(d.rawValue)") }
        return out
    }
}

/// A thumbstick value: offset over travel, clamped to the unit circle. +x right, +y down (screen axes); apps that
/// send y-up axes negate `y`.
public struct Skin2StickValue: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        let m = (x * x + y * y).squareRoot()
        if m > 1 { self.x = x / m; self.y = y / m } else { self.x = x; self.y = y }
    }
    public static let zero = Skin2StickValue(x: 0, y: 0)
}
