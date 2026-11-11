import CoreGraphics
import Foundation
import SkinKit2Core
@testable import SkinKit2Render
import Testing

private let controlsRequires = "[\"shapes.parametric\", \"controls.dpad\", \"controls.thumbstick\", \"controls.touchSurface\"]"

/// Four buttons, a d-pad, a stick, an action and a touch surface under everything, on a 400 × 400 canvas.
private func pad() throws -> Skin2HitTester {
    let doc = try renderSkin(##"""
    { "type": "control", "id": "touch", "kind": "touchSurface", "inputs": ["touchScreen"], "layout": { "frame": [0, 0, 400, 400] } },
    { "type": "control", "id": "a", "kind": "button", "input": "a", "layout": { "frame": [300, 300, 60, 60] },
      "haptic": { "style": "heavy", "intensity": 0.5 } },
    { "type": "control", "id": "b", "kind": "button", "input": "b", "layout": { "frame": [230, 300, 60, 60] } },
    { "type": "control", "id": "dpad", "kind": "dpad", "input": { "up": "up", "down": "down", "left": "left", "right": "right" },
      "layout": { "frame": [20, 280, 100, 100] } },
    { "type": "control", "id": "stick", "kind": "thumbstick", "input": "leftThumbstick", "travel": 20, "layout": { "frame": [20, 150, 80, 80] } },
    { "type": "control", "id": "menu", "kind": "action", "input": "menu", "layout": { "frame": [170, 20, 60, 40] } }
    """##, requires: controlsRequires)
    return Skin2HitTester(Skin2Resolver.resolve(doc, in: Skin2Environment(size: Skin2Size(width: 400, height: 400))))
}

@Suite("Touch tracker")
struct TouchTrackerTests {
    @Test("Two fingers on two buttons hold both; lifting one releases only it")
    func multiTouch() throws {
        var t = Skin2TouchTracker<Int>(tester: try pad())
        t.began(1, x: 330, y: 330)
        t.began(2, x: 260, y: 330)
        #expect(Set(t.snapshot().states.keys) == ["a", "b"])
        t.ended(1)
        #expect(Set(t.snapshot().states.keys) == ["b"])
        t.ended(2)
        #expect(t.snapshot() == .empty)
    }

    @Test("A finger dragging from one button to the next releases the first and presses the second")
    func dragAcross() throws {
        var t = Skin2TouchTracker<Int>(tester: try pad())
        t.began(1, x: 330, y: 330)
        #expect(Set(t.snapshot().states.keys) == ["a"])
        t.moved(1, x: 260, y: 330)
        #expect(Set(t.snapshot().states.keys) == ["b"])
        t.moved(1, x: 260, y: 50)
        // Off the buttons it presses nothing, and does not fall through to the touch surface it didn't start on.
        #expect(t.snapshot() == .empty)
    }

    @Test("A d-pad keeps its finger past the edge and tracks the zone it rolled to")
    func dpadLatch() throws {
        var t = Skin2TouchTracker<Int>(tester: try pad())
        t.began(1, x: 70, y: 330)
        #expect(t.snapshot().states["dpad"]?.directions == [])
        t.moved(1, x: 70, y: 285)
        #expect(t.snapshot().states["dpad"]?.directions == [.up])
        t.moved(1, x: 118, y: 285)
        #expect(t.snapshot().states["dpad"]?.directions == [.up, .right])
        // Far outside the hit frame: still the d-pad, still right/down.
        t.moved(1, x: 390, y: 395)
        #expect(t.snapshot().states["dpad"]?.directions == [.down, .right])
        #expect(t.snapshot().states["touch"] == nil)
    }

    @Test("A d-pad direction holds a few points into the dead zone, then lets go")
    func dpadHysteresis() throws {
        let f = Skin2Rect(x: 0, y: 0, width: 100, height: 100)
        #expect(Skin2HitTester.dpadDirections(in: f, x: 50, y: 41) == [])
        #expect(Skin2HitTester.dpadDirections(in: f, x: 50, y: 41, previous: [.up]) == [.up])
        #expect(Skin2HitTester.dpadDirections(in: f, x: 50, y: 45, previous: [.up]) == [])
    }

    @Test("A stick follows its finger, clamps to the unit circle, and zeroes on release")
    func stick() throws {
        var t = Skin2TouchTracker<Int>(tester: try pad())
        t.began(1, x: 60, y: 190)
        #expect(t.snapshot().states["stick"]?.stick == .zero)
        t.moved(1, x: 70, y: 190)
        let half = try #require(t.snapshot().states["stick"]?.stick)
        #expect(abs(half.x - 0.5) < 1e-9 && half.y == 0)
        t.moved(1, x: 300, y: 190)
        let far = try #require(t.snapshot().states["stick"]?.stick)
        #expect(abs(far.x - 1) < 1e-9)
        t.ended(1)
        #expect(t.snapshot().states["stick"] == nil)
    }

    @Test("One touch per control: a second finger on the stick does nothing")
    func oneTouchPerControl() throws {
        var t = Skin2TouchTracker<Int>(tester: try pad())
        t.began(1, x: 60, y: 190)
        t.began(2, x: 90, y: 190)
        t.moved(1, x: 70, y: 190)
        #expect(abs((t.snapshot().states["stick"]?.stick.x ?? 0) - 0.5) < 1e-9)
        t.ended(1)
        // The second finger never owned it.
        #expect(t.snapshot().states["stick"] == nil)
    }

    @Test("A touch surface reports normalised points and sits under the buttons")
    func surface() throws {
        var t = Skin2TouchTracker<Int>(tester: try pad())
        t.began(1, x: 100, y: 200)
        var s = t.snapshot()
        #expect(s.surfacePoints["touch"] == Skin2SurfacePoint(x: 0.25, y: 0.5))
        t.moved(1, x: 800, y: -50)
        s = t.snapshot()
        #expect(s.surfacePoints["touch"] == Skin2SurfacePoint(x: 1, y: 0))
        // A second finger on a button still presses it.
        t.began(2, x: 330, y: 330)
        #expect(t.snapshot().states["a"]?.pressed == true)
    }

    @Test("An action holds only while the finger stays inside it; leaving locks it out")
    func actionLockout() throws {
        var t = Skin2TouchTracker<Int>(tester: try pad())
        t.began(1, x: 200, y: 40)
        #expect(t.snapshot().states["menu"]?.pressed == true)
        t.moved(1, x: 200, y: 200)
        #expect(t.snapshot().states["menu"] == nil)
        t.moved(1, x: 200, y: 40)
        #expect(t.snapshot().states["menu"] == nil)
    }

    @Test("A free finger can't slide onto an action or a stick")
    func slideRestrictions() throws {
        var t = Skin2TouchTracker<Int>(tester: try pad())
        t.began(1, x: 330, y: 330)
        t.moved(1, x: 200, y: 40)
        #expect(t.snapshot() == .empty)
        t.moved(1, x: 60, y: 190)
        #expect(t.snapshot() == .empty)
    }

    @Test("A relayout that drops a latched control makes its touch inert")
    func relayout() throws {
        var t = Skin2TouchTracker<Int>(tester: try pad())
        t.began(1, x: 70, y: 330)
        #expect(t.snapshot().states["dpad"] != nil)
        let doc = try renderSkin(##"{ "type": "control", "id": "a", "kind": "button", "input": "a", "layout": { "frame": [0, 0, 50, 50] } }"##)
        t.setTester(Skin2HitTester(Skin2Resolver.resolve(doc, in: Skin2Environment(size: Skin2Size(width: 100, height: 100)))))
        #expect(t.snapshot() == .empty)
    }
}

private final class RecordingSink: Skin2InputSink {
    var log: [String] = []
    func press(_ input: String) { log.append("+\(input)") }
    func release(_ input: String) { log.append("-\(input)") }
    func stick(_ input: String, x: Double, y: Double) { log.append("stick \(input) \(x) \(y)") }
    func surface(_ input: String, point: Skin2SurfacePoint?) {
        log.append(point.map { "surface \(input) \($0.x) \($0.y)" } ?? "surface \(input) up")
    }
    func action(_ name: String) { log.append("action \(name)") }
}

/// Runs `steps` through a tracker and bridge, returning the sink's log.
private func drive(_ steps: [(Int, Character, Double, Double)]) throws -> [String] {
    let tester = try pad()
    var tracker = Skin2TouchTracker<Int>(tester: tester)
    var bridge = Skin2InputBridge()
    let sink = RecordingSink()
    var old = Skin2TouchSnapshot.empty
    for (key, phase, x, y) in steps {
        switch phase {
        case "b": tracker.began(key, x: x, y: y)
        case "m": tracker.moved(key, x: x, y: y)
        default: tracker.ended(key)
        }
        let new = tracker.snapshot()
        for e in skin2InputEvents(from: old, to: new, tester: tester) { bridge.handle(e, sink: sink) }
        old = new
    }
    return sink.log
}

@Suite("Input bridge")
struct InputBridgeTests {
    @Test("A d-pad rolling up, up + right, right releases only what it left")
    func dpadRoll() throws {
        let log = try drive([(1, "b", 70, 330), (1, "m", 70, 285), (1, "m", 118, 285), (1, "m", 118, 330), (1, "e", 0, 0)])
        #expect(log == ["+up", "+right", "-up", "-right"])
    }

    @Test("Buttons press and release; a drag across hands over")
    func buttons() throws {
        let log = try drive([(1, "b", 330, 330), (1, "m", 260, 330), (1, "e", 0, 0)])
        #expect(log == ["+a", "-a", "+b", "-b"])
    }

    @Test("Sticks send values, then a zero on release")
    func sticks() throws {
        let log = try drive([(1, "b", 60, 190), (1, "m", 70, 190), (1, "e", 0, 0)])
        #expect(log == ["stick leftThumbstick 0.0 0.0", "stick leftThumbstick 0.5 0.0", "stick leftThumbstick 0.0 0.0"])
    }

    @Test("An action fires once on touch-down and sends nothing on release")
    func action() throws {
        let log = try drive([(1, "b", 200, 40), (1, "m", 205, 42), (1, "e", 0, 0)])
        #expect(log == ["action menu"])
    }

    @Test("A touch surface sends points while held and lifts at the end")
    func surface() throws {
        let log = try drive([(1, "b", 100, 200), (1, "m", 200, 200), (1, "e", 0, 0)])
        #expect(log == ["surface touchScreen 0.25 0.5", "surface touchScreen 0.5 0.5", "surface touchScreen up"])
    }

    @Test("releaseAll lets go of held inputs and a held stick")
    func releaseAll() throws {
        let tester = try pad()
        var tracker = Skin2TouchTracker<Int>(tester: tester)
        var bridge = Skin2InputBridge()
        let sink = RecordingSink()
        tracker.began(1, x: 330, y: 330)
        tracker.began(2, x: 70, y: 190)
        tracker.moved(2, x: 80, y: 190)
        for e in skin2InputEvents(from: .empty, to: tracker.snapshot(), tester: tester) { bridge.handle(e, sink: sink) }
        sink.log.removeAll()
        bridge.releaseAll(sink: sink)
        #expect(sink.log.sorted() == ["-a", "stick leftThumbstick 0.0 0.0"])
    }
}

@Suite("Input bridge: shared inputs and removed controls")
struct InputBridgeSharingTests {
    /// An `a` button and an `a` + `b` combo side by side.
    private func comboPad() throws -> Skin2HitTester {
        let doc = try renderSkin(##"""
        { "type": "control", "id": "a", "kind": "button", "input": "a", "layout": { "frame": [0, 0, 50, 50] } },
        { "type": "control", "id": "ab", "kind": "button", "inputs": ["a", "b"], "layout": { "frame": [50, 0, 50, 50] } }
        """##)
        return Skin2HitTester(Skin2Resolver.resolve(doc, in: Skin2Environment(size: Skin2Size(width: 100, height: 100))))
    }

    @Test("An input two held controls share is released only when the last one lets go")
    func sharedInput() throws {
        let tester = try comboPad()
        var tracker = Skin2TouchTracker<Int>(tester: tester)
        var bridge = Skin2InputBridge()
        let sink = RecordingSink()
        var old = Skin2TouchSnapshot.empty
        func step(_ change: (inout Skin2TouchTracker<Int>) -> Void) {
            change(&tracker)
            let new = tracker.snapshot()
            for e in skin2InputEvents(from: old, to: new, tester: tester) { bridge.handle(e, sink: sink) }
            old = new
        }
        step { $0.began(1, x: 25, y: 25) }   // a
        step { $0.began(2, x: 75, y: 25) }   // a + b: only b is new
        step { $0.ended(1) }                 // the combo still holds a
        #expect(sink.log == ["+a", "+b"])
        step { $0.ended(2) }
        #expect(sink.log == ["+a", "+b", "-a", "-b"])
    }

    @Test("releaseAll releases a shared input once")
    func sharedReleaseAll() throws {
        let tester = try comboPad()
        var tracker = Skin2TouchTracker<Int>(tester: tester)
        var bridge = Skin2InputBridge()
        let sink = RecordingSink()
        tracker.began(1, x: 25, y: 25)
        tracker.began(2, x: 75, y: 25)
        for e in skin2InputEvents(from: .empty, to: tracker.snapshot(), tester: tester) { bridge.handle(e, sink: sink) }
        sink.log.removeAll()
        bridge.releaseAll(sink: sink)
        #expect(sink.log == ["-a", "-b"])
    }

    @Test("A snapshot knows when a held control is gone from a new layout")
    func heldControlRemoved() throws {
        let tester = try comboPad()
        var tracker = Skin2TouchTracker<Int>(tester: tester)
        tracker.began(1, x: 75, y: 25)
        let held = tracker.snapshot()
        let onlyA = Skin2HitTester(Skin2Resolver.resolve(
            try renderSkin(##"{ "type": "control", "id": "a", "kind": "button", "input": "a", "layout": { "frame": [0, 0, 50, 50] } }"##),
            in: Skin2Environment(size: Skin2Size(width: 100, height: 100))))
        #expect(held.holdsControls(missingFrom: onlyA))
        #expect(!held.holdsControls(missingFrom: tester))
        #expect(!Skin2TouchSnapshot.empty.holdsControls(missingFrom: onlyA))
    }
}

@Suite("Haptics")
struct HapticTests {
    @Test("A press plays the control's haptic, the default otherwise; holding and releasing are silent")
    func presses() throws {
        let tester = try pad()
        var t = Skin2TouchTracker<Int>(tester: tester)
        t.began(1, x: 330, y: 330)
        let down = t.snapshot()
        #expect(Skin2Haptics.requests(from: .empty, to: down, tester: tester) == [Skin2HapticRequest(controlID: "a", style: "heavy", intensity: 0.5)])
        t.moved(1, x: 331, y: 331)
        #expect(Skin2Haptics.requests(from: down, to: t.snapshot(), tester: tester).isEmpty)
        t.ended(1)
        #expect(Skin2Haptics.requests(from: down, to: t.snapshot(), tester: tester).isEmpty)
        t.began(2, x: 260, y: 330)
        let b = Skin2Haptics.requests(from: .empty, to: t.snapshot(), tester: tester)
        #expect(b == [Skin2HapticRequest(controlID: "b", style: "medium", intensity: 1)])
    }

    @Test("A d-pad buzzes for each direction it gains, and a touch surface is silent")
    func dpadAndSurface() throws {
        let tester = try pad()
        var t = Skin2TouchTracker<Int>(tester: tester)
        t.began(1, x: 70, y: 285)
        let up = t.snapshot()
        #expect(Skin2Haptics.requests(from: .empty, to: up, tester: tester).map(\.controlID) == ["dpad"])
        t.moved(1, x: 118, y: 285)
        #expect(Skin2Haptics.requests(from: up, to: t.snapshot(), tester: tester).map(\.controlID) == ["dpad"])
        var s = Skin2TouchTracker<Int>(tester: tester)
        s.began(1, x: 100, y: 200)
        #expect(Skin2Haptics.requests(from: .empty, to: s.snapshot(), tester: tester).isEmpty)
    }
}

@Suite("Scale easing")
struct ScaleEasingTests {
    @Test("Pressed scale eases in over 80 ms and out again")
    func inAndOut() {
        var e = Skin2ScaleEasing()
        e.update(pressed: ["a"], at: 10)
        #expect(e.progress("a", at: 10) == 0)
        let mid = e.progress("a", at: 10.04) ?? -1
        #expect(mid > 0.5 && mid < 1)   // ease-out: past halfway at half the time
        #expect(e.progress("a", at: 10.08) == 1)
        #expect(e.progress("a", at: 11) == 1)
        #expect(e.isAnimating(at: 10.04))
        #expect(!e.isAnimating(at: 10.08))

        e.update(pressed: [], at: 12)
        #expect(e.progress("a", at: 12) == 1)
        #expect((e.progress("a", at: 12.04) ?? -1) < 0.5)
        #expect(e.progress("a", at: 12.1) == 0)
    }

    @Test("Pressing again mid-release turns around from where it is")
    func retarget() {
        var e = Skin2ScaleEasing()
        e.update(pressed: ["a"], at: 0)
        e.update(pressed: [], at: 1)
        let at = e.progress("a", at: 1.04) ?? -1
        e.update(pressed: ["a"], at: 1.04)
        #expect(abs((e.progress("a", at: 1.04) ?? -2) - at) < 1e-9)
        #expect(e.progress("a", at: 1.2) == 1)
    }

    @Test("apply() sets scaleProgress on held controls and keeps released ones drawn as easing out")
    func apply() {
        var e = Skin2ScaleEasing()
        e.update(pressed: ["a"], at: 0)
        let held = e.apply(to: ["a": Skin2ControlState(pressed: true)], at: 0.04)
        #expect(held["a"]?.pressed == true && (held["a"]?.scaleProgress ?? 0) < 1)
        e.update(pressed: [], at: 1)
        let out = e.apply(to: [:], at: 1.04)
        #expect(out["a"]?.easingOut == true && (out["a"]?.scaleProgress ?? 0) > 0)
        #expect(e.apply(to: [:], at: 1.2)["a"] == nil)
    }

    @Test("prune drops finished releases but keeps held controls")
    func prune() {
        var e = Skin2ScaleEasing()
        e.update(pressed: ["a", "b"], at: 0)
        e.update(pressed: ["a"], at: 1)
        e.prune(at: 2)
        #expect(e.progress("b", at: 2) == nil)
        #expect(e.progress("a", at: 2) == 1)
    }
}

@Suite("Format 2.0 detection")
struct DetectionTests {
    @Test("A supported format2 entry renders skin.json")
    func supported() {
        let info = Skin2SourceInfo(infoJSON: ["format2": ["source": "skin.json", "formatVersion": "2.0", "requires": ["layout.stack", "shapes.path"]]])
        #expect(info?.isRenderable == true)
        #expect(Skin2SourceInfo(infoJSON: ["format2": [String: Any]()])?.source == "skin.json")
    }

    @Test("Any 2.x is accepted; 1.x and 3.0 are not")
    func versions() {
        #expect(Skin2SourceInfo(source: "skin.json", formatVersion: "2.3", requires: []).isRenderable)
        #expect(!Skin2SourceInfo(source: "skin.json", formatVersion: "3.0", requires: []).isRenderable)
        #expect(!Skin2SourceInfo(source: "skin.json", formatVersion: "1.0", requires: []).isRenderable)
        #expect(!Skin2SourceInfo(source: "skin.json", formatVersion: "2.", requires: []).isRenderable)
    }

    @Test("An unsupported or unknown requires entry falls back to classic")
    func unsupported() {
        #expect(!Skin2SourceInfo(source: "skin.json", formatVersion: "2.0", requires: ["layout.stack", "effects.ci"]).isRenderable)
        #expect(!Skin2SourceInfo(source: "skin.json", formatVersion: "2.0", requires: ["quantum.foam"]).isRenderable)
    }

    @Test("No format2 key, or a source escaping the bundle, is classic")
    func classic() {
        #expect(Skin2SourceInfo(infoJSON: ["name": "x"]) == nil)
        #expect(!Skin2SourceInfo(source: "../skin.json", formatVersion: "2.0", requires: []).isRenderable)
        #expect(!Skin2SourceInfo(source: "/etc/skin.json", formatVersion: "2.0", requires: []).isRenderable)
    }
}

@Suite("GameCube hit frames")
struct GameCubeHitFrameTests {
    static let portrait = Skin2Environment(size: Skin2Size(width: 393, height: 852), safeArea: Skin2Insets(top: 59, bottom: 34))
    static let landscape = Skin2Environment(size: Skin2Size(width: 852, height: 393), safeArea: Skin2Insets(left: 59, bottom: 21, right: 59))
    static let ipadLandscape = Skin2Environment(size: Skin2Size(width: 1180, height: 820), safeArea: Skin2Insets(top: 24, bottom: 20), device: .ipad)
    static let noInsets = Skin2Environment(size: Skin2Size(width: 414, height: 736), displayType: .standard)

    /// The spike's own assertions (PR #56, `Skin2SpikeTests`) are the contract: every control at least 44 pt on its
    /// short side, no two hit frames overlapping, in portrait, landscape and iPad landscape. It asserted no numeric
    /// hit frames, so these tests pin the rules (hit frame = frame + `hit.extend`) and the iCube geometry the spike
    /// matched, not literal rectangles.
    @Test("Controls are at least 44 pt, hit frames never overlap, and each sits on its frame",
          arguments: [portrait, landscape, ipadLandscape, noInsets])
    func spikeRules(env: Skin2Environment) throws {
        let doc = try Skin2Document.load(data: RenderPaths.skinData("gamecube-icube"))
        let r = Skin2Resolver.resolve(doc, in: env)
        let controls = r.controls
        #expect(controls.count == 11)
        for c in controls {
            let hit = try #require(c.hitFrame)
            #expect(min(c.frame.width, c.frame.height) >= 44, "\(c.id ?? "?") under 44 pt")
            #expect(hit.contains(c.frame), "\(c.id ?? "?") hit frame inside its frame")
        }
        for (i, a) in controls.enumerated() {
            for b in controls[(i + 1)...] {
                #expect(!a.hitFrame!.overlaps(b.hitFrame!), "\(a.id ?? "?") overlaps \(b.id ?? "?")")
            }
        }
    }

    @Test("Portrait hit frames are the resolved frames outset by hit.extend, and the tester finds each control")
    func portraitHitFrames() throws {
        let doc = try Skin2Document.load(data: RenderPaths.skinData("gamecube-icube"))
        let r = Skin2Resolver.resolve(doc, in: Self.portrait)
        let tester = Skin2HitTester(r)
        #expect(tester.controls.count == 11)
        for c in r.controls {
            let id = try #require(c.id)
            let extend = c.node.hit?.extend
            let hit = try #require(c.hitFrame)
            let expected = c.frame.outset(extend?.resolve(width: c.frame.width, height: c.frame.height, unit: r.unit,
                                                          safeArea: Self.portrait.safeArea) ?? .zero)
            #expect(abs(hit.x - expected.x) <= 0.5 && abs(hit.y - expected.y) <= 0.5
                    && abs(hit.width - expected.width) <= 1 && abs(hit.height - expected.height) <= 1,
                    "\(id): \(hit) vs \(expected)")
            #expect(tester.control(id: id)?.hitFrame == hit)
        }
    }
}

@Suite("Trigger pressure")
struct TriggerPressureTests {
    private func tester() throws -> Skin2HitTester {
        let doc = try renderSkin("""
        { "type": "control", "id": "l", "kind": "trigger", "input": "l",
          "layout": { "frame": [0, 0, 80, 40] } }
        """, requires: "[]")
        return Skin2HitTester(Skin2Resolver.resolve(doc, in: Skin2Environment(size: Skin2Size(width: 400, height: 400))))
    }

    @Test("Pressure-only changes emit events, and lifting releases the trigger")
    func pressureChanges() throws {
        let tester = try tester()
        var tracker = Skin2TouchTracker<Int>(tester: tester)
        tracker.began(1, x: 20, y: 20, pressure: 0.25)
        let first = tracker.snapshot()
        #expect(first.states["l"]?.pressure == 0.25)
        tracker.moved(1, x: 20, y: 20, pressure: 0.75)
        let next = tracker.snapshot()
        let events = skin2InputEvents(from: first, to: next, tester: tester)
        #expect(events.count == 1)
        #expect(events.first?.state.pressure == 0.75)
        tracker.ended(1)
        #expect(tracker.snapshot() == .empty)
        #expect(skin2InputEvents(from: next, to: .empty, tester: tester).first?.state.isPressed == false)
    }

    @Test("Missing force and ambiguous multiple touches use a full press")
    func fallback() throws {
        var tracker = Skin2TouchTracker<Int>(tester: try tester())
        tracker.began(1, x: 20, y: 20)
        #expect(tracker.snapshot().states["l"]?.pressure == 1)
        tracker.moved(1, x: 20, y: 20, pressure: 0.2)
        tracker.began(2, x: 30, y: 20, pressure: 0.4)
        #expect(tracker.snapshot().states["l"]?.pressure == 1)
        tracker.ended(2)
        #expect(tracker.snapshot().states["l"]?.pressure == 0.2)
        tracker.moved(1, x: 200, y: 20, pressure: 0.2)
        #expect(tracker.snapshot() == .empty)
    }
}
