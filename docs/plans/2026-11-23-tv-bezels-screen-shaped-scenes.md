# TV Bezels: Screen-Shaped Scenes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Built-in TVs are drawn on a canvas with the screen's own proportions, so they fill any landscape screen from 4:3 to 2.4:1 with no bars and no cropped cabinet, and the Seat setting changes how much room is drawn.

**Architecture:** A pure canvas rule in SkinKitBezels turns a display size and a seat into a canvas. `TVBezelArtwork` resolves a TV's document on that canvas and `TVBezelScene` carries it; the shader's `fr_zoom` is computed from the canvas width. The three bundled documents are rewritten with anchors. Provenance then asks the rule for the canvas instead of assuming 1920x1080.

**Tech Stack:** Swift 6 / SwiftPM (SkinKit repo, Swift Testing), format 2 skin JSON, Provenance PVUIBase (UIKit + Metal).

**Spec:** `docs/specs/2026-11-23-tv-bezels-screen-shaped-scenes-design.md`

## Global Constraints

- Work in the SkinKit worktree `/Users/jmattiello/Workspace/Provenance/SkinKit/_worktrees/bezel-screen-shaped`, branch `bezels/screen-shaped-scenes`. Tasks 1 to 4 touch only this repo.
- Package test command: `xcrun swift test --filter SkinKitBezelsTests` (plain `swift` on PATH is too old).
- Supported screen ratio: 4:3 ... 2.4 (width / height). Seat canvas heights: Back 1080, Middle 980, Front 900 points. Canvas width is not rounded.
- Back at 16:9 must reproduce today's tubes exactly: Living Room 960x720 at (480,180); Studio Monitor and Computer Monitor 1008x756 at (456,162).
- The tube is centred and has the same size at every shape for a given seat. No off-centre tubes.
- Public API stays source compatible: new parameters have defaults equal to today's behaviour, because iFly and iCube build against this package.
- No schema change. Use only existing format 2 features: `anchor`, `size`, `inset`, `%` / `min` / `max` / `sum` lengths, `repeat` (count at most 64), conditional `visible` with `minWidth`. An override can hide or show a node and change its layout; it cannot add one.
- Standalone presets (`TVBezel.presetID != nil`) and image bezels are untouched.
- No Bezel Project artwork in fixtures. Email in anything public: `git@joemattiello.com`.
- Do not push, open PRs, tag or merge without the owner's say-so. Never reset, rebase or stash in a shared checkout; commit own files by path.
- Provenance (Task 5) is a shared `develop` checkout used by other agents; PVUI cannot build in a git worktree.

## Review Focus

- A window narrower than 4:3 (Stage Manager) or a 32:9 display: the canvas is clamped and the app must still keep the tube on screen through the existing cover framing, not stretch the scene.
- A canvas whose width is not a whole number (for example 1080 x 19.5 / 9): artwork PNG and tube texture sizes must stay consistent with the drawable to within a pixel, so the picture sits inside the glass.
- A stored seat of `wholeRoom` from the stopgap build: it must read as Back, not crash or reset other settings.
- Room light (`uborder-koko-ambi`) on a non-16:9 canvas: tube position must match the plain preset's; if it does not, non-16:9 canvases use the plain preset.
- Rotating or resizing while a TV shows: the scene is rebuilt for the new canvas and the old tube rect is never used with the new scene.

---

### Task 1: Canvas rule and seat

**Files:**
- Create: `Sources/SkinKitBezels/Rules/TVBezelCanvas.swift`
- Test: `Tests/SkinKitBezelsTests/TVBezelCanvasTests.swift`

**Interfaces:**
- Produces:
  - `public enum TVBezelSeat: String, CaseIterable, Sendable { case back, middle, front; public var canvasHeight: CGFloat }` (1080, 980, 900)
  - `public enum TVBezelCanvas { public static let ratioRange: ClosedRange<CGFloat>` (`4.0 / 3.0 ... 2.4`)`; public static func size(display: CGSize, seat: TVBezelSeat = .back) -> CGSize; public static func fitsDisplay(_ display: CGSize) -> Bool }`
  - `size` returns `TVBezelArtwork.canvas` for an empty display. `fitsDisplay` is true when the display's ratio is inside `ratioRange` (within 0.001).

- [ ] **Step 1: Write the failing tests**

```swift
@Suite("TVBezelCanvas")
struct TVBezelCanvasTests {
    @Test("16:9 from the back is today's canvas")
    func sixteenNine() { #expect(TVBezelCanvas.size(display: CGSize(width: 3840, height: 2160)) == CGSize(width: 1920, height: 1080)) }

    @Test("The canvas has the display's proportions", arguments: [CGSize(width: 2360, height: 1640), CGSize(width: 2622, height: 1206), CGSize(width: 3440, height: 1440)])
    func proportions(display: CGSize) {
        let canvas = TVBezelCanvas.size(display: display)
        #expect(canvas.height == 1080)
        #expect(abs(canvas.width / canvas.height - display.width / display.height) < 0.0001)
        #expect(TVBezelCanvas.fitsDisplay(display))
    }

    @Test("Seats set the canvas height")
    func seats() {
        let display = CGSize(width: 1600, height: 1200)
        #expect(TVBezelCanvas.size(display: display, seat: .middle) == CGSize(width: 980.0 * 4 / 3, height: 980))
        #expect(TVBezelCanvas.size(display: display, seat: .front) == CGSize(width: 1200, height: 900))
    }

    @Test("Shapes outside 4:3 to 2.4:1 get the nearest supported canvas")
    func clamped() {
        #expect(TVBezelCanvas.size(display: CGSize(width: 1000, height: 1000)) == CGSize(width: 1440, height: 1080))
        #expect(TVBezelCanvas.size(display: CGSize(width: 5120, height: 1440)) == CGSize(width: 2592, height: 1080))
        #expect(!TVBezelCanvas.fitsDisplay(CGSize(width: 1000, height: 1000)))
        #expect(!TVBezelCanvas.fitsDisplay(CGSize(width: 5120, height: 1440)))
    }

    @Test("An empty display gets the default canvas")
    func empty() { #expect(TVBezelCanvas.size(display: .zero) == TVBezelArtwork.canvas) }
}
```

- [ ] **Step 2: Run** `xcrun swift test --filter TVBezelCanvasTests`. Expected: FAIL, "cannot find 'TVBezelCanvas' in scope".
- [ ] **Step 3: Implement** the two types in `TVBezelCanvas.swift`.
- [ ] **Step 4: Run** the same command. Expected: PASS.
- [ ] **Step 5: Commit** `feat(bezels): canvas rule for a display's shape and a seat`.

### Task 2: Artwork, scene and shader take a canvas

**Files:**
- Modify: `Sources/SkinKitBezels/Catalog/TVBezelArtwork.swift`, `Sources/SkinKitBezels/Catalog/TVBezelScene.swift`, `Sources/SkinKitBezels/Rules/TVBezelShader.swift`
- Test: `Tests/SkinKitBezelsTests/TVBezelShaderTests.swift`, `Tests/SkinKitBezelsTests/BezelPackageTests.swift`, `Tests/SkinKitBezelsTests/TVBezelCatalogTests.swift`

**Interfaces:**
- Consumes: `TVBezelCanvas` (Task 1).
- Produces:
  - `TVBezelArtwork.init(data: Data, canvas: CGSize = TVBezelArtwork.canvas) throws`, `init(bezel: TVBezel, canvas: CGSize = TVBezelArtwork.canvas) throws`, `public let canvas: CGSize` (instance; the static `canvas` stays, so name the instance property `canvasSize`), `public var tubeHeightOverCanvasWidth: CGFloat`. `image(pixelWidth:)` scales by `pixelWidth / canvasSize.width`. `tubeHeightFraction` stays (height over canvas height).
  - `TVBezelScene.canvas: CGSize` (default `TVBezelArtwork.canvas` in `init`), `TVBezelScene.key(bezel:lightsRoom:flatGlass:scenePixelWidth:canvas:)` and `make(bezel:lightsRoom:flatGlass:scenePixelWidth:key:canvas:hasPreset:)`, both with `canvas` defaulted. The key appends `|<Int(canvas.width)>x<Int(canvas.height)>` only when the canvas is not the default, so existing keys do not change. A standalone preset ignores `canvas`.
  - `TVBezelShader.geometryValues(tubeAspect: CGFloat, tubeHeightOverSceneWidth: CGFloat) -> [String: Float]` with `fr_zoom = tubeHeightOverSceneWidth * 100`; the existing `geometryValues(tubeAspect:tubeHeightFraction:)` calls it with `tubeHeightFraction * 9 / 16`. `values(frame:tubeAspect:tubeHeightOverSceneWidth:lightsRoom:)` likewise; `make` uses the new one.

- [ ] **Step 1: Write the failing tests**

```swift
// TVBezelShaderTests
@Test("fr_zoom is the tube's height as a percentage of the scene's width, at any scene shape")
func zoomFromSceneWidth() {
    #expect(TVBezelShader.geometryValues(tubeAspect: 4.0 / 3.0, tubeHeightOverSceneWidth: 756.0 / 1440)["fr_zoom"] == 52.5)
    #expect(TVBezelShader.geometryValues(tubeAspect: 4.0 / 3.0, tubeHeightFraction: 0.7)["fr_zoom"]
            == TVBezelShader.geometryValues(tubeAspect: 4.0 / 3.0, tubeHeightOverSceneWidth: 0.7 * 9 / 16)["fr_zoom"])
}

// BezelPackageTests
@Test("A scene made for a canvas carries it, keys on it and sizes its tube from its width")
func sceneForCanvas() throws {
    let bezel = try #require(TVBezelCatalog.bezel(id: "studio-monitor"))
    let canvas = CGSize(width: 1440, height: 1080)
    let key = TVBezelScene.key(bezel: bezel, lightsRoom: false, flatGlass: false, scenePixelWidth: 480, canvas: canvas)
    #expect(key != TVBezelScene.key(bezel: bezel, lightsRoom: false, flatGlass: false, scenePixelWidth: 480))
    let scene = try #require(TVBezelScene.make(bezel: bezel, lightsRoom: false, flatGlass: false, scenePixelWidth: 480,
                                               key: key, canvas: canvas) { _ in true })
    #expect(scene.canvas == canvas)
    #expect(scene.values["fr_zoom"] == Float(scene.tubeRect.height / canvas.width * 100))
}

// TVBezelCatalogTests
@Test("Artwork drawn for a canvas has that canvas's proportions")
func artworkImageProportions() throws {
    let bezel = try #require(TVBezelCatalog.bezel(id: "studio-monitor"))
    let image = try #require(try TVBezelArtwork(bezel: bezel, canvas: CGSize(width: 1440, height: 1080)).image(pixelWidth: 480))
    #expect(image.width == 480 && image.height == 360)
}
```

- [ ] **Step 2: Run** `xcrun swift test --filter SkinKitBezelsTests`. Expected: FAIL to compile on the new parameters.
- [ ] **Step 3: Implement** the interface above. Update the doc comments that say "16:9 scene".
- [ ] **Step 4: Run** the same command. Expected: PASS, including every existing test unchanged.
- [ ] **Step 5: Commit** `feat(bezels): artwork and scenes for any canvas`.

### Task 3: Re-lay out the three documents

**Files:**
- Modify: `Sources/SkinKitBezels/Resources/TVBezels/living-room-tv.skin.json`, `studio-monitor.skin.json`, `computer-monitor.skin.json`
- Test: `Tests/SkinKitBezelsTests/TVBezelCatalogTests.swift`

**Interfaces:**
- Consumes: `TVBezelArtwork(bezel:canvas:)`, `TVBezelCanvas.size(display:seat:)`.
- Produces: documents that resolve at any canvas the rule returns. Node ids `tube` and the cabinet node (`cabinet`, `body`, `case`) keep their ids; the floor band's lowest full-width node gets the id `floor`.

Structure for every document (sizes in points, taken from today's frames):
1. `wall`: fills the canvas (no layout), as today.
2. `room`: a group, `size` 100% width x 1080, anchored centre. Wall details and the floor band live in it. Repeats that march across the width start from x 0 with a count covering 2592 points (seams every 160: count 17). The floor band nodes use `inset` left/right 0 and their current y.
3. `set`: a group inside `room`, `size` 1920 x 1080, anchored centre, holding the cabinet, everything on it, legs or stand, and `tube`, all with today's `frame` values unchanged. This is what makes Back at 16:9 identical to today.
4. Living Room only: `set` content wider than the narrow cabinet (the cloth and weave wings, the wide `cabinet`, `top-trim`, `grain`, outer legs) gets `"visible": { "minWidth": 1700 }`; a narrow cabinet, trim and legs (cabinet frame about [420, 84, 1080, 922]) get the opposite by being drawn under the wide ones and hidden by them, or with their own condition if the format supports a negated one. The builder picks sizes; the tests below are the contract.

- [ ] **Step 1: Write the failing tests**

```swift
static let shapes: [CGSize] = [CGSize(width: 4, height: 3), CGSize(width: 16, height: 9), CGSize(width: 2.4, height: 1)]

@Test("Every built-in TV keeps a centred tube of one size at every shape and stays inside the canvas",
      arguments: TVBezelCatalog.builtIn.filter { $0.presetID == nil })
func tubeAcrossShapes(bezel: TVBezel) throws {
    for seat in TVBezelSeat.allCases {
        var sizes = Set<String>()
        for shape in Self.shapes {
            let canvas = TVBezelCanvas.size(display: shape, seat: seat)
            let tube = try TVBezelArtwork(bezel: bezel, canvas: canvas).tubeRect
            #expect(abs(tube.midX - canvas.width / 2) < 0.5 && abs(tube.midY - canvas.height / 2) < 0.5, "\(bezel.id) \(seat) \(shape)")
            #expect(CGRect(origin: .zero, size: canvas).contains(tube), "\(bezel.id) \(seat) \(shape)")
            sizes.insert("\(Int(tube.width))x\(Int(tube.height))")
        }
        #expect(sizes.count == 1, "\(bezel.id) \(seat): \(sizes)")
    }
}

@Test("From the back at 16:9 the tubes are where they were")
func backSixteenNineUnchanged() throws {
    let expected = ["living-room-tv": CGRect(x: 480, y: 180, width: 960, height: 720),
                    "studio-monitor": CGRect(x: 456, y: 162, width: 1008, height: 756),
                    "computer-monitor": CGRect(x: 456, y: 162, width: 1008, height: 756)]
    for (id, tube) in expected {
        #expect(try TVBezelArtwork(bezel: #require(TVBezelCatalog.bezel(id: id))).tubeRect == tube, "\(id)")
    }
}

@Test("From the back the cabinet fits every shape and stands on the floor",
      arguments: ["living-room-tv": "cabinet", "studio-monitor": "body", "computer-monitor": "case"])
func cabinetFits(id: String, cabinetNode: String) throws {
    // Resolve with Skin2Resolver as TVBezelArtwork does; among visible nodes with this id take the widest.
    // Expect it inside the canvas with at least 20 points of wall each side at 4:3, and the `floor` node
    // spanning the full canvas width at every shape.
}
```

Use whatever accessor the catalogue has for the built-in list (`TVBezelCatalogTests` already iterates it). The third test needs resolved node frames: add an internal `TVBezelArtwork.frame(ofNode id: String) -> CGRect?` (widest visible match) for tests via `@testable import`.

- [ ] **Step 2: Run** `xcrun swift test --filter TVBezelCatalogTests`. Expected: `tubeAcrossShapes` and `cabinetFits` FAIL (tube off centre at 4:3; Living Room cabinet wider than 1440); `backSixteenNineUnchanged` PASS already and must keep passing.
- [ ] **Step 3: Rewrite the three documents** as structured above.
- [ ] **Step 4: Render and look.** For each TV and each of 4:3, 16:9, 2.4:1 at Back, plus 4:3 at Front, write `TVBezelArtwork(bezel:canvas:).pngData(pixelWidth: 1200)` to the session scratchpad from a throwaway test or script and read the images: wall covers the canvas, no detail stops short of an edge, legs meet the floor, the narrow Living Room form looks deliberate. Compare 16:9 Back against a render from `origin/main`: they must match.
- [ ] **Step 5: Run** `xcrun swift test --filter SkinKitBezelsTests` and `xcrun swift test --filter SkinKitBezelsUITests`. Expected: PASS.
- [ ] **Step 6: Commit** `feat(bezels): built-in TVs lay out for the screen's shape`.

### Task 4: Measure the room-light preset off 16:9

**Files:** none in the repo unless the fallback is needed (then `Sources/SkinKitBezels/Catalog/TVBezelScene.swift` and `Tests/SkinKitBezelsTests/BezelPackageTests.swift`).

- [ ] **Step 1: Measure.** With a throwaway SwiftPM executable that depends on Provenance's `PVShaders` (`PVSlangRuntime.FilterChain`, as `PVShaders/Sources/pvshader-validate/main.swift` does), render `bezel/uborder/uborder-koko-ambi` from a built app's `SlangShaders` folder at 1920x1080, 1440x1080 and 2560x1080 with `fr_aspect_x` 10.667, `fr_aspect_y` 8, `fr_zoom` 39.375, centre parameters 0, `h_curvature` 0, plus `TVBezelShader.neutralTubeValues`, and a white source. Measure the bright run through the centre.
  Expected: tube height within 1% of 39.375% of the output width, centred, at all three sizes (the plain preset gives 754, 564 and 1004 pixels).
- [ ] **Step 2: If it holds,** record the three measurements in the spec's "What was measured" table and commit `docs(bezels): room-light preset measured off 16:9`.
- [ ] **Step 3: If it does not,** add the failing test "room light off 16:9 uses the plain preset" (`make(... lightsRoom: true, canvas: 1440x1080)` returns `presetID == TVBezelShader.bezelOnlyID`), make `make` do that when `canvas` is not 16:9, record the measurements, and commit `fix(bezels): plain preset for room light off 16:9`.

### Task 5: Provenance adopts the canvas

**Stop before this task** and ask the owner to push the SkinKit branch and say how it should land (PR, then a revision to pin). Do not push without that.

**Files (Provenance repo, `/Users/jmattiello/Workspace/Provenance/Provenance`, branch `develop`):**
- Modify: `PVUI/Sources/PVUIBase/ExternalDisplay/ProvenanceBezels.swift`, `GameExternalOutputView.swift`, `BezelOptionsView.swift`, `ExternalDisplayOptionsView.swift`, `PVUI/Package.swift`, `PVTouchOverlay/Package.swift`, every `Package.resolved` that pins SkinKit
- Test: `PVUI/Tests/PVUIBaseTests/TVBezelCatalogTests.swift` (compile only in this loop; the owner runs PVUI tests)

**Interfaces:**
- Consumes: `TVBezelSeat`, `TVBezelCanvas.size(display:seat:)`, `TVBezelCanvas.fitsDisplay(_:)`, `TVBezelScene.canvas`, `TVBezelScene.key(...canvas:)`, `TVBezelScene.make(...canvas:)`.
- Produces: no new public API.

- [ ] **Step 1:** Delete PVUIBase's own `TVBezelSeat`. Add `extension TVBezelSeat: @retroactive Defaults.Serializable` with `name` (Back, Middle, Front) and `zoom` (1, 1.1, 1.2, for standalone presets). The Defaults key `externalDisplayBezelSeat` keeps its name; an unknown stored value (`wholeRoom`) must decode as `.back`: store the key as `Key<String>` with a computed `TVBezelSeat(rawValue:) ?? .back` accessor if `Defaults` would otherwise fail the decode.
- [ ] **Step 2:** In `GameExternalOutputView`: `showBezel` reads the seat, computes `canvas = TVBezelCanvas.size(display: drawableSize, seat:)` for a TV without `presetID`, and passes it to `key` and `make`. `sceneRect(drawableSize:)` returns the whole drawable when the shown scene's canvas is not the default or `TVBezelCanvas.fitsDisplay(drawableSize)`; otherwise the existing `RenderGeometry.sceneRect` with the canvas's aspect and `SceneFraming(coversDisplay: true, zoom:, kept:)`. `tubeTarget` and `bezelPictureFrame` use `scene.canvas` instead of `TVBezelArtwork.canvas`.
- [ ] **Step 3:** Remove the "Whole Room" wording from both option screens' footers.
- [ ] **Step 4:** Bump the SkinKit revision in both `Package.swift` files and each `Package.resolved` by hand.
- [ ] **Step 5: Compile** for iOS and tvOS: `cd PVUI && xcodebuild build-for-testing -scheme PVUI-UnitTests -destination 'platform=iOS Simulator,id=<an iPhone simulator id>' -xcconfig <file with OTHER_CFLAGS and OTHER_CPLUSPLUSFLAGS = $(inherited) -Wno-invalid-specialization> CODE_SIGNING_ALLOWED=NO -skipPackagePluginValidation -skipMacroValidation`, then the same with a tvOS simulator id. Expected: `** TEST BUILD SUCCEEDED **` twice.
- [ ] **Step 6: Look.** Build `Provenance-Dev-UI` for the simulator, set `externalDisplayBezel` to each built-in TV id in the app's preferences plist, run the harness GBA ROM in landscape on an iPad and an iPhone simulator at each seat, with room light on and off, and read the screenshots: no bars, nothing cropped at Back, the picture inside the glass.
- [ ] **Step 7: Commit** by path: `feat(bezels): TV scenes drawn for the screen's shape`. Push only on the owner's word.

## Not in this plan

- iFly and iCube adoption (same shape as Task 5, in their repos, after the SkinKit revision exists).
- Apple TV and real-device checks: the owner's.
