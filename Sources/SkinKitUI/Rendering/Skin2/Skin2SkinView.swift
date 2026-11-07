#if canImport(UIKit)
import SkinKit2Core
import SkinKit2Render
import SkinKitCore
import SwiftUI
import UIKit

/// Draws a format 2.0 skin (`skin.json`) with the `SkinKit2Render` drawer in a SwiftUI `Canvas`, through
/// `GraphicsContext.withCGContext`, so the app and the reference images share one drawer (9.1).
///
/// The view resolves the document for its own size and safe area on every layout pass. On iOS a multi-touch
/// overlay drives the controls (section 6): frame hit testing, d-pad zones, thumbstick travel, touch surfaces,
/// one finger per stick, a finger dragging across buttons. Pressed `scale`s ease in over 80 ms (6.4) and each
/// press plays the control's haptic. The rules live in `SkinKit2Render` (`Skin2TouchTracker`, `Skin2Haptics`,
/// `Skin2ScaleEasing`) and are tested on the macOS host. tvOS draws the skin without touch handling.
public struct Skin2SkinView: View {
    public let document: Skin2Document
    public var device: Skin2Device
    public var displayType: Skin2DisplayType
    public var flags: Set<String>
    public var edits: [String: Skin2Edit]
    public var screenPlaceholders: Bool
    public var showHitFrames: Bool
    /// Controls drawn in their `selected` state (a toggled switch, a sticky button).
    public var selected: Set<String>
    /// Plays each control's `haptic` when it goes down. Off for previews.
    public var playsHaptics: Bool
    /// Bytes of a file under the bundle's `assets/` (images, and fonts as `fonts/<family>`).
    public var asset: (@Sendable (String) -> Data?)?
    public var onInput: (Skin2InputEvent) -> Void
    /// Called with the resolved layout whenever the size, safe area, device or flags change (and on appear).
    public var onLayout: ((Skin2Resolution) -> Void)?
    /// Called when the view lets go of everything (it disappears, or the canvas changes shape mid-touch).
    public var onReleaseAll: () -> Void

    @State private var snapshot = Skin2TouchSnapshot.empty
    @State private var easing = Skin2ScaleEasing()
    @State private var tick = 0

    public init(document: Skin2Document, device: Skin2Device = .iphone, displayType: Skin2DisplayType = .edgeToEdge,
                flags: Set<String> = [], edits: [String: Skin2Edit] = [:], screenPlaceholders: Bool = false,
                showHitFrames: Bool = false, selected: Set<String> = [], playsHaptics: Bool = true,
                asset: (@Sendable (String) -> Data?)? = nil,
                onInput: @escaping (Skin2InputEvent) -> Void = { _ in },
                onLayout: ((Skin2Resolution) -> Void)? = nil,
                onReleaseAll: @escaping () -> Void = {}) {
        self.document = document
        self.device = device
        self.displayType = displayType
        self.flags = flags
        self.edits = edits
        self.screenPlaceholders = screenPlaceholders
        self.showHitFrames = showHitFrames
        self.selected = selected
        self.playsHaptics = playsHaptics
        self.asset = asset
        self.onInput = onInput
        self.onLayout = onLayout
        self.onReleaseAll = onReleaseAll
    }

    private struct LayoutKey: Hashable {
        var size: CGSize
        var insets: [CGFloat]
        var device: Skin2Device
        var displayType: Skin2DisplayType
        var flags: Set<String>
    }

    public var body: some View {
        GeometryReader { outer in
            let insets = outer.safeAreaInsets
            GeometryReader { inner in
                let resolution = resolve(size: inner.size, insets: insets)
                let tester = Skin2HitTester(resolution)
                let key = LayoutKey(size: inner.size, insets: [insets.top, insets.leading, insets.bottom, insets.trailing],
                                    device: device, displayType: displayType, flags: flags)
                TimelineView(.animation(minimumInterval: nil, paused: !isEasing)) { timeline in
                    Canvas(rendersAsynchronously: false) { context, _ in
                        let options = Skin2RenderOptions(states: drawnStates(at: timeline.date.timeIntervalSinceReferenceDate),
                                                         screenPlaceholders: screenPlaceholders,
                                                         showHitFrames: showHitFrames, asset: asset)
                        context.withCGContext { cg in Skin2Renderer.draw(resolution, in: cg, options: options) }
                    }
                }
                #if os(iOS)
                .overlay(
                    Skin2TouchSurface(tester: tester, onSnapshot: { apply($0, tester: tester) }, onReleaseAll: onReleaseAll)
                )
                #endif
                .task(id: key) { onLayout?(resolution) }
            }
            .ignoresSafeArea()
        }
    }

    static var now: TimeInterval { Date.timeIntervalSinceReferenceDate }

    /// Reads `tick`, so the view re-evaluates once an ease is over and the timeline pauses.
    private var isEasing: Bool {
        _ = tick
        return easing.isAnimating(at: Self.now)
    }

    func resolve(size: CGSize, insets: EdgeInsets) -> Skin2Resolution {
        let env = Skin2Environment(size: Skin2Size(width: size.width, height: size.height),
                                   safeArea: Skin2Insets(top: insets.top, left: insets.leading, bottom: insets.bottom, right: insets.trailing),
                                   device: device, displayType: displayType, flags: flags)
        return Skin2Resolver.resolve(document, in: env, edits: edits)
    }

    // MARK: States

    /// The held states with the selected controls and the 80 ms scale ease folded in.
    private func drawnStates(at now: TimeInterval) -> [String: Skin2ControlState] {
        var states = snapshot.states
        for id in selected { states[id, default: Skin2ControlState()].selected = true }
        return easing.apply(to: states, at: now)
    }

    #if os(iOS)
    /// A touch change: ease the scales, play haptics, tell the host.
    private func apply(_ new: Skin2TouchSnapshot, tester: Skin2HitTester) {
        let old = snapshot
        guard new != old else { return }
        snapshot = new
        let now = Self.now
        easing.update(pressed: Set(new.states.filter { $0.value.isPressed }.keys), at: now)
        // Re-evaluate once the ease is over so the timeline pauses again.
        DispatchQueue.main.asyncAfter(deadline: .now() + Skin2ScaleEasing.duration + 0.02) {
            easing.prune(at: Self.now)
            tick &+= 1
        }
        if playsHaptics {
            for h in Skin2Haptics.requests(from: old, to: new, tester: tester) {
                DeltaSkinHaptic(style: h.style, intensity: h.intensity).play()
            }
        }
        for event in skin2InputEvents(from: old, to: new, tester: tester) { onInput(event) }
    }
    #endif
}

#if os(iOS)
/// The multi-touch layer over the drawn skin: feeds every finger to a `Skin2TouchTracker` and reports the
/// resulting snapshot. Touches that begin where no control is pass through to whatever is below.
struct Skin2TouchSurface: UIViewRepresentable {
    var tester: Skin2HitTester
    var onSnapshot: (Skin2TouchSnapshot) -> Void
    var onReleaseAll: () -> Void

    func makeUIView(context: Context) -> Skin2TouchUIView {
        let view = Skin2TouchUIView(tester: tester)
        view.onSnapshot = onSnapshot
        view.onReleaseAll = onReleaseAll
        return view
    }

    func updateUIView(_ view: Skin2TouchUIView, context: Context) {
        view.onSnapshot = onSnapshot
        view.onReleaseAll = onReleaseAll
        view.update(tester: tester)
    }
}

final class Skin2TouchUIView: UIView {
    var onSnapshot: (Skin2TouchSnapshot) -> Void = { _ in }
    var onReleaseAll: () -> Void = {}
    private var tracker: Skin2TouchTracker<ObjectIdentifier>
    private var current = Skin2TouchSnapshot.empty
    private var lastSize = CGSize.zero

    init(tester: Skin2HitTester) {
        tracker = Skin2TouchTracker(tester: tester)
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(tester: Skin2HitTester) {
        guard tester != tracker.tester else { return }
        // A relayout from rotation or a resize moves every control: let go of the fingers.
        if bounds.size != lastSize, !tracker.isEmpty { releaseAll(); return }
        tracker.setTester(tester)
        if !tracker.isEmpty { emit() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastSize {
            lastSize = bounds.size
            if !tracker.isEmpty { releaseAll() }
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil, !tracker.isEmpty { releaseAll() }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        super.point(inside: point, with: event) && tracker.tester.control(at: point.x, point.y) != nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let p = t.location(in: self)
            tracker.began(ObjectIdentifier(t), x: p.x, y: p.y)
        }
        emit()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let p = t.location(in: self)
            tracker.moved(ObjectIdentifier(t), x: p.x, y: p.y)
        }
        emit()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }

    private func end(_ touches: Set<UITouch>) {
        for t in touches { tracker.ended(ObjectIdentifier(t)) }
        emit()
    }

    private func releaseAll() {
        tracker.removeAll()
        emit()
        onReleaseAll()
    }

    private func emit() {
        let next = tracker.snapshot()
        guard next != current else { return }
        current = next
        onSnapshot(next)
    }
}
#endif

#if DEBUG
#Preview("Format 2.0 skin") {
    let json = """
    { "formatVersion": "2.0", "requires": ["layout.anchors", "shapes.parametric", "text"], "identifier": "preview", "name": "Preview",
      "gameTypes": ["com.rileytestut.delta.game.snes"], "reference": { "shortSide": 390, "minScale": 1, "maxScale": 1.35 },
      "root": { "type": "group", "children": [
        { "type": "screen", "id": "screen", "aspect": 1.3333,
          "layout": { "size": { "width": "100%" }, "anchor": { "x": "center", "y": "top", "to": "safeArea" } } },
        { "type": "control", "id": "a", "kind": "button", "input": "a",
          "layout": { "size": { "width": 80, "height": 80 }, "anchor": { "x": "trailing", "y": "bottom", "to": "safeArea" }, "offset": { "x": -24, "y": -40 } },
          "states": { "pressed": { "scale": 0.9 } },
          "children": [ { "type": "shape", "shape": { "kind": "ellipse" }, "fills": [ { "type": "solid", "color": "#52DB66" } ] },
                        { "type": "text", "text": "A", "font": { "size": 22, "weight": "bold" }, "color": "#FFFFFF" } ] } ] } }
    """
    if let doc = try? Skin2Document.load(data: Data(json.utf8)) {
        Skin2SkinView(document: doc, screenPlaceholders: true, showHitFrames: true)
            .background(Color(red: 0.11, green: 0.11, blue: 0.13))
    }
}
#endif
#endif
