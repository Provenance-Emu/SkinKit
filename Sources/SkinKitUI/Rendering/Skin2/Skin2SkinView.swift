#if canImport(UIKit)
import Combine
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
///
/// Accessory panels: the app says what it can supply right now in `capabilities` and hands over the pictures in a
/// `Skin2PictureStore`. Each accessory screen the app can fill gets a layer of its own, with the skin drawn in
/// parts under and over it; a skin with none is one canvas as before. The view owns which shelves are open (their
/// handles toggle them, and never reach `onInput`) and reports what the skin itself gives the player through
/// `onProvidedChange`, so the app can hide its own copy and bring it back the moment the skin stops.
public struct Skin2SkinView: View {
    public let document: Skin2Document
    public var device: Skin2Device
    public var displayType: Skin2DisplayType
    /// Hosts that simulate a device supply its safe area explicitly.
    public var safeAreaOverride: Skin2Insets?
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
    /// What the app and the running game can supply now (`picture.vmu.p1`, `input.arcade.coin1`).
    public var capabilities: Set<String>
    /// The app's pictures for accessory screens. Nil: accessory screens show nothing.
    public var pictures: Skin2PictureStore?
    /// Names the skin when remembering which shelves the player left open. Nil: not remembered.
    public var skinIdentifier: String?
    /// What the skin provides, on appear and whenever it changes; `.none` when the view goes away. `pictures` holds
    /// only sources the app has delivered a picture for.
    public var onProvidedChange: ((Skin2Provided) -> Void)?

    private let extendsIntoSafeArea: Bool

    @StateObject private var panelState: Skin2PanelState
    @State private var delivered: Set<String>
    @State private var transition: Transition?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A shelf opening or closing: the layout it started from and when.
    private struct Transition: Equatable {
        var from: Skin2Resolution
        var start: TimeInterval
    }

    /// How long a shelf takes to open or close.
    static let shelfDuration: TimeInterval = 0.2

    @State private var snapshot = Skin2TouchSnapshot.empty
    @State private var easing = Skin2ScaleEasing()
    @State private var tick = 0

    /// Set `extendsIntoSafeArea` to false when embedding the skin in a bounded view.
    public init(document: Skin2Document, device: Skin2Device = .iphone, displayType: Skin2DisplayType = .edgeToEdge,
                flags: Set<String> = [], edits: [String: Skin2Edit] = [:], screenPlaceholders: Bool = false,
                showHitFrames: Bool = false, selected: Set<String> = [], playsHaptics: Bool = true,
                asset: (@Sendable (String) -> Data?)? = nil,
                onInput: @escaping (Skin2InputEvent) -> Void = { _ in },
                onLayout: ((Skin2Resolution) -> Void)? = nil,
                onReleaseAll: @escaping () -> Void = {}, safeAreaOverride: Skin2Insets? = nil,
                capabilities: Set<String> = [], pictures: Skin2PictureStore? = nil, skinIdentifier: String? = nil,
                onProvidedChange: ((Skin2Provided) -> Void)? = nil, extendsIntoSafeArea: Bool = true) {
        self.extendsIntoSafeArea = extendsIntoSafeArea
        self.capabilities = capabilities
        self.pictures = pictures
        self.skinIdentifier = skinIdentifier
        self.onProvidedChange = onProvidedChange
        // Seeded from the store, so a view that replaces another (a rotation that rebuilds it) reports the picture
        // in its first report and the app's own copy does not flash.
        _delivered = State(initialValue: pictures?.delivered ?? [])
        _panelState = StateObject(wrappedValue: Skin2PanelState(document: document, skinIdentifier: skinIdentifier))
        self.safeAreaOverride = safeAreaOverride
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
        var capabilities: Set<String>
    }

    /// The app's flags plus the open flags of the shelves; the skin view owns every `panel.*` flag.
    private var allFlags: Set<String> {
        flags.filter { !$0.hasPrefix(Skin2Panel.flagPrefix) }.union(panelState.flags)
    }

    private var deliveredChanges: AnyPublisher<Set<String>, Never> {
        pictures?.deliveredChanges ?? Just([]).eraseToAnyPublisher()
    }

    public var body: some View {
        GeometryReader { outer in
            let actual = outer.safeAreaInsets
            let insets = safeAreaOverride.map {
                EdgeInsets(top: $0.top, leading: $0.left, bottom: $0.bottom, trailing: $0.right)
            } ?? actual
            GeometryReader { inner in
                let resolution = resolve(size: inner.size, insets: insets)
                let tester = Skin2HitTester(resolution)
                let key = LayoutKey(size: inner.size, insets: [insets.top, insets.leading, insets.bottom, insets.trailing],
                                    device: device, displayType: displayType, flags: allFlags, capabilities: capabilities)
                let provided = resolution.provided.keeping(pictures: delivered)
                TimelineView(.animation(minimumInterval: nil, paused: !isAnimating)) { timeline in
                    let now = timeline.date.timeIntervalSinceReferenceDate
                    layers(drawnLayout(resolution, at: now), states: drawnStates(at: now))
                }
                #if os(iOS)
                .overlay(
                    Skin2TouchSurface(tester: tester, onSnapshot: { apply($0, tester: tester, resolution: resolution) },
                                      onReleaseAll: onReleaseAll)
                )
                .overlay(handleAccessibility(resolution, tester: tester))
                #endif
                .task(id: key) { onLayout?(resolution) }
                .task(id: provided) {
                    // A task cancelled before it ran belongs to a view that is already gone.
                    guard !Task.isCancelled else { return }
                    onProvidedChange?(provided)
                }
            }
            .ignoresSafeArea(edges: extendsIntoSafeArea ? .all : [])
        }
        .onReceive(deliveredChanges) { delivered = $0 }
        .onChange(of: document) { _, new in panelState.adopt(document: new, skinIdentifier: skinIdentifier) }
        .onDisappear { onProvidedChange?(.none) }
    }

    // MARK: Layers

    /// The skin as one canvas, or, when the app can fill accessory screens, in parts with each screen's picture
    /// in a layer between the part under it and the part over it.
    @ViewBuilder
    private func layers(_ layout: Skin2Resolution, states: [String: Skin2ControlState]) -> some View {
        let live = pictures == nil ? [] : layout.accessoryScreens.filter { screen in
            screen.node.source.map { capabilities.contains(Skin2Capabilities.picture($0)) } ?? false
        }
        if let pictures, !live.isEmpty {
            ZStack(alignment: .topLeading) {
                canvas(layout, part: .upTo(screen: live[0].pointer), states: states)
                ForEach(Array(live.enumerated()), id: \.element.pointer) { index, screen in
                    Skin2PictureLayerView(store: pictures, source: screen.node.source ?? "", sampling: screen.node.sampling ?? .nearest)
                        .frame(width: screen.frame.width, height: screen.frame.height)
                        .position(x: screen.frame.midX, y: screen.frame.midY)
                        .opacity(layout.effectiveOpacity(of: screen.pointer))
                        .allowsHitTesting(false)
                    canvas(layout, part: index + 1 < live.count ? .between(after: screen.pointer, upTo: live[index + 1].pointer)
                                                                : .after(screen: screen.pointer), states: states)
                }
            }
        } else {
            canvas(layout, part: .all, states: states)
        }
    }

    private func canvas(_ layout: Skin2Resolution, part: Skin2DrawPart, states: [String: Skin2ControlState]) -> some View {
        Canvas(rendersAsynchronously: false) { context, _ in
            var options = Skin2RenderOptions(states: states, screenPlaceholders: screenPlaceholders, showHitFrames: showHitFrames, asset: asset)
            options.part = part
            context.withCGContext { cg in Skin2Renderer.draw(layout, in: cg, options: options) }
        }
        .allowsHitTesting(false)
    }

    /// The layout to draw: while a shelf moves, the blend between where it started and where it is going.
    private func drawnLayout(_ resolution: Skin2Resolution, at now: TimeInterval) -> Skin2Resolution {
        guard let transition, transition.from.environment.size == resolution.environment.size else { return resolution }
        let t = (now - transition.start) / Self.shelfDuration
        guard t < 1 else { return resolution }
        let eased = max(0, t) * max(0, t) * (3 - 2 * max(0, t))
        return Skin2LayoutBlend.blend(from: transition.from, to: resolution, progress: eased)
    }

    private var isAnimating: Bool {
        if let transition, Self.now < transition.start + Self.shelfDuration { return true }
        return isEasing
    }

    // MARK: Shelves

    /// Opens or closes a shelf. The new layout arrives on the next pass; the touch layer lets go of any control
    /// the new layout no longer has, which releases the app's inputs.
    private func toggle(_ panel: String, from resolution: Skin2Resolution) {
        if !reduceMotion {
            transition = Transition(from: resolution, start: Self.now)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.shelfDuration + 0.02) {
                if let current = transition, Self.now >= current.start + Self.shelfDuration { transition = nil }
                tick &+= 1
            }
        }
        panelState.toggle(panel)
    }

    #if os(iOS)
    /// Each shelf's handle as a button for VoiceOver: "Visual Memory, open".
    private func handleAccessibility(_ resolution: Skin2Resolution, tester: Skin2HitTester) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(resolution.panels.filter { $0.presentation == .shelf }, id: \.panel.name) { panel in
                if let handle = tester.controls.first(where: { $0.togglesPanel == panel.panel.name }) {
                    Color.clear
                        .frame(width: handle.hitFrame.width, height: handle.hitFrame.height)
                        .position(x: handle.hitFrame.midX, y: handle.hitFrame.midY)
                        .accessibilityElement()
                        .accessibilityLabel(Text(verbatim: "\(panel.panel.label ?? panel.panel.name), \(panel.isOpen ? "open" : "closed")"))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { toggle(panel.panel.name, from: resolution) }
                }
            }
        }
        .allowsHitTesting(false)
    }
    #endif

    static var now: TimeInterval { Date.timeIntervalSinceReferenceDate }

    /// Reads `tick`, so the view re-evaluates once an ease is over and the timeline pauses.
    private var isEasing: Bool {
        _ = tick
        return easing.isAnimating(at: Self.now)
    }

    func resolve(size: CGSize, insets: EdgeInsets) -> Skin2Resolution {
        let env = Skin2Environment(size: Skin2Size(width: size.width, height: size.height),
                                   safeArea: Skin2Insets(top: insets.top, left: insets.leading, bottom: insets.bottom, right: insets.trailing),
                                   device: device, displayType: displayType, flags: allFlags, capabilities: capabilities)
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
    private func apply(_ new: Skin2TouchSnapshot, tester: Skin2HitTester, resolution: Skin2Resolution) {
        let old = snapshot
        guard new != old else { return }
        snapshot = new
        // A shelf's handle belongs to this view: it toggles the shelf and is never an input event.
        for panel in skin2PanelToggles(from: old, to: new, tester: tester) { toggle(panel, from: resolution) }
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
        // A held control the new layout no longer has (hidden by a flag, a document change) would get no
        // release event from the new tester: let go of every finger, which also releases the host's inputs.
        if current.holdsControls(missingFrom: tester) {
            releaseAll()
            tracker.setTester(tester)
            return
        }
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
            tracker.began(ObjectIdentifier(t), x: p.x, y: p.y, pressure: normalizedPressure(t))
        }
        emit()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let p = t.location(in: self)
            tracker.moved(ObjectIdentifier(t), x: p.x, y: p.y, pressure: normalizedPressure(t))
        }
        emit()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }

    private func normalizedPressure(_ touch: UITouch) -> Double? {
        guard touch.maximumPossibleForce > 0, touch.force > 0 else { return nil }
        return Double(touch.force / touch.maximumPossibleForce)
    }

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
