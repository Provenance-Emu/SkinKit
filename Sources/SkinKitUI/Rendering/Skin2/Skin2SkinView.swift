#if canImport(UIKit)
import SkinKit2Core
import SkinKit2Render
import SwiftUI

/// A control's input changed: the control, its new state, and the input names it now holds (a d-pad's held
/// directions, every input of a pressed button, nothing on release).
public struct Skin2InputEvent: Equatable, Sendable {
    public var control: Skin2HitTester.Control
    public var state: Skin2ControlState
    public var inputs: [String]
    /// Touch surfaces: the touch in 0–1 across the frame; nil on release.
    public var surfacePoint: CGPoint?
}

/// Draws a format 2.0 skin (`skin.json`) with the `SkinKit2Render` drawer in a SwiftUI `Canvas`, through
/// `GraphicsContext.withCGContext`, so the app and the reference images share one drawer (9.1).
///
/// The view resolves the document for its own size and safe area on every layout pass. On iOS one finger drives
/// the controls (frame hit testing, d-pad zones, thumbstick travel; 6.1); pressed `scale`s ease in over 80 ms
/// (6.4). tvOS draws the skin without touch handling. Multi-touch clusters and haptics are left to the host for now.
public struct Skin2SkinView: View {
    public let document: Skin2Document
    public var device: Skin2Device
    public var displayType: Skin2DisplayType
    public var flags: Set<String>
    public var edits: [String: Skin2Edit]
    public var screenPlaceholders: Bool
    public var showHitFrames: Bool
    /// Bytes of a file under the bundle's `assets/` (images, and fonts as `fonts/<family>`).
    public var asset: (@Sendable (String) -> Data?)?
    public var onInput: (Skin2InputEvent) -> Void

    @State private var states: [String: Skin2ControlState] = [:]
    @State private var activeControl: String?
    @State private var changedAt: [String: Date] = [:]
    @State private var tick = 0

    /// The pressed-scale ease (6.4).
    static let scaleDuration: TimeInterval = 0.08

    public init(document: Skin2Document, device: Skin2Device = .iphone, displayType: Skin2DisplayType = .edgeToEdge,
                flags: Set<String> = [], edits: [String: Skin2Edit] = [:], screenPlaceholders: Bool = false,
                showHitFrames: Bool = false, asset: (@Sendable (String) -> Data?)? = nil,
                onInput: @escaping (Skin2InputEvent) -> Void = { _ in }) {
        self.document = document
        self.device = device
        self.displayType = displayType
        self.flags = flags
        self.edits = edits
        self.screenPlaceholders = screenPlaceholders
        self.showHitFrames = showHitFrames
        self.asset = asset
        self.onInput = onInput
    }

    public var body: some View {
        GeometryReader { outer in
            let insets = outer.safeAreaInsets
            GeometryReader { inner in
                let resolution = resolve(size: inner.size, insets: insets)
                TimelineView(.animation(minimumInterval: nil, paused: !isEasing(Date()))) { timeline in
                    Canvas(rendersAsynchronously: false) { context, _ in
                        let options = Skin2RenderOptions(states: easedStates(at: timeline.date), screenPlaceholders: screenPlaceholders,
                                                         showHitFrames: showHitFrames, asset: asset)
                        context.withCGContext { cg in Skin2Renderer.draw(resolution, in: cg, options: options) }
                    }
                }
                #if os(iOS)
                .contentShape(Rectangle())
                .gesture(touchGesture(Skin2HitTester(resolution)))
                #endif
            }
            .ignoresSafeArea()
        }
    }

    func resolve(size: CGSize, insets: EdgeInsets) -> Skin2Resolution {
        let env = Skin2Environment(size: Skin2Size(width: size.width, height: size.height),
                                   safeArea: Skin2Insets(top: insets.top, left: insets.leading, bottom: insets.bottom, right: insets.trailing),
                                   device: device, displayType: displayType, flags: flags)
        return Skin2Resolver.resolve(document, in: env, edits: edits)
    }

    // MARK: State easing

    private func isEasing(_ now: Date) -> Bool {
        _ = tick
        return changedAt.values.contains { now.timeIntervalSince($0) < Self.scaleDuration }
    }

    /// Each control's state with `scaleProgress` eased toward it: in from rest while pressed, back out after release.
    private func easedStates(at now: Date) -> [String: Skin2ControlState] {
        var out = states
        for (id, at) in changedAt {
            let t = min(1, max(0, now.timeIntervalSince(at) / Self.scaleDuration))
            let eased = 1 - (1 - t) * (1 - t)
            if var s = out[id] {
                s.scaleProgress = eased
                out[id] = s
            } else if t < 1 {
                // Released: the pressed scale eases back out; the art is already at rest.
                out[id] = Skin2ControlState(scaleProgress: 1 - eased, easingOut: true)
            }
        }
        return out
    }

    private func set(_ id: String, _ state: Skin2ControlState?) {
        let wasPressed = states[id]?.isPressed ?? false
        states[id] = state
        if (state?.isPressed ?? false) != wasPressed {
            changedAt[id] = Date()
            // Re-evaluate after the ease so the timeline pauses again.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.scaleDuration + 0.02) { tick &+= 1 }
        }
    }

    // MARK: Touches (iOS)

    #if os(iOS)
    private func touchGesture(_ tester: Skin2HitTester) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let p = value.location
                // A drag keeps its control (rolling across a d-pad, a stick past its travel) until it lifts.
                let control = activeControl.flatMap(tester.control(id:)) ?? tester.control(at: p.x, p.y)
                guard let control else { return }
                if activeControl != control.id {
                    if let old = activeControl, let c = tester.control(id: old) { release(c) }
                    activeControl = control.id
                }
                var state = Skin2HitTester.state(for: control, x: p.x, y: p.y)
                state.selected = states[control.id]?.selected ?? false
                guard Skin2HitTester.isNewSample(control, state: state, previous: states[control.id]) else { return }
                if control.kind == .action, states[control.id]?.isPressed == true { return }
                if state != states[control.id] { set(control.id, state) }
                var point: CGPoint?
                if control.kind == .touchSurface {
                    let s = Skin2HitTester.surfacePoint(frame: control.frame, x: p.x, y: p.y)
                    point = CGPoint(x: s.x, y: s.y)
                }
                onInput(Skin2InputEvent(control: control, state: state, inputs: Skin2HitTester.inputs(for: control, state: state), surfacePoint: point))
            }
            .onEnded { _ in
                if let id = activeControl, let c = tester.control(id: id) { release(c) }
                activeControl = nil
            }
    }

    private func release(_ c: Skin2HitTester.Control) {
        let state = Skin2ControlState(selected: states[c.id]?.selected ?? false)
        set(c.id, state.selected ? state : nil)
        onInput(Skin2InputEvent(control: c, state: state, inputs: [], surfacePoint: nil))
    }
    #endif
}

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
