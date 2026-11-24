# Accessory panels, slice 1 (iFly VMU) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A format 2 skin can carry a panel that shows the real Dreamcast VMU screen, iFly ships one such skin and hides its floating VMU only while the skin provides the picture, and the format's documentation site shows the same panel.

**Architecture:** `SkinKit2Core` gains capabilities, accessory screens, panels, the semantic input registry and the `provided` report, all resolved in the existing single layout pass. `SkinKitUI`'s `Skin2SkinView` draws accessory pictures in layers between two canvases and owns shelf state. iFly feeds one `Skin2PictureStore` from the flycast LCD poll it already has. The TypeScript renderer in the `skins` repo is ported against the same recorded fixtures.

**Tech Stack:** Swift 6 (SwiftPM, Swift Testing), SwiftUI and Core Animation, TypeScript compiled in place with `tsc` (Node 22), Python for the docs generator.

**Spec:** `docs/specs/2026-11-21-skin-format-2-accessory-panels-design.md` (this repo). Section numbers below (§1 to §11) are that document's. Read it before any task.

## Global Constraints

- Three repos, one branch each, never the default branch:
  - SkinKit: this worktree, `/Users/jmattiello/Workspace/Provenance/SkinKit/_worktrees/format2-accessory-panels`. Create branch `format2/accessory-panels` from `docs/format2-accessory-panels` before Task 1.
  - skins: `/Users/jmattiello/Workspace/Provenance/skins`. Its checkout sits on another session's branch. Make a worktree: `git -C /Users/jmattiello/Workspace/Provenance/skins worktree add ../_worktrees/skins-accessory-panels -b format2/accessory-panels refs/remotes/origin/main`.
  - iFly: `/Users/jmattiello/Workspace/Provenance/iFly/iFly` (`develop`). Make a worktree and branch `feature/skin-vmu-panel` from `origin/develop`. Read iFly's `CLAUDE.md` build table first; compile checks are `make build-app`, never the plain `iFly` scheme.
- Other agents work in these checkouts. Commit only your own files by path. Never `git reset`, `rebase`, `stash`, force-push, or touch `main` / `develop`.
- Do not push, open a pull request, tag, merge or publish anything. Branches stay local until the owner says otherwise.
- `formatVersion` stays `"2.0"`.
- Use `xcrun swift`, not `swift`. Use `/bin/cp -f` and `/bin/rm -f`.
- The schema file `docs/schema/skin-2.0.schema.json` and the `skins` repo copy are generated. Change `Sources/SkinKit2Core/Skin2Schema.swift` and record with `SKIN2_RECORD=1`; never edit the JSON.
- Reference images and `layout.json` files are recorded by the Swift tests with `SKIN2_RECORD=1` (the run fails on purpose; run again without it). The `skins` repo takes them only through `tests/skin2/vendor-fixtures.mjs`.
- Registries are closed: capability, picture and semantic input names come only from `Skin2Capabilities` and `Skin2SemanticInputs`.
- Limits: 4 accessory screens, 6 panels, no nested panels, panel name at most 64 characters.
- Thresholds, exact: a provided picture needs a frame of at least 48×32 pt; a provided control and a shelf handle need a hit frame of at least 44×44 pt; opacity above 0.05; shelf animation 200 ms.
- Nothing shown as a live VMU may be made up. Sample frames on the site are captioned "sample frame".
- All `std.vmu` and example-skin art is vector shapes drawn for this project. Do not trace the concept image or photographed hardware.
- New Swift must compile for iOS 17, tvOS 17, macOS 14 and visionOS 1; guard UIKit code with `#if canImport(UIKit)` as the neighbouring files do.
- Public material uses `git@joemattiello.com`, never another address.
- Commit messages are conventional (`feat:`, `test:`, `docs:`), under 72 characters, ending with the attribution line the session specifies.

## Review Focus

1. **The app delivers a picture, then stops (VMU unplugged, game quit).** The skin must stop providing `vmu.p1` at once so the floating VMU can return. Test in Task 7 (`providedDropsPictureWhenStoreClears`).
2. **A finger is down on a control inside a shelf when the shelf closes or its capability disappears.** The input must be released, never stuck. Test in Task 7 (`closingShelfReleasesHeldInputs`).
3. **A skin from a newer SkinKit read by an app pinned to an older one.** It must draw the classic bake, not a housing with an empty window. Test in Task 8 (`vmuSkinRequiresStdParts21`).
4. **A shelf handle that the layout pushes outside the safe area on one device.** The validator must reject it; if it happens at run time through player edits, the skin must provide nothing. Tests in Task 3 and Task 5.
5. **The all-zero LCD buffer before the game first draws to the VMU.** iFly must deliver no picture, so the skin shows an empty window and iFly's existing placeholder rule is unchanged. Test in Task 9 (`zeroBufferDeliversNoPicture`).

---

### Task 1: `optional`, capabilities and the `has` condition

**Files:**
- Create: `Sources/SkinKit2Core/Skin2Capabilities.swift`
- Modify: `Sources/SkinKit2Core/Skin2Document.swift` (add `optional`), `Skin2Environment.swift`, `Skin2Layout.swift` (`Skin2Condition`), `Skin2Features.swift`, `Skin2Resolver.swift` (condition matching), `Skin2Validator.swift`, `Skin2Schema.swift`
- Modify: `Sources/SkinKit2Render/SkinKit2Render.swift` (`supportedFeatures`, `supports`)
- Test: `Tests/SkinKit2CoreTests/CapabilityTests.swift` (new), `ValidatorTests.swift`, `SchemaTests.swift`

**Interfaces:**
- Produces:
  - `Skin2Document.optional: [String]` (default `[]`).
  - `Skin2Environment.capabilities: Set<String>`, last `init` parameter, default `[]`.
  - `Skin2Condition.has: [String]?` decoded from a string or an array of strings; `"has"` added to `Skin2Condition.keys`.
  - `public enum Skin2Capabilities { static let pictureSources: [String] /* "vmu.p1"…"vmu.p4" */; static func picture(_ source: String) -> String /* "picture.vmu.p1" */; static func input(_ name: String) -> String /* "input.arcade.coin1" */; static func isKnown(_ capability: String) -> Bool }`.
  - `Skin2Features.all` gains `"capabilities"`, `"screens.accessory"`, `"panels"`, `"inputs.semantic"`, `"parts.std@2.1"`. `Skin2Features.used` inserts `"capabilities"` when any condition has `has`.
  - `SkinKit2Render.supports(_ requires: [String]) -> Bool` is unchanged in meaning; `SkinKit2Render.supportedFeatures` gains the five names by the end of Task 8. Add each name in the task that implements it; add `"capabilities"` here.

- [ ] **Step 1: Write the failing tests** in `CapabilityTests.swift` (Swift Testing, using `Skin2Fixtures.inline` and `skinJSON` from `Skin2TestSupport.swift`):

```swift
@Test func hasConditionFollowsCapabilities() throws {
    let doc = try Skin2Fixtures.inline(skinJSON(children: #"""
      {"type":"shape","id":"lamp","shape":{"kind":"rect"},"layout":{"size":{"width":40,"height":40}},
       "visible":{"has":"picture.vmu.p1"}}
    """#, extra: #""optional":["capabilities"],"#))
    let without = Skin2Resolver(document: doc).resolve(Skin2Environment(size: .init(width: 390, height: 844)))
    let with = Skin2Resolver(document: doc).resolve(Skin2Environment(size: .init(width: 390, height: 844), capabilities: ["picture.vmu.p1"]))
    #expect(without.node(id: "lamp") == nil)
    #expect(with.node(id: "lamp") != nil)
}
@Test func hasAcceptsAList() // {"has":["picture.vmu.p1","picture.vmu.p2"]} needs both
@Test func unknownCapabilityIsAValidationError() // "has":"picture.gameboy" → error at the node's /visible/has
@Test func featureUsedMustBeRequiredOrOptional() // content uses `has`, neither list names "capabilities" → error at /requires
@Test func optionalFeatureDoesNotBlockTheReader() // SkinKit2Render.supports(doc.requires) is true when an unknown name is only in `optional`
@Test func unknownOptionalNameIsAnError() // "optional":["nope"] → error at /optional/0
```

If `skinJSON` already writes `requires`, keep its list and add only `optional`. Match how existing tests construct a resolver and environment; if hidden nodes stay in `Skin2Resolution.nodes` today, assert on whatever "not visible" means there (see `ResolverTests.swift`, the `flag` cases) and use the same assertion in every later task.

- [ ] **Step 2: Run** `xcrun swift test --filter CapabilityTests`. Expected: compile failure (`capabilities`, `has`, `optional` unknown).
- [ ] **Step 3: Implement** the model, registry, condition matching (a condition with `has` passes only when every name is in `environment.capabilities`), the validator rules (names known; every used feature in `requires` or `optional`; `optional` entries are known feature names; a name may not be in both lists) and the schema entries.
- [ ] **Step 4: Record the schema:** `SKIN2_RECORD=1 xcrun swift test --filter SchemaTests` (fails by design), then `xcrun swift test --filter "CapabilityTests|SchemaTests|ValidatorTests|ResolverTests"`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(format2): optional features, capabilities and the has condition`.

### Task 2: Accessory screens in the model, resolver and one-shot renderer

**Files:**
- Modify: `Sources/SkinKit2Core/Skin2Node.swift`, `Skin2Resolver.swift`, `Skin2Validator.swift`, `Skin2Features.swift`, `Skin2Schema.swift`
- Modify: `Sources/SkinKit2Render/Skin2Renderer.swift`, `SkinKit2Render.swift`
- Modify: `Sources/SkinKitUI/Rendering/Skin2/DeltaSkinFormat2.swift` (`viewportFrame` ignores accessory screens)
- Create: `Tests/Format2Fixtures/accessory-screen/skin.json`, `Tests/Format2Fixtures/accessory-screen/pictures/vmu.p1.png` (48×32, a drawn test card: a border, a diagonal and the digits "12"; not a capture)
- Test: `Tests/SkinKit2CoreTests/AccessoryScreenTests.swift` (new), `Tests/SkinKit2RenderTests/RenderTests.swift`, `ReferenceImageTests.swift`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `Skin2Node.source: String?` (nil means `game`), `Skin2Node.sampling: Skin2Sampling?`; `public enum Skin2Sampling: String, Codable, Sendable, CaseIterable { case nearest, linear }`.
  - `Skin2Node.isAccessoryScreen: Bool` (`type == .screen && source != nil && source != "game"`).
  - `Skin2Resolution.accessoryScreens: [Skin2ResolvedNode]`; `Skin2Resolution.screens` keeps returning game screens only.
  - `Skin2RenderOptions.pictures: [String: CGImage]` (default `[:]`), keyed by source name.
  - `public static let nativeAspect: [String: Double]` on `Skin2Capabilities` (`vmu.*` → 1.5).
  - `Skin2Fixtures.pictures(_ fixture: String) -> [String: CGImage]` in `RenderTestSupport.swift`, reading `pictures/<source>.png`.

- [ ] **Step 1: Write the failing tests.**

```swift
@Test func accessoryScreenIsNotTheViewport() // doc with a main screen and a vmu.p1 screen: resolution.screens.count == 1, accessoryScreens.count == 1
@Test func accessoryScreenDefaultsToNativeAspect() // no aspect, width 96 → resolved height 64
@Test func accessoryScreenRejectsRoleAndPlacement() // validator errors at /…/role and /…/placement
@Test func accessoryScreenSourceMustBeRegistered() // "source":"gameboy.lcd" → error
@Test func fiveAccessoryScreensIsAnError() // limit 4
@Test func accessoryScreenAloneDoesNotSatisfyScreenChecks() // a controller skin whose only screen is accessory fails the same check a screenless skin fails today
@Test func oneShotDrawsSuppliedPictureWithNearestSampling() // render fixture with pictures: the pixel at the centre of LCD cell (0,0) equals the PNG's pixel (0,0); with no picture that pixel equals the fill behind the screen
@Test func nodesAfterAccessoryScreenDrawOverIt() // a 50%-opaque red rect listed after the screen changes the LCD's centre pixel
```

- [ ] **Step 2: Run** `xcrun swift test --filter AccessoryScreenTests`. Expected: FAIL to compile.
- [ ] **Step 3: Implement.** In `Skin2Renderer`'s `.screen` case, an accessory screen with a picture in `options.pictures` is drawn with `ctx.interpolationQuality = .none` for `nearest`, `.high` for `linear`; with `screenPlaceholders` and no picture, draw the existing placeholder plus the source name as text. The one-shot drawer already paints in document order, so later nodes cover it. Add `"screens.accessory"` to `Skin2Features.used` (any accessory screen) and to `supportedFeatures`.
- [ ] **Step 4: Record** `SKIN2_RECORD=1 xcrun swift test --filter "ReferenceImageTests|FixtureTests|SchemaTests"` for the new fixture (rest frame, and a `.with-pictures` image using the fixture's pictures; follow how variants add a suffix to recorded names), then run the whole suite: `xcrun swift test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(format2): accessory screens with app-supplied pictures`.

### Task 3: Panels and shelf state

**Files:**
- Create: `Sources/SkinKit2Core/Skin2Panel.swift`
- Modify: `Sources/SkinKit2Core/Skin2Node.swift`, `Skin2Layout.swift` (`Skin2Patch` gains `panel`), `Skin2Resolver.swift`, `Skin2Validator.swift`, `Skin2Features.swift`, `Skin2Schema.swift`
- Modify: `Sources/SkinKit2Render/Skin2HitTesting.swift` (handle marking), `SkinKit2Render.swift`
- Create: `Tests/Format2Fixtures/panels/skin.json`
- Test: `Tests/SkinKit2CoreTests/PanelTests.swift` (new), `ValidatorTests.swift`, `Tests/SkinKit2RenderTests/ControlHostTests.swift`

**Interfaces:**
- Consumes: Tasks 1 and 2.
- Produces:
  - `public struct Skin2Panel: Equatable, Hashable, Sendable, Decodable { var name: String; var label: String?; var needs: [String]; var presentation: Skin2PanelPresentation; var handle: String? /* "#id" */; var open: Bool }`; `public enum Skin2PanelPresentation: String, Codable, Sendable, CaseIterable { case fixed, shelf }`.
  - `Skin2Node.panel: Skin2Panel?` (groups only).
  - `Skin2Panel.openFlag(_ name: String) -> String` returns `"panel.<name>.open"`; `Skin2Panel.flagPrefix = "panel."`; `Skin2Panel.toggleInput = "togglePanel"`.
  - `Skin2Document.panels: [Skin2Panel]` (preorder) and `Skin2Document.initialPanelFlags: Set<String>` (the open flags of shelves whose `open` is true).
  - `Skin2ResolvedPanel { var panel: Skin2Panel; var presentation: Skin2PanelPresentation; var isOpen: Bool; var handleReachable: Bool; var frame: Skin2Rect }` and `Skin2Resolution.panels: [Skin2ResolvedPanel]` (present panels only).
  - `Skin2ResolvedNode.panelName: String?` for every node inside a present panel.
  - `Skin2HitTester.Control.togglesPanel: String?` (the panel name when the control is that panel's handle).

Resolver rules (§3): a panel whose `needs` are not all in `environment.capabilities` is absent with its subtree. A shelf is open when `environment.flags` contains its open flag. In a closed shelf every descendant except the handle is absent. In a fixed panel the handle is absent. The effective presentation is the node's, after `when` patches that carry `panel.presentation`. `handleReachable` is true when the handle is present and its hit frame lies inside `environment.safeRect`.

- [ ] **Step 1: Write the failing tests.**

```swift
@Test func panelWithoutItsNeedsIsAbsent()            // needs picture.vmu.p1; without capability, resolution.panels is empty and no descendant resolves
@Test func closedShelfKeepsOnlyItsHandle()            // flags [] → only "#tab" of the group's descendants is present; resolution.panels[0].isOpen == false
@Test func openShelfShowsEverything()                 // flags ["panel.vmu.open"]
@Test func fixedPanelHidesItsHandle()
@Test func whenPatchCanChangePresentation()           // {"minWidth":700,"panel":{"presentation":"fixed"}} → fixed at 1024 wide, shelf at 390
@Test func initialPanelFlagsFollowOpen()              // "open": true → document.initialPanelFlags == ["panel.vmu.open"]
@Test func handleOutsideSafeAreaIsNotReachable()      // resolve with an edit that moves the tab off the canvas → handleReachable == false
// validator
@Test func shelfNeedsAHandleInsideTheGroup()          // missing, or an id outside the group → error at /…/panel/handle
@Test func handleMustBeAnActionWithTogglePanel()
@Test func handleSmallerThan44IsAnError()             // hit frame 40×40 → error
@Test func handleOverlappingAControlInEitherStateIsAnError()
@Test func handleOutsideSafeAreaOnABakeTraitIsAnError()
@Test func nestedPanelIsAnError()
@Test func duplicatePanelNameIsAnError()
@Test func sevenPanelsIsAnError()
@Test func panelNameOver64CharactersIsAnError()
@Test func appFlagsMayNotUsePanelPrefix()             // Skin2Environment flags are not validated; assert instead that the validator rejects `"flag":"panel.x.open"` naming a panel that does not exist
```

- [ ] **Step 2: Run** `xcrun swift test --filter PanelTests`. Expected: FAIL to compile.
- [ ] **Step 3: Implement.** The validator's layout pass (`Skin2TraitSet.sets(for:)`, around `Skin2Validator.swift:418`) runs each trait set twice when the document has shelves: all shelves open, all closed. Add `"panels"` to features and `supportedFeatures`.
- [ ] **Step 4: Record and run** the `panels` fixture (closed is the rest frame; record a second image with every shelf open, named with an `.open` suffix), then `xcrun swift test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(format2): panels, shelves and their open flags`.

### Task 4: Semantic input registry and routing

**Files:**
- Create: `Sources/SkinKit2Core/Skin2SemanticInputs.swift`
- Modify: `Sources/SkinKit2Core/Skin2Resolver.swift`, `Skin2Validator.swift`, `Skin2Features.swift`, `Skin2Schema.swift`; `Sources/SkinKit2Render/SkinKit2Render.swift`
- Modify: `Sources/SkinKitUI/Rendering/Skin2/DeltaSkinFormat2.swift`
- Create: `Sources/SkinKitUI/Rendering/Skin2/DeltaSkinSemanticInputHandling.swift`
- Test: `Tests/SkinKit2CoreTests/SemanticInputTests.swift` (new), `Tests/SkinKitUITests/` (one new file `Format2SinkTests.swift`)

**Interfaces:**
- Produces:
  - `public enum Skin2SemanticInputs { public enum Kind: Sendable { case momentary, twoPosition }; public struct Entry: Sendable { let name: String; let kind: Kind; let label: String }; static let all: [Entry]; static func entry(_ name: String) -> Entry?; static func isSemantic(_ input: String) -> Bool /* contains "." */ }`, with exactly the rows of §4.
  - `public protocol DeltaSkinSemanticInputHandling: AnyObject { func semanticInput(_ name: String, pressed: Bool) }`.
  - `DeltaSkinFormat2Sink.press` / `release`: a dotted name goes to `(handler as? DeltaSkinSemanticInputHandling)?.semanticInput(_:pressed:)` and never to `buttonPressed`.
- Rules: a control with a semantic input is present only while `environment.capabilities` contains `Skin2Capabilities.input(name)`. Dotted names not in the registry are a validator error. A `twoPosition` name on any control is a validator error in this slice ("switches are not built yet").

- [ ] **Step 1: Write the failing tests.**

```swift
@Test func semanticControlNeedsItsCapability()   // arcade.coin1 absent without input.arcade.coin1, present with it
@Test func unknownDottedInputIsAnError()         // "arcade.jukebox"
@Test func twoPositionInputIsRejectedForNow()    // "console.tvType"
@Test func registryHasTheSpecRows()              // names == the 17 names of §4, in order
@Test func sinkRoutesDottedNamesToTheSemanticHandler() // a spy handler: buttonPressed never sees "arcade.coin1"; semanticInput sees (name, true) then (name, false)
@Test func sinkDropsDottedNamesWhenHandlerLacksTheProtocol()
```

- [ ] **Step 2: Run** the two test files. Expected: FAIL to compile.
- [ ] **Step 3: Implement.** Add `"inputs.semantic"` to features and `supportedFeatures`.
- [ ] **Step 4: Run** `xcrun swift test`; SkinKitUI tests need Xcode: `xcodebuild test -scheme SkinKit-Package -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SkinKitUITests -skipPackagePluginValidation` (use the scheme `scripts/ci-test.sh` uses if it differs). Expected: PASS.
- [ ] **Step 5: Commit** `feat(format2): semantic input registry and routing`.

### Task 5: The `provided` report

**Files:**
- Create: `Sources/SkinKit2Core/Skin2Provided.swift`
- Modify: `Sources/SkinKit2Core/Skin2Node.swift` (`duplicate`), `Skin2Resolver.swift`, `Skin2Validator.swift`, `Skin2Schema.swift`
- Test: `Tests/SkinKit2CoreTests/ProvidedTests.swift` (new)

**Interfaces:**
- Consumes: Tasks 2 to 4.
- Produces:

```swift
public struct Skin2Provided: Equatable, Sendable {
    public var pictures: Set<String>   // "vmu.p1"
    public var inputs: Set<String>     // "arcade.coin1"
    public var panels: [String: Bool]  // name → open
    public static let none = Skin2Provided(pictures: [], inputs: [], panels: [:])
    public func keeping(pictures delivered: Set<String>) -> Skin2Provided   // intersects `pictures`
}
extension Skin2Resolution { public var provided: Skin2Provided { get } }
```

  - `Skin2Node.duplicate: Bool` (default false), valid only on `screen` and `control` nodes.
  - Constants on `Skin2Provided`: `minimumPicture = Skin2Size(width: 48, height: 32)`, `minimumControl = Skin2Size(width: 44, height: 44)`, `minimumOpacity = 0.05`.
- Rules: exactly §5. A closed shelf's descendants are absent from the resolution, so compute a closed shelf's contribution by resolving that panel as open in a second pass (same environment plus its open flag) and counting only nodes whose `panelName` is that panel, and only when the closed resolution's `handleReachable` is true. Only semantic inputs appear in `inputs`.

- [ ] **Step 1: Write the failing tests**, one per rule:

```swift
@Test func fixedPanelProvidesItsPicture()
@Test func openShelfProvidesItsPicture()
@Test func closedShelfWithReachableHandleStillProvides()   // the owner's decision of 2026-11-21
@Test func closedShelfWithUnreachableHandleProvidesNothing()
@Test func pictureSmallerThan48x32IsNotProvided()          // 40×27
@Test func pictureOutsideTheCanvasIsNotProvided()
@Test func nearlyTransparentPictureIsNotProvided()         // opacity 0.04
@Test func controlSmallerThan44IsNotProvided()
@Test func duplicateNodeDoesNotClaim()                      // one screen marked duplicate → pictures is empty; two screens, one marked → provided
@Test func duplicateOnAGroupIsAValidationError()
@Test func panelsReportTheirOpenState()                     // ["vmu": false]
@Test func missingCapabilityProvidesNothing()
@Test func classicButtonNamesAreNeverInInputs()             // a control with input "a"
@Test func keepingNarrowsToDeliveredPictures()
```

- [ ] **Step 2: Run** `xcrun swift test --filter ProvidedTests`. Expected: FAIL to compile.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `SKIN2_RECORD=1 xcrun swift test --filter SchemaTests`, then `xcrun swift test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(format2): report what a resolved skin provides`.

### Task 6: Bakes leave panels out

**Files:**
- Modify: `Sources/SkinKit2Bake/Skin2Baker.swift` (and `ClassicItem.swift` if items are built there)
- Test: `Tests/SkinKit2BakeTests/` (new file `PanelBakeTests.swift`)

**Interfaces:**
- Consumes: Tasks 2 to 4.
- Produces: the baker resolves with no capabilities and no panel flags, and additionally drops every panel group, accessory screen and semantic control even when they have no `needs`. One warning per skin: `"panels, accessory screens and semantic controls are not baked"`.

- [ ] **Step 1: Write the failing tests:** `bakedSkinHasNoPanelItems` (bake the `panels` fixture; no classic item has input `togglePanel` or a dotted name; item count equals the controller's controls), `bakedArtDoesNotDrawThePanel` (the baked image at the panel's frame equals the image baked from the same skin with the panel node removed), `bakedScreensAreGameScreensOnly`, `bakeWarnsOnce`.
- [ ] **Step 2: Run** `xcrun swift test --filter PanelBakeTests`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `xcrun swift test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(format2): leave panels and accessory screens out of bakes`.

### Task 7: The view: picture layers, shelf state, ownership callback

**Files:**
- Create: `Sources/SkinKit2Render/Skin2PictureStore.swift`
- Create: `Sources/SkinKitUI/Rendering/Skin2/Skin2PictureLayers.swift`, `Sources/SkinKitUI/Rendering/Skin2/Skin2PanelState.swift`
- Modify: `Sources/SkinKit2Render/Skin2Renderer.swift` (draw a range of the plan), `Sources/SkinKitUI/Rendering/Skin2/Skin2SkinView.swift`, `DeltaSkinFormat2.swift`, `Sources/SkinKitUI/Views/Skin/DeltaSkinView.swift`
- Test: `Tests/SkinKit2RenderTests/PictureSplitTests.swift` (new), `Tests/SkinKitUITests/Format2PanelViewTests.swift` (new)

**Interfaces:**
- Consumes: Tasks 1 to 5.
- Produces:

```swift
// SkinKit2Render
@MainActor public final class Skin2PictureStore: ObservableObject {
    public init()
    public func set(_ image: CGImage?, for source: String)   // nil removes; publishes only when the image identity changes
    public func image(for source: String) -> CGImage?
    public var delivered: Set<String> { get }                // sources with an image now
}
public enum Skin2DrawPart: Equatable, Sendable { case all; case upTo(screen: String /* node pointer */); case after(screen: String) }
extension Skin2RenderOptions { public var part: Skin2DrawPart }   // default .all
// SkinKitUI
@MainActor final class Skin2PanelState: ObservableObject {
    init(document: Skin2Document, skinIdentifier: String?, defaults: UserDefaults = .standard)
    var flags: Set<String> { get }                 // the panel.<name>.open flags that are on
    func toggle(_ panel: String)
}
```

  - `Skin2SkinView.init` gains, with defaults: `capabilities: Set<String> = []`, `pictures: Skin2PictureStore? = nil`, `skinIdentifier: String? = nil`, `onProvidedChange: ((Skin2Provided) -> Void)? = nil`.
  - `DeltaSkinView.init` gains the same three app-facing parameters (`capabilities`, `pictures`, `onProvidedChange`), default-valued and placed last so existing call sites compile; `DeltaSkinFormat2View` passes them through with `skinIdentifier: skin.identifier`.
  - Persistence key: `"SkinKit.format2.panelOpen.<skinIdentifier>.<panelName>"` in `UserDefaults.standard` (a Bool). With no stored value the document's `open` applies. With a nil identifier nothing is stored.
- Behaviour:
  - The environment the view resolves with is `flags ∪ panelState.flags` and `capabilities`. `LayoutKey` gains both so a change re-resolves.
  - A touch on a control whose `togglesPanel` is set calls `panelState.toggle` on touch-down and produces no `Skin2InputEvent`.
  - Before a toggle changes the layout, and whenever `holdsControls(missingFrom:)` is true after a capability change, the view calls `onReleaseAll` (the existing path).
  - Drawing: with no present accessory screen, the body is today's single canvas. Otherwise, in z order: canvas `.upTo(first screen)`, then for each accessory screen a layer with `contents = store.image(for:)`, `magnificationFilter = .nearest` or `.linear`, frame = the resolved frame, then the canvas for the nodes after it. At most two extra canvases are needed per screen; with several screens split at each.
  - Shelf animation: on a toggle, animate between the two resolved layouts for 0.2 s (`withAnimation(.easeInOut(duration: 0.2))` over an interpolation factor the canvases read); with `accessibilityReduceMotion`, switch at once.
  - `onProvidedChange` fires with `resolution.provided.keeping(pictures: store?.delivered ?? [])` on appear and whenever that value changes (layout, capabilities, shelf state, a picture arriving or clearing), and with `.none` on disappear.
  - Accessibility: the handle is an accessibility element, trait button, label `"<panel.label ?? panel.name>, open"` or `", closed"`. On tvOS the handle is not focusable and the shelf keeps its initial state.

- [ ] **Step 1: Write the failing tests.**

```swift
// PictureSplitTests (macOS host)
@Test func partsComposeToTheWholeImage()   // draw .upTo + picture + .after onto one context == Skin2Renderer.image(… pictures:) for the accessory-screen fixture, pixel for pixel
@Test func storePublishesOnlyOnChange()    // set the same CGImage twice → one objectWillChange
@Test func storeDeliveredFollowsSetAndClear()
// Format2PanelViewTests (simulator)
@Test func panelStateStartsFromTheDocument()            // open:true → flags == ["panel.vmu.open"]
@Test func panelStateRemembersPerSkin()                 // toggle, new instance with the same identifier and a scratch UserDefaults suite → toggled value; another identifier → document value
@Test func handleTouchTogglesAndSendsNoInput()          // drive Skin2TouchUIView as ControlHostTests does; sink records nothing, flags flip
@Test func closingShelfReleasesHeldInputs()             // hold a control inside the shelf, toggle with a second finger → sink saw release for it
@Test func capabilityLossReleasesHeldInputs()
@Test func providedDropsPictureWhenStoreClears()        // host the view, set an image → callback has "vmu.p1"; set nil → callback without it
@Test func providedIsNoneOnDisappear()
@Test func noAccessoryScreenMeansOneCanvas()            // the view's layer tree has no picture layer for the std-parts fixture
```

- [ ] **Step 2: Run** both files (`xcrun swift test --filter PictureSplitTests`; the UI file through `xcodebuild test … -only-testing:SkinKitUITests/Format2PanelViewTests`). Expected: FAIL to compile.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `xcrun swift test` and the SkinKitUI tests on an iOS and a tvOS simulator. Expected: PASS on both.
- [ ] **Step 5: Commit** `feat(format2): picture layers, shelf state and the provided callback`.

### Task 8: `std.vmu`, `Skin2PartView` and the Dreamcast VMU skin

**Files:**
- Modify: `Sources/SkinKit2Core/Resources/parts/std.json`, `Skin2StdParts.swift` (doc table, `featureName21 = "parts.std@2.1"`, `parts21: Set<String> = ["std.vmu"]`), `Skin2Features.swift` (a `use` of a name in `parts21` inserts `parts.std@2.1`), `Sources/SkinKit2Render/SkinKit2Render.swift`
- Create: `Sources/SkinKitUI/Rendering/Skin2/Skin2PartView.swift`
- Create: `Tests/Format2Fixtures/dreamcast-vmu/skin.json`, `Tests/Format2Fixtures/dreamcast-vmu/pictures/vmu.p1.png` (the same drawn test card as Task 2)
- Test: `Tests/SkinKit2CoreTests/StdPartsTests.swift`, `Tests/SkinKit2RenderTests/ReferenceImageTests.swift`, `Tests/SkinKitUITests/Skin2PartViewTests.swift` (new)

**Interfaces:**
- Consumes: Tasks 1 to 7.
- Produces:
  - Part `std.vmu` with parameters exactly as §8: `source` (string, default `vmu.p1`), `body`, `bodyShade`, `window` (colours; defaults charcoal `#2B2D31`, `#1C1D20`, amber-dark `#3A2A10`), `glass` (bool, default true), `buttons` (`none` | `art`, default `none`). Inner ids: `body`, `window`, `lcd` (the accessory screen), `glass`.
  - `public struct Skin2PartView: View { public init(part: String, with arguments: [String: Skin2JSON] = [:], capabilities: Set<String> = [], pictures: Skin2PictureStore? = nil) }`. It builds a document whose root is one instance of the part filling the view, lists the features that instance uses, and hosts `Skin2SkinView`. An unknown part or a document that fails to load draws nothing.
  - The skin `dreamcast-vmu`: identifier `com.provenance-emu.skinkit.dreamcast-vmu`, name "Dreamcast VMU", `gameTypes` the Dreamcast type iFly's bundled skins use (read it from `Resources/Skins/*.manicskin` `info.json` in the iFly checkout), a standard Dreamcast controller from `std.*` parts in charcoal, and one panel: `{"name":"vmu","label":"Visual Memory","needs":["picture.vmu.p1"],"presentation":"shelf","handle":"#vmuTab","open":true}` with `when` patches making it `fixed` in portrait and on iPad (`minWidth` 700), a shelf on the trailing edge in phone landscape. `requires` includes `parts.std@2.1`; `optional` is `["capabilities","screens.accessory","panels"]`.

- [ ] **Step 1: Write the failing tests.**

```swift
@Test func stdVMUExpandsWithAnAccessoryScreen()   // {"use":"std.vmu","id":"v"} → node "v.lcd" is a screen with source "vmu.p1"
@Test func stdVMUSourceParameterIsPassedThrough() // with source vmu.p2
@Test func usingStdVMUNeedsStdParts21()           // Skin2Features.used contains "parts.std@2.1"
@Test func vmuSkinRequiresStdParts21()            // the fixture's requires contains it; SkinKit2Render.supports(requires) is true here and false for a supported set without that name
@Test func vmuSkinValidatesClean()                // Skin2Validator report has no errors and no warnings on every bake trait
@Test func vmuSkinProvidesThePictureOnEveryTrait()// for each Skin2TraitSet of the doc, with capability and both shelf states: provided.pictures == ["vmu.p1"]
@Test func vmuSkinShelfStartsOpen()               // document.initialPanelFlags == ["panel.vmu.open"]
@Test func partViewDrawsStdVMUAlone()             // hosted at 240×160 with a picture: the provided callback is not needed; snapshot is non-empty and the LCD centre pixel matches the picture
@Test func partViewWithUnknownPartDrawsNothing()
```

- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement** the part, the view and the skin. Keep hit frames of the controller's controls clear of the shelf in both states (the validator enforces it).
- [ ] **Step 4: Record** the fixture's images (rest, `.open`, `.with-pictures` on phone portrait, phone landscape and iPad landscape) with `SKIN2_RECORD=1`, then `xcrun swift test` and the SkinKitUI tests. Expected: PASS.
- [ ] **Step 5: Bake check:** `xcrun swift run skinkit-bake Tests/Format2Fixtures/dreamcast-vmu <scratch dir>` produces a classic bundle with no panel. Then commit `feat(format2): std.vmu, Skin2PartView and the Dreamcast VMU skin`.
- [ ] **Step 6: Stop for the owner's look.** Render the three recorded images plus the open shelf to PNGs and show them to the owner before Task 9. Art changes he asks for are made here and re-recorded.

### Task 9: iFly mount

**Files (iFly worktree):**
- Modify: `Project.swift` (SkinKit `.revision(…)` → the head commit of SkinKit branch `format2/accessory-panels`; that commit must exist on the remote before iFly can resolve it, so this task starts only after the owner allows that branch to be pushed)
- Create: `Sources/Core/VMU/VMUPictureFeed.swift`
- Modify: `Sources/UI/Views/FloatingVMUView.swift` (read the feed instead of polling itself), `Sources/UI/Views/EmulatorWithSkinView.swift`, `Sources/UI/Views/EmulationView+Layout.swift`, `Sources/UI/Views/EmulationView.swift` (one `@State var skinProvided = Skin2Provided.none`)
- Create: `Resources/Skins/dreamcast-vmu.<bundle extension the app's other skins use>` built from the SkinKit fixture with `skinkit-bake`
- Test: `Tests/VMUPictureFeedTests.swift`, `Tests/SkinVMUOwnershipTests.swift`

**Interfaces:**
- Consumes: `Skin2PictureStore`, `Skin2Provided`, `Skin2Capabilities.picture(_:)`, `DeltaSkinView(… capabilities:pictures:onProvidedChange:)`.
- Produces:

```swift
@MainActor final class VMUPictureFeed: ObservableObject {
    static let shared: VMUPictureFeed
    let store: Skin2PictureStore                    // source "vmu.p1"
    @Published private(set) var image: CGImage?     // what FloatingVMUView draws; same image as the store's
    func start(); func stop()                       // reference counted; polls only while a reader is active
    init(copy: @escaping (Int32, UnsafeMutablePointer<UInt32>) -> Bool, clock: …)   // injectable for tests; the default calls flycast_copy_vmu_lcd
}
enum SkinVMUOwnership {
    static func capabilities(platform: Int32, hasVMU: Bool) -> Set<String>          // ["picture.vmu.p1"] or []
    static func showsFloatingVMU(settingOn: Bool, internalUIVisible: Bool, provided: Skin2Provided) -> Bool
}
```

- Rules: the feed copies the slot from `VMUDisplayPrefs.lcdIndex(platform:)`, compares with the last buffer, and on a change builds the `CGImage` through the same LCD filter path `FloatingVMUView` uses today. An all-zero buffer sets `nil` on both outputs. `showsFloatingVMU` is `settingOn && !internalUIVisible && !provided.pictures.contains("vmu.p1")`.

- [ ] **Step 1: Write the failing tests.**

```swift
@Test func zeroBufferDeliversNoPicture()          // copy returns true with zeros → image == nil, store.delivered is empty
@Test func changedBufferDeliversOneImage()        // two polls with the same bytes → one publish
@Test func failedCopyClearsThePicture()           // copy returns false after a frame → nil
@Test func feedPollsOnlyWhileStarted()
@Test func floatingVMUHidesWhenSkinProvides()     // showsFloatingVMU(true, false, provided with vmu.p1) == false
@Test func floatingVMUShowsWhenSkinDoesNot()      // .none → true
@Test func settingOffAlwaysHidesFloatingVMU()
@Test func capabilityIgnoresTheSetting()          // capabilities(platform: dreamcast, hasVMU: true) == ["picture.vmu.p1"]
```

- [ ] **Step 2: Run** them with iFly's test lane (`xcodebuild test … FLYCAST_SKIP_PREBUILD=YES`, per its `CLAUDE.md`). Expected: FAIL to compile.
- [ ] **Step 3: Implement.** `EmulatorWithSkinView` passes the capabilities, `VMUPictureFeed.shared.store` and an `onProvidedChange` that writes the `skinProvided` state; `EmulationView+Layout` replaces its `if VMUDisplayPrefs.isShown(…), !internalUIVisible` with `SkinVMUOwnership.showsFloatingVMU`. Leaving the skin (controller connected, skin changed) resets `skinProvided` to `.none` through the view's disappear callback.
- [ ] **Step 4: Run** the tests, then `make build-app` and `make build-app PLATFORM=tvOS`. Expected: PASS, both build.
- [ ] **Step 5: See it work.** In an iOS simulator with a homebrew disc that draws to the VMU (iFly's memory notes name the rig), select "Dreamcast VMU": the panel shows the game's LCD, the floating VMU is gone; switch to a classic bundled skin: the floating VMU returns; close the shelf in landscape: neither shows; reopen: the panel shows. Screenshot each state.
- [ ] **Step 6: Commit** `feat(skins): Dreamcast VMU skin with a live panel`.

### Task 10: TypeScript renderer (`skins` worktree)

**Files:**
- Modify: `docs/js/skin2/model.ts`, `features.ts`, `preprocess.ts`, `layout.ts`, `validate.ts`, `render.ts`, `std-parts.ts`, `index.ts` (and the compiled `.js` beside each)
- Create: `docs/js/skin2/capabilities.ts`, `docs/js/skin2/provided.ts`
- Vendored (script only): `fixtures/format2/accessory-screen/`, `panels/`, `dreamcast-vmu/`, `MANIFEST.json`, `docs/format/skin-2.0.schema.json`
- Test: `tests/skin2/layout.test.js`, `render.test.js`, `model.test.js`, new `tests/skin2/provided.test.js`

**Interfaces:**
- Consumes: the SkinKit branch's recorded fixtures.
- Produces (mirroring Swift names): `capabilities` on the environment; `has`; `optional`; `source` / `sampling`; `panel`; `resolvePanels`; `provided(resolution)` returning `{pictures: string[], inputs: string[], panels: Record<string, boolean>}` sorted; `render(…, {pictures: Record<string, CanvasImageSource>})`.

- [ ] **Step 1: Vendor:** `node tests/skin2/vendor-fixtures.mjs /Users/jmattiello/Workspace/Provenance/SkinKit/_worktrees/format2-accessory-panels/Tests/Format2Fixtures <SkinKit commit>`; extend the script to copy each fixture's `pictures/` folder and to vendor the schema if it does not already.
- [ ] **Step 2: Run** `cd tests/skin2 && npm ci && npm test`. Expected: the three new fixtures FAIL in `layout.test.js` and `render.test.js`.
- [ ] **Step 3: Add `provided.test.js`** with the same fourteen cases as Task 5, as inline documents, expecting the same sets.
- [ ] **Step 4: Port** Tasks 1 to 5 and the `std.vmu` part (`std-parts.ts` reads the vendored `std.json`). Accessory pictures draw with `imageSmoothingEnabled = false` for `nearest`.
- [ ] **Step 5: Run** `npm run build && npm test`, then `pytest tests/ -v` from the repo root. Expected: PASS; layouts match exactly, images within the existing thresholds.
- [ ] **Step 6: Commit** `feat(skin2): capabilities, panels and accessory screens`.

### Task 11: Format pages (`skins` worktree)

**Files:**
- Modify: `scripts/generate_format_reference.py` (new sections, and `hosts.html` added to the shared chrome's tab list), `docs/format/index.html`, `docs/format/examples.html`, `docs/format/playground.js`, `docs/format/preview.js`, `docs/format/reference.html` (generated)
- Create: `docs/format/hosts.html`, `docs/format/examples/dreamcast-vmu.json` (a copy of the fixture's `skin.json`), `docs/format/examples/pictures/vmu.p1.png`
- Test: `tests/test_format_pages.py`, `tests/skin2/format-docs.test.js`, `tests/browser/format-docs.cjs`

**Interfaces:**
- Consumes: Task 10.
- Produces, with these exact headings: in `reference.html` "Capabilities", "Accessory screens", "Panels", "Semantic inputs", "What the skin provides"; in `index.html` "What readers need" lists the five feature names of §7; `hosts.html` titled "Hosting a skin with panels" documents `capabilities`, `Skin2PictureStore`, `onProvidedChange`, `Skin2PartView`, `DeltaSkinSemanticInputHandling` and the one-line fallback rule of §5. The example figure and the playground gain a control strip: one checkbox per capability the document names, one per shelf ("open"), and the picture is drawn only while its capability is ticked. The caption under any drawn VMU picture reads exactly "sample frame".

- [ ] **Step 1: Write the failing tests:** in `test_format_pages.py`, `test_reference_has_panel_sections` (the five headings) and `test_hosts_page_uses_shared_chrome`; in `format-docs.test.js`, `dreamcast-vmu example validates clean and renders with and without capabilities`; in `format-docs.cjs`, unticking `picture.vmu.p1` removes the panel and the "sample frame" caption, ticking it restores both, and toggling "open" changes the rendered image.
- [ ] **Step 2: Run** `pytest tests/test_format_pages.py -v` and the Node tests. Expected: FAIL.
- [ ] **Step 3: Implement**, regenerate `reference.html` with the script.
- [ ] **Step 4: Run** `pytest tests/ -v`, `cd tests/skin2 && npm test`, and the browser flow the repo's `CLAUDE.md` gives for `format-docs.cjs`. Expected: PASS.
- [ ] **Step 5: Commit** `docs(format): panels, accessory screens and the host guide`.

### Task 12: Close out

- [ ] **Step 1:** In SkinKit, update `README.md`'s format 2 feature list and `ROADMAP.md` with slices 2 to 5 from the spec; mark the spec's status line "approved 2026-11-21; slice 1 built on `format2/accessory-panels`". Commit `docs: accessory panels slice 1 status`.
- [ ] **Step 2:** Run the full suites once more: SkinKit `scripts/ci-test.sh`; skins `pytest tests/ -v` and `npm test`; iFly tests and both `make build-app` platforms.
- [ ] **Step 3:** Report to the owner: the three branch names and head commits, the screenshots from Task 9, what was not checked on hardware (a real iPhone and iPad; VoiceOver on the handle), and that nothing is pushed beyond what he allowed in Task 9.
