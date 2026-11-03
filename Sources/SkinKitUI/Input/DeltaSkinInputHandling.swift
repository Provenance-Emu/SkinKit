#if canImport(UIKit)
import SkinKitCore
import SwiftUI
import UIKit

/// What the skin views need from the host's input handler.
///
/// In Provenance the skin views took the concrete `DeltaSkinInputHandler`, which forwards button,
/// stick and touch events to the emulator core (and intercepts frontend commands). That class is app
/// code, so SkinKitUI depends on this protocol instead. The app's handler conforms; the previews and
/// tests use ``DeltaSkinPreviewInputHandler``.
public protocol DeltaSkinInputHandling: AnyObject {
    /// A skin button went down. `buttonId` is the input token (`"a"`, `"menu"`, ...).
    func buttonPressed(_ buttonId: String)
    /// A skin button came up.
    func buttonReleased(_ buttonId: String)
    /// A thumbstick moved. `x` and `y` are in -1...1, y up.
    func analogStickMoved(_ stickId: String, x: Float, y: Float)
    /// A touch landed on, or moved over, the DS bottom screen. `normalizedPoint` is in 0...1 of that screen.
    func ndsBottomScreenTouched(at normalizedPoint: CGPoint)
    /// The DS bottom-screen touch ended.
    func ndsBottomScreenTouchReleased()
    /// Whether the DS top and bottom screens are swapped.
    var dsScreensSwapped: Bool { get }
    /// Turbo (autofire) state, observed by the skin view.
    var turboManager: TurboManager { get }
    /// Sticky (toggle-held) button state.
    var stickyManager: StickyButtonManager { get }
    /// Whether the token is a gameplay input or a frontend / console-system control.
    ///
    /// The role must agree with what ``buttonPressed(_:)`` does with the token, so it lives with the
    /// handler. The default treats every token as gameplay.
    func touchRole(forToken token: String) -> TouchInputRole
    /// What a press-and-hold on an empty area does, for a view created with `allowsEmptyAreaHold`.
    /// `nil` (the default): nothing; see ``DeltaSkinHoldHandling``.
    var holdHandler: (any DeltaSkinHoldHandling)? { get }
    /// The skin's `toggleAltRepresentations` button was pressed (Ignited's alternate layout).
    ///
    /// Called once per press, never for the release, and never through ``buttonPressed(_:)``. The host flips
    /// `DeltaSkinTraits.usesAltRepresentations` for the skin views it shows (and persists it per game with
    /// `DeltaSkinSelectionManager.setUsesAltRepresentations`), then re-runs any layout it derives from the skin's
    /// screens, such as a dual-screen or external-display viewport. The default posts
    /// ``DeltaSkinAltRepresentationsToggle/requestedNotification`` with the handler as the object.
    func toggleAltRepresentations()
}

public extension DeltaSkinInputHandling {
    func touchRole(forToken token: String) -> TouchInputRole { .gameplay }
    var holdHandler: (any DeltaSkinHoldHandling)? { nil }
    func toggleAltRepresentations() {
        NotificationCenter.default.post(name: DeltaSkinAltRepresentationsToggle.requestedNotification, object: self)
    }
}

/// The `toggleAltRepresentations` skin input.
public enum DeltaSkinAltRepresentationsToggle {
    /// Posted by the default ``DeltaSkinInputHandling/toggleAltRepresentations()`` when the skin's toggle button
    /// is pressed. The object is the input handler.
    public static let requestedNotification = Notification.Name("DeltaSkinAltRepresentationsToggleRequested")

    /// The input token, `"toggleAltRepresentations"`.
    public static var input: String { DeltaSkin.toggleAltRepresentationsInput }
}

/// An input handler that forwards nothing to an emulator: it records state, so the skin views are
/// usable in previews, tests and screens that only display a skin. Sticky and turbo bookkeeping works.
public final class DeltaSkinPreviewInputHandler: DeltaSkinInputHandling, ObservableObject {
    public let turboManager = TurboManager()
    public let stickyManager = StickyButtonManager()
    public var dsScreensSwapped = false

    /// Buttons currently held, for tests.
    public private(set) var pressedButtons: Set<String> = []
    /// The last position reported for each stick, for tests.
    public private(set) var stickPositions: [String: CGPoint] = [:]
    /// The last DS bottom-screen touch (nil once released), for tests.
    public private(set) var ndsTouch: CGPoint?
    /// Whether the previewed skin shows its alternate layout. Flipped by the skin's `toggleAltRepresentations` button;
    /// a preview builds its traits with `usesAltRepresentations: usesAltRepresentations`.
    @Published public var usesAltRepresentations = false
    /// How many times the toggle button was pressed, for tests.
    public private(set) var altRepresentationsToggleCount = 0

    public init() {}

    public func buttonPressed(_ buttonId: String) { pressedButtons.insert(buttonId) }
    public func buttonReleased(_ buttonId: String) { pressedButtons.remove(buttonId) }
    public func analogStickMoved(_ stickId: String, x: Float, y: Float) {
        stickPositions[stickId] = CGPoint(x: CGFloat(x), y: CGFloat(y))
    }
    public func ndsBottomScreenTouched(at normalizedPoint: CGPoint) { ndsTouch = normalizedPoint }
    public func ndsBottomScreenTouchReleased() { ndsTouch = nil }
    public func toggleAltRepresentations() {
        altRepresentationsToggleCount += 1
        usesAltRepresentations.toggle()
    }
}

// MARK: - Environment

private struct DeltaSkinInputHandlerKey: EnvironmentKey {
    static let defaultValue: any DeltaSkinInputHandling = DeltaSkinPreviewInputHandler()
}

public extension EnvironmentValues {
    /// The input handler for skin views that do not take one as a parameter (``DeltaSkinScreensView``).
    /// Replaces Provenance's `.environmentObject(inputHandler)`. The default forwards nothing.
    var deltaSkinInputHandler: any DeltaSkinInputHandling {
        get { self[DeltaSkinInputHandlerKey.self] }
        set { self[DeltaSkinInputHandlerKey.self] = newValue }
    }
}

public extension View {
    /// Supplies the input handler to skin views below.
    func deltaSkinInputHandler(_ handler: any DeltaSkinInputHandling) -> some View {
        environment(\.deltaSkinInputHandler, handler)
    }
}
#endif
