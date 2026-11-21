# Skin format 2: accessory panels and live accessory screens (design)

Date: 2026-11-21. Status: draft, waiting for the owner's approval. Nothing here is built.

Extends [`2026-11-03-skin-format-2-design.md`](2026-11-03-skin-format-2-design.md) ("the 2.0 design") and [`2026-11-11-skin-format-2-live-effects-design.md`](2026-11-11-skin-format-2-live-effects-design.md) ("the live effects design"). Section numbers such as "live §8" refer to those.

## Why

A skin today can draw a controller and leave a hole for the game. It cannot hold the other things a real machine has on it: the Dreamcast's memory unit with its small screen, an arcade cabinet's coin and service buttons, an Atari console's switches. Each app draws those itself, in its own SwiftUI, beside or over the skin. iFly floats a VMU window over the game; arcade coin and test buttons live in a pause menu.

The owner wants a skin to carry these as working parts of its artwork: a panel built into the housing or a shelf that pops out of it, showing the real VMU picture and operating the real machine. It must be one shared capability of the format, with the schema, the runtime, the documentation site and working examples moving together, so the three apps do not each grow a private version.

## Who decided what

The owner decided:

- The idea, and its vocabulary: **accessory panel** is the general thing; **shelf** is one way of showing it (a drawer attached to the housing). An embedded panel and a shelf share one content model.
- It is a shared SkinKit capability across Provenance, iFly and iCube, not app-only SwiftUI.
- A VMU panel shows the frames the game really generates. Nothing made up may be presented as live. The documentation site may use fixture frames if they are labelled as fixtures.
- The app keeps emulation logic and core mappings. A skin never carries code, scripts or arbitrary shaders.
- A JSON declaration alone does not claim a control. The app hides its own control only when the skin really draws and can operate that control.
- Held inputs are released when the layout changes.
- Classic Delta and Manic skins keep working, and an old reader keeps the app's own controls.
- Layout state (is the shelf open) is separate from emulated hardware state.
- (2026-11-21) **The first working panel is the iFly VMU.**
- (2026-11-21) **Approach C**: the panel is written once as a reusable part and mounted in the controller skin first, in the TV around the picture second.

Every other choice below is mine and is listed under "Calls I made".

## What exists today (checked 2026-11-21)

- **SkinKit** (`origin/main` at `9a39d4a`; tag `0.4.0` is older). Format 2, the control host and both bezel modules are merged. `SkinKit2Core` has the model, validator, resolver, preprocessor (parts, tokens, themes, variants) and the standard parts library `parts.std@2.0` (`Resources/parts/std.json`, eight controller parts). `SkinKit2Render` has the Core Graphics drawer, hit testing, the touch tracker and `Skin2InputSink` / `Skin2InputBridge`. `SkinKitUI` hosts format 2: `DeltaSkinView` switches to `DeltaSkinFormat2View` when a bundle's `skin.json` loads, validates and its `requires` are supported; `DeltaSkinFormat2Sink` forwards control events to the app's `DeltaSkinInputHandling`.
- **A `screen` node is always the game.** Its roles are `main`, `top`, `bottom`, `touch`. The renderer draws nothing for it (a placeholder in previews). `DeltaSkinFormat2.viewportFrame` reports only the main screen's frame to the app.
- **Conditions** (`when`, `visible`) test `orientation`, `device`, `displayType`, `flag`, `minWidth`, `minHeight`, `theme`, `variant`. Flags are app-supplied names in `Skin2Environment.flags` (`altToggled`, `keypadShown`, `microphone`).
- **Layout changes already release held inputs.** `Skin2TouchSnapshot.holdsControls(missingFrom:)` makes the host call `releaseAll`.
- **The live effects design is approved and unbuilt.** It defines `optional` beside `requires`, `screen.overlay` (nodes after a screen draw over it), `paint.picture`, signals and the `display` document for TVs. None of it is in the code.
- **No panel, capability, semantic input or ownership code exists** on `main` or on any unmerged branch (`format2/control-host`, `docs/format2-live-effects`, `codex/skin2-wiki-guide`, `release/0.4.0`, `codex/provenance-format2-compat`, `codex/store-device-layouts`, `codex/skinkit-testflight-compat`, `fix/screen-filter-undefined-keys`).
- **TVs** (`SkinKitBezels`): built-in TVs are format 2 documents drawn through a `uborder` shader with the artwork as a texture; imported TVs are images laid over the picture. Neither path has a touch layer.
- **iFly** (`develop` at `255f24f1e`, SkinKit pinned at `446ad75`): controller skins go through `DeltaSkinView` (`EmulatorWithSkinView`) with `DreamcastInputHandler`. Its three bundled Dreamcast skins are classic `.manicskin` files; it bundles no format 2 skin. The VMU picture is real: flycast writes `vmu_lcd_data` (48×32 RGBA per slot, changed only when the game changes it) and `flycast_copy_vmu_lcd(slot, pixels)` copies it; `VMUDisplayPrefs.lcdIndex(platform:)` gives player 1's slot. `FloatingVMUView` polls that and draws a floating window, gated by the setting "Show VMU In-Game" (`VMUDisplayPrefs.isShown`). `VMUWatchPublisher` reads the same source for the watch. VMU buttons do nothing during a Dreamcast game; they matter only in iFly's standalone VMU emulator (`VMUDevice.setButton`).
- **Provenance** uses the format 2 renderer only for artwork in `PVTouchOverlay`, with its own touch pipeline. **iCube** has no format 2 use that I found; its checkout path in the handoff does not exist.
- **Documentation site**: the `skins` repo, `docs/format/` (reference, tutorial, examples, playground, the schema copy) and the TypeScript renderer in `docs/js/skin2/`. The schema is generated from `Skin2Schema.swift`.

## Goals

- A skin can place a panel in its artwork or as a pop-out shelf, sized and placed by the normal layout rules, adapting to orientation and room.
- A panel can show a live picture that is not the game: first the VMU's screen.
- A panel's controls operate real machine functions through named inputs the app maps to its core.
- The app learns exactly which pictures and controls the skin is providing right now, and hides only those of its own.
- The same panel content can be mounted in a controller skin, in a TV around the picture, or drawn alone.
- Schema, Swift runtime, TypeScript renderer, reference pages and one working example land together.

## Non-goals

- Arcade and Atari panels, and the iCube mount. They are later slices (see "Slices"); this design shapes the contract so they fit, and the plan builds only slice 1.
- Building the whole live effects design. Slice 1 builds two small pieces of it (`optional`, and drawing over a screen for accessory screens only).
- VMU buttons during a game. They do nothing on real hardware while the unit is in the controller.
- A new documentation site. The existing format pages gain sections.
- App Store media, screenshots, or any submission.

## Anti-goals (failure even if it works)

- A panel that shows a picture the game did not produce, or a switch that looks moved when the core's setting did not change.
- Two copies of the same control on screen by accident, or none: the app hides its VMU and the skin's panel is not actually visible.
- A skin that stops working on a reader without these features, or a classic skin that changes at all.
- A private panel system in one app.
- A button stuck down after a shelf closes or a panel disappears.

## Approaches

**A. The panel only inside the controller skin.** A panel is ordinary nodes in `skin.json` plus the missing pieces (accessory screens, capabilities, the provided report). Smallest change; touch already works there. It reaches only players using touch skins on iPhone and iPad, and each skin redraws its own VMU housing.

**B. The panel in the TV around the picture first.** Matches the concept art and reaches controller and Apple TV players. But the built-in TVs are drawn by a shader with the artwork as a texture and have no touch layer, so a live picture and touch both need new machinery before anything shows.

**C. One reusable panel part, mounted in both (chosen).** Format 2 already has reusable parts and a standard library. The VMU housing becomes a standard part; a panel is a group that instantiates it. A small view draws a part alone, which is how the TV mounts it later and how the documentation shows it. Slightly more than A, and the arcade and Atari panels reuse the same route.

The owner picked C on 2026-11-21. A was the fallback; B was dropped as a first step because it needs the most new machinery to show the least.

## Design

`formatVersion` stays `"2.0"`. No 2.0 reader has shipped, so these are additions to 2.0, as in live §8.

### 1. Two different questions: features and capabilities

- A **feature** is what the *reader* can do (`requires`, `optional`). It is fixed for a build of SkinKit.
- A **capability** is what the *app and the running game* can supply right now: a VMU picture, a coin input. It changes per core, per game and during play (a VMU is unplugged).

`Skin2Environment` gains `capabilities: Set<String>`. Names are dotted and come from a registry in `SkinKit2Core` (`Skin2Capabilities`); the validator rejects names that are not in it, so a skin cannot invent one.

| Capability | Meaning |
|---|---|
| `picture.vmu.p1` … `picture.vmu.p4` | the app can supply that player's memory-unit screen for the running game |
| `input.<name>` | the app has wired the semantic input `<name>` (§4) to the running core |

A `Condition` gains the key `has` (one capability name or a list; all must be present). It works wherever `flag` works: `"visible": {"has": "picture.vmu.p1"}`.

A change of capabilities is a change of environment: the layout resolves again, and held inputs that no longer exist are released by the existing rule.

### 2. Accessory screens

A `screen` node gains `source`. The default, `"game"`, is today's behaviour. Any other value names a picture the app supplies:

```json
{ "type": "screen", "id": "lcd", "source": "vmu.p1", "sampling": "nearest", "layout": { … } }
```

| Key | Type | Notes |
|---|---|---|
| `source` | `game` \| a picture name from the registry (`vmu.p1`…`vmu.p4`) | default `game` |
| `sampling` | `nearest` \| `linear` | how the picture is scaled into the frame; default `nearest` for accessory sources |
| `aspect` | number | default is the source's native aspect (VMU: 48:32) |

Rules:

- An accessory screen never takes `role` or `placement`, is never the viewport, and is not counted by the "at least one screen" checks.
- It is drawn only while the app has the capability `picture.<source>` **and** has handed over a picture. Otherwise it draws nothing, and its frame still takes its place in the layout. To remove the housing with it, put it in a panel (§3) or under `visible: {has: …}`.
- The app supplies a finished image at any resolution. SkinKit fits it to the frame with `sampling` and does not recolour it. The look of the LCD (iFly's LCD filters) stays the app's, so the player's chosen filter shows in the skin as it does in the floating window.
- Nodes after the screen in document order draw over it (glass, a glare, a tinted window). This is live §2's draw-order rule; slice 1 builds it for accessory screens only.
- In the rest frame, in bakes and in classic output it draws nothing. A renderer handed a still for the source draws it, so fixtures cover it in Swift and TypeScript. Previews (`screenPlaceholders`) draw a placeholder marked with the source's name.
- A live effects `paint.picture` may name an accessory screen by `#id` once that design is built. Nothing extra is needed here.
- At most four accessory screens per skin.

### 3. Panels

A `group` node gains `panel`. Its children are ordinary nodes, usually one part instance:

```json
{ "type": "group", "id": "vmuPanel",
  "panel": { "name": "vmu", "label": "Visual Memory", "needs": ["picture.vmu.p1"],
             "presentation": "shelf", "handle": "#vmuTab", "open": true },
  "layout": { … },
  "when": [ { "flag": "panel.vmu.open", "layout": { "offset": { "x": 0 } } } ],
  "children": [
    { "use": "std.vmu", "id": "vmu", "with": { "source": "vmu.p1" } },
    { "type": "control", "id": "vmuTab", "kind": "action", "input": "togglePanel", … }
  ] }
```

| Key | Type | Notes |
|---|---|---|
| `name` | string | unique in the document; used in flags and reports |
| `label` | string | spoken by VoiceOver for the panel and its handle |
| `needs` | [capability] | if the app lacks any, the whole group is absent: not drawn, not hit-tested, no layout space. Default: none |
| `presentation` | `fixed` \| `shelf` | default `fixed` |
| `handle` | `#id` | required for `shelf`: a control in the group, kind `action`, input `togglePanel` |
| `open` | bool | a shelf's state the first time the skin is shown; default `false` |

- **`fixed`** is always shown. Whether it sits inside the housing art ("embedded") or against an edge of the canvas ("docked") is ordinary layout, not a different kind of panel.
- **`shelf`** has two states. The skin view owns the state and exposes it as the flag `panel.<name>.open`, which the skin's own `when` patches use to move, resize or fade the panel. While closed, every child except the handle is not drawn and not hit-tested. The handle's touch toggles the state and is never sent to the app.
- A `when` entry may also carry `panel: {"presentation": …}`, so a skin can be fixed in landscape on an iPad and a shelf on a phone.
- **Opening and closing** re-resolves the layout. The host animates frames and opacity between the two resolved layouts over 200 ms; with Reduce Motion on it switches without moving. Held inputs inside a closing shelf are released first.
- **The validator** requires that a shelf's handle exists, is inside the group, is at least 44×44 pt in its hit frame, does not overlap another control's hit frame in either state, and lies inside the safe area in both states on every bake trait. It rejects a panel inside a panel and duplicate names. At most six panels per skin.
- **Accessibility:** the handle is a button named "`label`, open" or "closed". Panel controls get labels from the semantic input registry (§4) unless the node gives one. On tvOS and with a hardware controller a shelf starts and stays as its `open` value, because there is no touch to move it (the TV mount in slice 2 defines focus movement).
- **Flags named `panel.*` are reserved** for the skin view; an app may not supply them. The validator already resolves the layout once per bake trait set (`Skin2TraitSet.sets(for:)`); for a document with shelves it resolves each trait with every shelf open and with every shelf closed.
- **When `presentation` changes by condition:** `handle` is required if any condition can make the panel a shelf. While the panel is fixed the handle is absent (not drawn, not hit-tested) and the stored open state is kept but ignored.
- **Remembering:** the skin view reports changes of open state; `SkinKitUI` stores it per skin identifier and panel name beside the skin's theme selection.

### 4. Semantic inputs

Controller buttons keep their classic names (`a`, `start`). Things that are not pad buttons get dotted names from a registry in `SkinKit2Core` (`Skin2SemanticInputs`), each with a kind and an English label:

| Name | Kind | Slice |
|---|---|---|
| `arcade.coin1`, `arcade.coin2`, `arcade.service`, `arcade.test` | momentary | 3 |
| `console.reset`, `console.select` | momentary | 4 |
| `console.difficulty.left`, `console.difficulty.right`, `console.tvType` | two-position switch | 4 |
| `vmu.a`, `vmu.b`, `vmu.mode`, `vmu.sleep`, `vmu.up`, `vmu.down`, `vmu.left`, `vmu.right` | momentary | later, with the standalone VMU |

- A control whose input is a semantic name is present only while the app has `input.<name>`. Without it the control is absent like a panel whose `needs` fail. This is automatic; the skin writes no condition.
- Momentary inputs arrive through `Skin2InputSink.press` / `release` with the dotted name. The app's sink maps them to its core. `SkinKitUI` gains an optional `DeltaSkinSemanticInputHandling` so `DeltaSkinFormat2Sink` routes dotted names there instead of to `buttonPressed`.
- A validator rule: dotted input names must be in the registry.
- **Two-position switches are designed in slice 4, not here.** They need a `switch` control kind whose drawn position comes from the app (the core's real setting), never from the touch alone. The registry rows above reserve the names.

Slice 1 adds the registry type, the validator rule and the routing, with no rows in use. The VMU panel has a picture and no controls.

### 5. What the skin is providing (ownership)

`Skin2Resolution` gains `provided`:

```swift
public struct Skin2Provided: Equatable, Sendable {
    public var pictures: Set<String>   // "vmu.p1"
    public var inputs: Set<String>     // "arcade.coin1"
    public var panels: [String: Bool]  // name → open
}
```

It is computed from the resolved tree, not from the document:

- A **picture** is provided when an accessory screen with that source is present (its panel's `needs` hold, its conditions pass), its frame is at least 48×32 pt and inside the canvas, its opacity is above 0.05, and it is in a fixed panel, an open shelf, a closed shelf whose handle is reachable, or no panel.
- An **input** is provided when a control with that input is present with a hit frame of at least 44×44 pt inside the canvas, in a fixed panel, an open shelf, a closed shelf whose handle is reachable, or no panel.
- "Reachable" means the handle is present and its hit frame is inside the safe area. A closed shelf still provides its contents, because the player closed it on purpose and can open it. A shelf whose handle is off screen provides nothing.
- A `screen` or `control` node (not a group) may carry `"duplicate": true` to say it does not claim its picture or input (an intentional second copy). It is then left out of `provided`. Several nodes may show the same picture or input without the mark; the thing is provided if any one of them qualifies.
- The view layer narrows `pictures` further: a source is reported only once the app has actually delivered a picture for it (§6).

`Skin2SkinView` gains `onProvidedChange: (Skin2Provided) -> Void`, and `DeltaSkinView` passes it through. It fires on appear and whenever the set changes, and with an empty value on disappear. A classic skin, or a 2.0 skin drawn as its bake, never fires a non-empty value, so the app keeps its own controls.

The app's rule is one line per fallback: show my floating VMU unless `provided.pictures` contains `vmu.p1`.

### 6. Delivering pictures

`SkinKit2Render` gains `Skin2PictureStore`, a main-actor observable object the app owns and the skin view reads:

```swift
@MainActor public final class Skin2PictureStore: ObservableObject {
    public func set(_ image: CGImage?, for source: String)   // nil = no picture now
    public func image(for source: String) -> CGImage?
}
```

- `Skin2SkinView` takes `pictures: Skin2PictureStore?`. For each accessory screen it places a `CALayer` at the resolved frame with the image as contents and the magnification filter from `sampling`. Changing a picture updates only that layer; the skin's canvas is not redrawn.
- The canvas is split at each accessory screen into the part under it and the part over it, so glass drawn after the screen sits on top. With no accessory screens the view is exactly today's single canvas.
- `Skin2RenderOptions` gains `pictures: [String: CGImage]` for the one-shot drawer (`Skin2Renderer.image`), used by fixtures, snapshots and previews.
- **Stills for fixtures** are PNG files named `pictures/<source>.png` beside the fixture's `skin.json`, read top-left first like every other asset, and vendored into the `skins` repo with the fixture. Both renderers scale them with the screen's `sampling`.
- Budget: at most four layers; pictures are copied by the app, never read from the core by SkinKit.

### 7. Features and what old readers do

| Feature | Covers |
|---|---|
| `capabilities` | `Skin2Environment.capabilities`, the `has` condition |
| `screens.accessory` | `source`, `sampling` on screens; pictures; drawing over an accessory screen |
| `panels` | `panel` on groups, `togglePanel`, `panel.<name>.open` flags |
| `inputs.semantic` | dotted input names |
| `parts.std@2.1` | the standard parts added here (`std.vmu`) |

- Slice 1 builds live §8's `optional` key (model, schema, validator rule "every feature the content uses is in one list or the other"). These features belong in `optional`.
- A reader that lacks an optional feature draws the skin without it: `panels` → panel groups are absent; `screens.accessory` → accessory screens are absent; `capabilities` → every `has` is false; `inputs.semantic` → those controls are absent. In each case `provided` is empty for those things and the app's own controls stay.
- **Baking:** a panel group and everything in it is left out of the classic bake, as is any accessory screen and any semantic control. The baker warns once per skin. A Delta or Manic reader therefore sees the controller alone and the app's own VMU.
- **Readers pinned before this work** (iFly at `446ad75`, Provenance at `6cfcebd`) ignore unknown keys, so they would not know `optional` or `source`. A skin that uses a new standard part must therefore list `parts.std@2.1` in `requires`, which makes those readers draw the bake. Every app that bundles such a skin moves its pin in the same change.
- Listing one of these in `requires` is allowed and only changes what a reader that lacks it does (draws the bake).

### 8. The standard VMU part and drawing a part alone

`std.json` gains `std.vmu`: the memory unit's housing with an accessory screen as its window.

| Parameter | Default | Notes |
|---|---|---|
| `source` | `vmu.p1` | the accessory picture |
| `body`, `bodyShade` | charcoal | housing colours |
| `window` | amber-tinted dark | the colour behind and around the LCD |
| `glass` | on | a soft glare drawn over the screen |
| `buttons` | `none` | `none` \| `art` (drawn, not controls). Working buttons come with the standalone VMU slice |

The art is vector shapes only, drawn for this project. It does not copy the housing from the concept image or any photographed hardware.

`SkinKitUI` gains `Skin2PartView(part:with:size:capabilities:pictures:)`, which wraps one named part in a minimal document and draws it with the same view. It is what slice 2 mounts in a TV, what the documentation's example uses, and what an app can use as its own floating accessory in place of hand-written SwiftUI.

### 9. iFly: the first mount

- Checkouts: iFly is `/Users/jmattiello/Workspace/Provenance/iFly/iFly` (`develop`); the `skins` repo is `/Users/jmattiello/Workspace/Provenance/skins` (`main`; the local checkout sits on another branch, so use a worktree). Each repo gets a branch for this work.
- Move the SkinKit pin to a revision on this work's SkinKit branch, the way iFly pins a pull request head today. It moves to a tag when the owner releases one.
- **Capabilities:** `picture.vmu.p1` while the running platform has a VMU in player 1's controller (`VMUDisplayPrefs.currentPlatform` and the slot from `lcdIndex`), whatever "Show VMU In-Game" says. That setting keeps meaning the floating window.
- **Pictures:** move the polling in `FloatingVMUView` (copy on change, build a `CGImage`, apply the chosen LCD filter) into one `VMUPictureFeed` object. `FloatingVMUView` reads it, and it writes the same image to a `Skin2PictureStore` passed to `DeltaSkinView`. One poll, two readers. An all-zero buffer (no frame pushed yet) sets `nil`, so the skin provides nothing and the placeholder rule in `FloatingVMUView` is unchanged.
- **Ownership:** `EmulationView+Layout` shows `FloatingVMUView` when the setting is on **and** `provided.pictures` lacks `vmu.p1`.
- **The skin:** one new bundled format 2 Dreamcast skin, "Dreamcast VMU" (working name), charcoal with an amber window, using `std.vmu` in a panel. Phone portrait: fixed, above the buttons. Phone landscape: a shelf on the trailing edge, closed by default. iPad: fixed. It ships with its classic bake like any format 2 bundle. The source lives in SkinKit's examples so the site and the tests use the same file.
- tvOS and controller-only play have no controller skin, so they keep the floating window until slice 2.

### 10. Documentation and the TypeScript renderer (`skins` repo)

- Regenerate `skin-2.0.schema.json` from `Skin2Schema.swift`. Never edit the generated copy.
- `docs/js/skin2/`: capabilities and `has`; `optional`; panels with open state and the `togglePanel` handle; accessory screens drawn from a supplied still; `std.vmu`; `provided` computed the same way, with the same fixtures as Swift.
- `docs/format/reference.html`: sections "Capabilities", "Accessory screens", "Panels", "Semantic inputs", "What the skin provides". `index.html`: "What readers need" gains the five features.
- `docs/format/examples.html` and the playground: the Dreamcast VMU skin with switches for each capability, shelf open and closed, and a still VMU frame. The still is visibly captioned "sample frame"; it is not a capture presented as live.
- Host API reference (the Swift side: `capabilities`, `Skin2PictureStore`, `onProvidedChange`, `Skin2PartView`, the semantic handler) as a new page, `docs/format/hosts.html`.

### 11. Tests

- **Core:** validator cases for every rule in §1 to §4 and §7; resolver cases for `has`, `needs`, shelf open and closed; `provided` for each line of §5, including a handle pushed outside the safe area and `duplicate`.
- **Render:** new fixtures `panels` and `accessory-screen` with recorded PNGs (rest frame, with a still, shelf open, shelf closed), shared with the TypeScript port.
- **Bake:** a skin with a panel bakes to a classic skin with no trace of it.
- **Input:** a control held inside a shelf is released when the shelf closes and when its capability goes away.
- **iFly:** unit tests for the feed (zero buffer → nil, change detection) and for the show/hide rule; a simulator check with a homebrew disc that draws to the VMU.

## Slices

1. **This plan:** §1 to §8 in SkinKit (with `optional` and the over-screen split), the iFly mount (§9), documentation and TypeScript (§10), tests (§11).
2. **The TV mount.** A `display` document gains panels; `SkinKitBezelsUI` draws `Skin2PartView` over the shader's output at the panel's resolved frame, for built-in and image TVs. Focus movement for controllers and Apple TV. Depends on live effects' `display` key.
3. **Arcade service panel.** `std.arcadeService`; `arcade.*` inputs wired in iFly (Naomi, Atomiswave) and Provenance (MAME) as proof that two apps share one panel. Needs Provenance to route its format 2 touches through `Skin2InputSink`.
4. **Atari console switches.** The `switch` control kind with app-reported state, `console.*`, Stella in Provenance. The console model named in the handoff ("Atari 5800") is not a real model I can identify; the owner confirms which machine before any art.
5. **iCube**, once its checkout and its supported actions are known.

Each later slice gets its own short design. The owner reviews the VMU skin's look before more housings are drawn.

## Limits (added to 2.0 §11)

Four accessory screens, six panels, no nested panels, 64 characters for a panel name, capability and semantic names only from the registries.

## Calls I made (not the owner's words)

1. **Capabilities are separate from features**, with a registry, so "this reader can" and "this game can, now" never mix.
2. **`has` as a condition key and `needs` on a panel** instead of a new negotiation message.
3. **An accessory screen is a `screen` with `source`**, not a new node type.
4. **The app supplies a finished image; SkinKit does not recolour it.** iFly's LCD filters keep working, and the amber look is the window art plus the player's filter.
5. **Two presentations, `fixed` and `shelf`.** "Embedded" and "docked" are both `fixed` with different layout.
6. **Shelf state is a flag the skin's own `when` patches read**, so no new animation language; the host tweens between two resolved layouts.
7. **A closed shelf with a reachable handle still provides its contents**; an unreachable one provides nothing.
8. **`provided` is computed from the resolved tree** with size and visibility thresholds (48×32 pt for a picture, 44×44 pt for a control, opacity above 0.05), and a picture counts only after the app has delivered one.
9. **`"duplicate": true`** is the explicit way to allow a second copy.
10. **Pictures are drawn in layers above a split canvas**, so a changing VMU does not redraw the skin.
11. **Slice 1 builds `optional` and the over-screen split** from the live effects design, and nothing else from it.
12. **Panels, accessory screens and semantic controls are left out of bakes.**
13. **`std.vmu` has no working buttons in slice 1**, because they do nothing during a game.
14. **"Show VMU In-Game" governs only iFly's floating window**; a skin with a VMU panel shows it regardless.
15. **One new bundled Dreamcast skin carries the panel**; the three existing classic skins are untouched.
16. **Switches wait for slice 4**; only their names are reserved now.
17. **From the builder check:** reserved `panel.*` flags and validating shelves in both states; the handle rule when `presentation` changes; `duplicate` on screens and controls only; PNG stills in `pictures/`; `parts.std@2.1` in `requires` so older pinned readers draw the bake.
18. **The registry names** in §1 and §4, the feature names in §7, and `parts.std@2.1` for the new standard part.
19. **The spec lives in `docs/specs/`**, where this repo keeps its designs.

## Left to the builder

- Confirming that a `screen` inside a part works. Parts are expanded as plain JSON before decoding, so no node type is special; if that proves wrong, the fallback is to write the VMU housing inline in the example skin and add the part afterwards.
- How the canvas split is implemented (two `Canvas` views around the layers, or one layer-backed view).
- The exact store used to remember shelf state, following how theme selection is stored.
- The VMU skin's geometry on each trait, within §9.
- Whether iFly's `VMUWatchPublisher` also moves onto `VMUPictureFeed` (only if it falls out naturally).
- The order of work between the Swift and TypeScript renderers, as long as they land with the same fixtures.

## Not part of this work

Publishing a SkinKit release, merging, App Store media and any App Review submission are separate decisions. Work lands on branches and waits for the owner.
