# Skin format 2.0: design

Design for Provenance-Emu/SkinKit#25. Turns the notes ([`2026-10-23-skin-format-2-notes.md`](2026-10-23-skin-format-2-notes.md), including the spike findings of 2026-11-03, spike PR #56) into a format the three apps and the website can build against. Stage 4 of the [roadmap](../../ROADMAP.md); after the app store releases.

Status: proposed. Nothing here ships until the follow-up issues at the end are done in order.

## Why

iCube, iFly and Provenance each draw their default on-screen controller from Swift: shapes, gradients, labels and a layout computed from the screen size. Those three generators are about 2,000 lines of near-duplicate code that no one but a developer can change, that the website cannot preview, and that cannot be recoloured, edited or published to emuskins.com. The classic Delta/Manic format can't hold them either: it is pictures plus rectangles, one picture per device and orientation.

Format 2.0 is a declarative description of a skin (a tree of shapes, text, controls and screens with layout rules, tokens and variants) that renders natively in the apps and in the browser, adapts to any screen from one file, and bakes to a classic skin so Delta and Manic keep working.

## What exists today (researched 2026-11-03)

Paths are relative to each repo. Line numbers drift; search for the symbol.

**iCube** (`DolphiniOS/UI/Emulation/TouchOverlay/`): `TouchOverlayDefaults.gameCube(canvas:safeArea:orientation:)` computes centres bottom-up per column from a `Screen` struct (unit `min(max(shortSide/390, 1), 1.35)`, gap 8, edge `max(safeInset, 8) + 8`, a 70 pt landscape diagonal, an iPad band clamp). Groups are `TouchOverlayGroupLayout {group, placement: TouchOverlayPlacement(anchor, inset, size), controls: [TouchOverlayControl {id, kind, frame}]}` with anchors `bottomLeading/bottomTrailing/bottomCenter/fill/fillInset` (`TouchOverlayLayoutEngine.swift`). Art is `TouchOverlayArt`: two palettes (GameCube, Wii), shapes circle/kidney/bar/pill, cross d-pad with four arrows, octagonal stick gate, each with gradient, gloss, rim, two shadows and a label. Hit testing is on frames (`TouchOverlayHitTester`), pressed looks are SwiftUI state. Player edits: `TouchOverlayLayoutStore` (anchored centres). Four pad kinds: GameCube, Wii Remote, sideways Wii Remote, Classic Controller.

**Provenance** (`PVTouchOverlay/Sources/PVTouchOverlay/`): the most data-driven. `SystemOverlayBinding` per system gives families (`OverlayFamily`, 18 of them: `FourFace`, `GameCube`, `DualStick`, `Keypad`, …), slot→input tokens (`OverlayFamilySlot` → `"a"`, `"cross"`, `"l1"`, …), labels, an `OverlayPalette` of nine colour slots (`shell, primary…quaternary, utility, dpad, stick, label`) and switches/actions. A family builds an `OverlayTemplate {padKind, orientation, groups: [OverlayGroup {id, controls: [OverlayControl {id, kind, frame, label, shape, paletteSlot, axis}], placement: OverlayPlacement(anchor, inset), scale, opacity, toggledBy}], screenPolicy}`. `OverlayLayoutEngine.resolve` (reference width 390, unit clamp 1…1.35, extended edges 20) and `OverlayScreenPlanner` (`topBand`, `centerColumn`, `dualStacked`, `dualStacked3DS`, `fill`) produce `OverlayLayout` with `hitFrame`s and `screenFrames`. Shapes: `circle, kidney, pill, bar, cross, ring, knob, key, surface` (`OverlayShapePath`), styles flat/glossy/outline (`OverlayArt`). Variants: `OverlayPadKind {system, subtype}` where subtype is a `ControllerLayoutVariant` id (`genesis-6btn`, `psx-dualshock`). Player edits: `OverlayLayoutOverrides` with `AnchoredCenter` (edge or centre-relative, canvas-independent), per pad kind and per game MD5 (`OverlayLayoutStore`, `touch_overlay_layout_v1.json`).

**iFly** (`Sources/UI/Views/Controller/`): imperative. `ConsoleOverlayLayout.metrics(container:isPortrait:safeArea:)` returns absolute centres (left column stick-under-dpad, face cluster right, triggers 100 pt above, Start/special strip centre; portrait margin 20, landscape 50); `VirtualControllerOverlay.consoleLayout` builds a `[ControlGroup: (CGSize, CGPoint)]` dict, arcade layouts in `ArcadePortraitLayout`/`ArcadeLandscapeLayout`. Art: `ControllerArtKit` with a 5-colour `Palette` (dreamcast, arcade) and three `ControllerButtonStyle`s (`flat`, `glossy`, `outline`), bundled image slots (`ifly.ctrl.<slot>`) overriding procedural art. Player edits: `ButtonLayoutStore`, centres normalised 0–1 per skin class and orientation.

**Classic format in SkinKit** (`Sources/SkinKitCore/`): `DeltaSkin` decodes `info.json` (`representations[device][displayType][orientation]` → `assets`, `items[]`, `screens[]`, `mappingSize`, `extendedEdges`, `translucent`, plus Provenance's `themes`, `gameOverrides`, `altRepresentations`, item `states`/`haptic`, screen `maintainAspectRatio`, `keyboardOverlay`). Items are `DeltaSkinButton {id, input(s), frame, extendedEdges, thumbstick, states, haptic}`; screens are `DeltaSkinScreen {inputFrame, outputFrame, placement, filters}`. `SkinKitUI/Rendering/DeltaSkin+Rendering.swift` draws PDF/PNG/SVG artwork; `DeltaSkinValidator` checks files. The website (`skins/docs/js/`) has no renderer; it shows catalog thumbnails. The RetroArch converter (#22) and the web editor (`2026-11-03-skin-editing-tools-design.md`) will need a browser-side model of a skin, which 2.0 provides.

**Spike** (#24, PR #56): one JSON file (171 lines) reproduced iCube's GameCube pad in both orientations through anchors, stacks and one `when` patch; see the findings in the notes for what was missing (typed lengths, min/max, controller shapes, stroke alignment, shadow order, states, visibility, text metrics).

## Goals

- One file describes a skin for every device and orientation. Portrait and landscape of iCube's GameCube pad are one file today; that stays the acceptance test.
- Each app's generated default skins become 2.0 files, rendered by SkinKit, and the generators are deleted.
- The website renders and edits 2.0 skins without a server; the editor of `2026-11-03-skin-editing-tools-design.md` is its first client.
- Every 2.0 skin bakes to a classic skin that Delta and Manic load as a normal `.deltaskin`/`.manicskin`.
- The Swift and TypeScript renderers agree on shared reference images.
- Creators can recolour (tokens, themes) and re-map (variants) without touching the tree.

## Non-goals

- Replacing the classic format for hand-drawn skins. Artists keep shipping PDFs; 2.0 is for skins that are shapes and rules.
- Scripting, expressions beyond `min`/`max`/`sum`, animation beyond state transitions. Not in 2.0; revisit after an editor exists.
- Materials beyond the named list (gloss, brushed metal, plastic grain, CRT) and raw shaders.
- Hand-written YAML. JSON is the format; a YAML front end can be a website feature later.

## Anti-goals (failure even if it works)

- A 2.0 skin that installs in Delta or Manic and shows a broken controller. The baked classic part must be complete on its own.
- A renderer that needs a code change to draw a skin the schema accepts. If the schema allows it, both renderers draw it.
- Two renderers that drift. A fixture that passes in Swift and fails in TypeScript blocks the merge.
- Downloaded content that runs code. No scripting, no shader source, no URL-fetching nodes.

## Design

### 1. File placement, versioning, feature detection

A 2.0 skin is a classic skin bundle that also carries its source.

```
MySkin.deltaskin/            (zip; .manicskin identical)
  info.json                  classic, baked: items, screens, mappingSize, assets per trait set
  skin.json                  the 2.0 source (this document)
  assets/                    images and fonts skin.json references (optional)
  bake/
    iphone-edgeToEdge-portrait.pdf   one PDF per baked trait set, named by the baker
    …
  preview.png                thumbnail, baked (the catalog's crawler keeps using it)
```

`info.json` stays a complete classic skin (the non-negotiable). It gains one additive key:

```json
"format2": { "source": "skin.json", "formatVersion": "2.0", "requires": ["layout.stack", "shapes.path"] }
```

Delta and Manic ignore it. A 2.0-aware app reads `format2`, checks that it supports every entry of `requires`, and if so renders `skin.json`; otherwise it renders the baked `info.json` like any classic skin. Edits saved by the player (section 4.7) are stored next to the bundle, never inside it.

**Versioning.** `skin.json` has `"formatVersion": "2.0"`. Major bumps break; minor bumps add optional keys and features. A reader accepts any `2.x`, ignores unknown keys, and honours `requires`. **Feature names** are the unit of detection; each renderer publishes the set it implements and the validator checks `requires` against the skin's actual content (a skin that uses `grid` must list `layout.grid`):

| Feature | Covers |
|---|---|
| `layout.anchors` | `anchor`, `offset`, named areas |
| `layout.stack`, `layout.grid`, `layout.repeat` | stacks, grids, `repeat` |
| `shapes.parametric` | rect, squircle, ellipse, capsule, polygon, star, arc, line, cross, kidney, trapezoid |
| `shapes.path` | SVG path strings |
| `paint.gradients`, `paint.image` | linear/radial/angular gradients, tiled image fills |
| `effects.shadow`, `effects.blur`, `effects.blend` | portable effects |
| `effects.ci` | Core Image filter list (iOS only; the TS renderer ignores it and draws without) |
| `materials` | named materials |
| `text` | text nodes |
| `parts`, `tokens`, `themes`, `variants`, `states` | sections 3.9, 7, 6.4 |
| `controls.dpad`, `controls.thumbstick`, `controls.touchSurface` | control kinds beyond buttons |

The catalog's health check (`skins/link_health.py`) validates `skin.json` against the schema, re-bakes it, and fails the entry if the baked `info.json` differs from the one in the bundle (section 8.6).

### 2. Coordinates and lengths

**Unit.** A skin declares its reference scale:

```json
"reference": { "shortSide": 390, "minScale": 1.0, "maxScale": 1.35 }
```

`unit = clamp(min(canvas.width, canvas.height) / shortSide, minScale, maxScale)`. All three apps use this rule already (iCube `Spacing`, Provenance `OverlayLayoutEngine`). Lengths in points are multiplied by `unit`. The spike matched iCube's geometry to the point with it.

**Length values.** The spike's "number means points, `"50%"` string means fraction" lost its meaning through part parameters. 2.0 keeps the two short forms and adds a typed form; the schema says which fields take a `Length`:

| JSON | Meaning |
|---|---|
| `8` | 8 points at reference scale (× unit) |
| `"50%"` | 0.5 × the parent's size along that axis |
| `{"pt": 8}` / `{"frac": 0.5}` | the same, explicit (required for part parameters of type `length`) |
| `{"max": [Length, Length]}`, `{"min": […]}`, `{"sum": […]}` | the only operators; nesting allowed, depth ≤ 4 |

`{"sum": [{"max": [{"safe": "left"}, 8]}, 8]}` is iCube's edge rule; `{"safe": "left|right|top|bottom"}` is the only variable and is only valid inside `offset`/`inset`. Canvas fractions do not exist: the iPad xib that broke on phones is the reason.

**Coordinate space.** Top-left origin, y down, in canvas points. Every node resolves to a frame in that space. Named areas a node may anchor to: `parent` (default), `canvas`, `safeArea`, `screen` (the first screen node, after it resolves), `#id` (any node resolved earlier in document order).

**Rounding.** Resolved frames are rounded to 1/2 point before drawing and baking, so both renderers and the baker agree.

### 3. Node schema

A skin is one `root` group. Every node has the common fields; each type adds its own. "L" is a `Length`, "C" a colour (`#RRGGBB` or `#RRGGBBAA`, or a `$token`).

**Document**

| Key | Type | Notes |
|---|---|---|
| `formatVersion` | string | `"2.0"` |
| `requires` | [string] | feature names (section 1) |
| `identifier`, `name`, `author`, `gameTypes` | string, string, string?, [string] | mirrored into `info.json` by the baker |
| `reference` | object | section 2 |
| `tokens`, `themes`, `variants`, `parts` | objects | section 7, 3.9 |
| `screens` | [string]? | ids of screen nodes in display order (dual screen); default: document order |
| `root` | Node | type `group` |

**Common node fields**

| Key | Type | Notes |
|---|---|---|
| `type` | `group` \| `shape` \| `image` \| `text` \| `control` \| `screen` | required |
| `id` | string | unique in the skin; required on controls and screens; `#id` anchors and variants use it |
| `layout` | Layout | section 4; absent = fill the parent |
| `when` | [Condition] | ordered patches (section 4.6) |
| `visible` | Condition? | node is laid out and drawn only when true; default true |
| `opacity` | number | 0–1, multiplies the subtree |
| `effects` | [Effect] | on a group or control: rasterises the subtree once, then applies |
| `repeat` | Repeat | section 4.5 |
| `use`, `with` | string, object | part instantiation (section 3.9); replaced by the part's node before validation |

**`group`**: `children: [Node]`, `stack: Stack?`, `grid: Grid?` (at most one). A group with neither lays children out by their own `layout`.

**`shape`**

| Key | Type | Notes |
|---|---|---|
| `shape` | Shape | below |
| `fills` | [Paint] | drawn in order, first at the bottom |
| `strokes` | [Stroke] | drawn after the fills, in order |
| `effects` | [Effect] | shadows apply to the union of fills; see 5.3 |
| `role` | `knob` \| `base` \| `highlight`? | meaning inside a control (6.2) |

Shape kinds (`shapes.parametric` unless noted):

| `kind` | Parameters | Notes |
|---|---|---|
| `rect` | `cornerRadius` L=0, `corners` [tl,tr,br,bl]? | |
| `squircle` | `cornerRadius` L | continuous corners (SwiftUI `.continuous`; TS: superellipse n=4 approximation, fixture-checked) |
| `ellipse` | | `circle` is an alias |
| `capsule` | | radius = half the short side |
| `polygon` | `sides` ≥3, `rotation` deg=0, `cornerRadius` L=0 | inscribed in the frame's short side |
| `star` | `points` ≥3, `innerRatio` 0–1, `rotation` | |
| `arc` | `startAngle`, `endAngle` deg, `inner` frac=0 | ring sector when `inner` > 0 |
| `line` | `from`, `to` as [frac, frac] | stroked only |
| `cross` | `armRatio` frac=0.34, `cornerRadius` L=6 | the d-pad body all three apps draw |
| `kidney` | `bulge` 0–1=0.5 | Provenance's/iCube's bean, long axis horizontal; rotate the node for vertical |
| `trapezoid` | `taper` frac=0.14 | iCube's bar/trigger |
| `path` | `d` string, `box` [x,y,w,h] | `shapes.path`; SVG `M L H V C S Q T A Z`, absolute and relative; stretched non-uniformly from `box` to the frame; `d` ≤ 4 KB |

**`image`**: `src` (path under `assets/`, PNG/PDF/SVG per the classic lookup rules), `mode`: `fit` \| `fill` \| `stretch` \| `tile`, `tint` C? (template images). No remote URLs.

**`text`**: `text` string, `font` `{family?, size: L, weight: regular|medium|semibold|bold}`, `color` C, `align` `leading|center|trailing`, `fit` bool (shrink to the frame, min 60 %). `family` is a bundled font in `assets/fonts/` or omitted for the renderer's default sans; both renderers draw glyph outlines (section 9.3), so a bundled font renders identically everywhere. `size` is points × unit, never scaled by the frame (spike finding 10).

**`control`**

| Key | Type | Notes |
|---|---|---|
| `kind` | `button` \| `dpad` \| `thumbstick` \| `trigger` \| `touchSurface` \| `action` | section 6 |
| `input` / `inputs` | string / [string] | classic input names (`a`, `start`, `leftThumbstick`, `up`…); `dpad` takes `{up, down, left, right}`; `action` takes `menu`, `quickSave`, `quickLoad`, `fastForward`, `toggleAltRepresentations`, `toggleKeyboard`, … (the Provenance `OverlayAction` list) |
| `hit` | `{extend: L \| {top,left,bottom,right}}` | hit frame = resolved frame outset; default 0 |
| `travel` | L | `thumbstick` only: knob travel radius; default 35 % of the short side |
| `states` | object | `pressed`, `selected`, and for d-pads `pressed.up` … (6.4) |
| `haptic` | `{style, intensity}` | mirrors the classic `haptic` |
| `children` | [Node] | the art; a `role: knob` child is the thumbstick's knob |

**`screen`**: `aspect` number? (native aspect; the app may override from the core), `role` `main|top|bottom|touch`, `filters` [ {name, params} ]? (classic `filters`, Provenance only), `placement` `app|controller` (classic `placement`). A screen is a node, so it is laid out with the same rules; the app replaces its frame with the live video.

**JSON Schema.** The normative schema is `docs/schema/skin-2.0.schema.json` (follow-up issue 1), generated from the Swift model with a test that every fixture validates. The tables above are its summary; where they disagree the schema wins. Skeleton:

```json
{ "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://emuskins.com/schema/skin-2.0.schema.json",
  "type": "object", "required": ["formatVersion", "identifier", "name", "gameTypes", "reference", "root"],
  "properties": { "formatVersion": { "pattern": "^2\\.[0-9]+$" }, "root": { "$ref": "#/$defs/node" } },
  "$defs": { "node": { "oneOf": [ {"$ref": "#/$defs/group"}, {"$ref": "#/$defs/shape"}, "…" ] },
             "length": { "oneOf": [ {"type": "number"}, {"pattern": "^-?[0-9.]+%$"}, {"$ref": "#/$defs/lengthExpr"} ] } } }
```

#### 3.9 Parts

```json
"parts": {
  "faceButton": {
    "params": { "input": {"type": "string"}, "label": {"type": "string"},
                "top": {"type": "color", "default": "$neutralTop"}, "shape": {"type": "shape", "default": {"kind": "ellipse"}},
                "knob": {"type": "length", "default": {"frac": 0.5}} },
    "node": { "type": "control", "kind": "button", "input": "@input", "children": [ "…" ] } } }
```

`{"use": "faceButton", "with": {"input": "a", "label": "A"}, "id": "a", "layout": {…}}` expands to the part's node with `@param` references substituted and the caller's extra keys (`id`, `layout`, `when`, `visible`) merged over it. Parameters are typed (`string`, `number`, `length`, `color`, `shape`, `paint`), which is what the spike lacked. Parts may use other parts; depth ≤ 8, no recursion. Expansion happens before validation, so the validator sees a plain tree and the renderers never see `use`.

A shared **standard parts library** (`SkinKit/Sources/SkinKit2Core/Resources/parts/`) holds the controller vocabulary the three apps draw today (face button, kidney button, trigger bar, cross d-pad with lit arrows, dished stick with octagonal gate, pill, keypad key). Skins reference it with `"use": "std.faceButton"`. The library is versioned with the format and is part of `requires` (`parts.std@2.0`).

### 4. Layout model

#### 4.1 Resolution

For a canvas (size, safe-area insets, orientation, device class, flags) the resolver walks the tree once, parents before children, in document order:

1. Apply `when` patches whose conditions hold (in order; later wins) and evaluate `visible`.
2. Size the node (4.2). Groups with a `stack`/`grid` size from their children's sizes.
3. Place the node (4.3) against its reference area.
4. Record `#id`.
5. Resolve children inside the node's frame; a stack/grid assigns children their frames instead of 4.3.
6. Expand `repeat` (4.5).

Hidden nodes take no space (a stack skips them). Output is a tree of `(node, frame, hitFrame, transforms)` that the renderers and the baker consume; the resolver is pure and lives in `SkinKit2Core` (Swift) and `skins/docs/js/skin2/layout.js` (TS), each a port of the same pseudocode in this section, checked by the layout fixtures (9.2).

#### 4.2 Size

`layout.size: {width: L?, height: L?}` plus `layout.aspect` number? Rules in order: explicit `frame` → its size; `inset` → parent minus inset; stack/grid group → packed size; otherwise each axis from `size`, the missing axis from `aspect` if given, else the parent's. `minSize`/`maxSize` (`{width, height}` of L) clamp the result. Controls must end ≥ 44 pt on the short side at unit 1; the validator warns, the renderer does not fix.

#### 4.3 Anchors

```json
"layout": { "anchor": { "x": "trailing", "y": "bottom", "to": "safeArea" },
            "offset": { "x": {"sum": [{"max": [{"safe": "right"}, 8]}, 8]}, "y": -6 } }
```

`x` ∈ leading/center/trailing, `y` ∈ top/center/bottom; `to` is a named area (section 2). `offset` moves the anchored edge (positive x to the right, positive y down). `frame: [x, y, w, h]` places explicitly in the parent (the classic way, for clusters like the GameCube face buttons). `inset: L | {top,left,bottom,right}` fills the parent minus the inset.

#### 4.4 Stacks and grids

`stack: {axis: vertical|horizontal, spacing: L, align: leading|center|trailing (cross axis), distribute: packed|spaceBetween}`. Children are placed in order along the axis; a child's own `anchor` on the cross axis overrides `align` (L leading above a centred stick); its `offset` applies after placement. A vertical stack anchored at the bottom grows upward because the group is placed after it is sized.

`grid: {columns: n, spacing: L | {x, y}, align}` for keypads and grilles; cells are equal; a child may set `layout.span: {columns, rows}`.

Neither reflows. `distribute: spaceBetween` is the only spring; the "flexible spacing" of the notes is this plus `min`/`max` on offsets. The spike showed stacks remove the need for iCube's band clamp and iFly's metric arithmetic.

#### 4.5 Repeat

`repeat: {count: n ≤ 64, offset: {x: L, y: L}?, rotate: deg?, scale: number?, pivot: self|parent}`. Copies are the node drawn `count` times with the cumulative transform; copy `i` can be addressed by `states` as `#id[i]` (lit d-pad arrows). Hit testing ignores copies (controls can't repeat).

#### 4.6 Conditions

```json
"when": [ { "orientation": "landscape", "layout": { "offset": { "x": 70 } } },
          { "device": "ipad", "layout": { "size": { "width": 96 } } } ]
```

A `Condition` is an object whose keys all must match: `orientation` (portrait|landscape), `device` (iphone|ipad|tv|mac|web), `displayType` (standard|edgeToEdge|splitView, the classic trait), `flag` (an app-supplied name: `microphone`, `keypadShown`, `altToggled`), `minWidth`/`minHeight` (points), `theme`, `variant`. A `when` entry carries any subset of `layout`, `visible`, `opacity`, `fills`, `strokes`, `text`. `null` clears a layout field. Patches apply in order; nothing is re-evaluated after resolution (no feedback).

`visible` takes one Condition. Provenance's `toggledBy` and iCube's Microphone are `visible: {flag: "keypadShown"}`; the app declares which flags exist.

#### 4.7 Player edits

Default positions are hints. The app stores edits per skin, per `(device, orientation)`, per node id: `{offset: {x, y} in points at reference scale, scale, opacity, hidden}`, in `<skin-id>.edits.json` beside the installed bundle (the `DeltaSkinLayoutEdits` store of the editing-tools design, extended with ids). Edits apply after step 3 and before children resolve, so a moved stick keeps its knob. The app clamps edited frames inside the safe area. Migration of the existing stores: Provenance's `AnchoredCenter` and iFly's normalised centres convert to an offset from the 2.0 default on first launch (section 10).

#### 4.8 Screens

A screen node is laid out like any node; its `aspect` sizes it when one dimension is given. Dual screens are two screen nodes with `role: top` and `role: bottom` in a stack; the app matches roles to its displays (Provenance's `dualStacked`/`dualStacked3DS` become two nodes in a vertical stack with the 3DS top screen at `aspect: 1.667`). A `touchSurface` control with `inputs: ["touchScreen"]` anchored `to: "#bottom"` is the DS touch screen. The app may override a screen's frame (integer scaling, filters); the skin's frame is the budget it fits in.

### 5. Paint, effects, materials

#### 5.1 Paint

| `type` | Fields |
|---|---|
| `solid` | `color` C, `opacity` |
| `linear` | `start`, `end` [frac, frac] in the node's frame, `stops: [[C, at] \| [C, opacity, at]]` |
| `radial` | `center` [frac, frac], `radius` frac of the longer side, `stops` |
| `angular` | `center`, `startAngle` deg, `stops` |
| `image` | `src`, `mode: tile|fit|fill`, `scale`, `opacity` (`paint.image`) |

Stops are sorted by `at`; colours interpolate in sRGB (both renderers; Core Graphics with a device RGB space, Canvas 2D is sRGB).

#### 5.2 Stroke

`{color, opacity, width: L, align: center|inner|outer, dash: [L], cap: butt|round|square, join: miter|round|bevel}`. Inner and outer strokes are drawn as a double-width stroke clipped to (or clipped out of) the path, in both renderers.

#### 5.3 Effects

`effects` is an ordered list; the renderer applies it as: shadows (all of them, listed order, each a separate pass drawn under the node's content), then the content, then `blur` (Gaussian, radius L, applies to the node's rasterised content), then `blend` (`mode`: normal|multiply|screen|overlay|softLight|plus; applies when compositing the node onto its parent). A node with `effects` on a group or control is rasterised to a layer first. Core Image `{type: "ci", name, params}` entries render on Apple platforms only and are skipped elsewhere, so a skin that relies on them lists `effects.ci` in `requires` and the baker renders with them.

`shadow: {color C, opacity, radius: L (blur radius), offset: [L, L], spread: L=0, inner: bool=false}`. A blur radius of r means a Gaussian with σ = r/2 in both renderers (Core Graphics `setShadow(blur:)` is ≈2σ; Canvas `shadowBlur` is ≈σ×2 as well, fixture-checked).

#### 5.4 Materials

`material: {name: gloss|brushedMetal|plasticGrain|crt, intensity: 0–1, params}` on a shape node, applied after fills and before strokes. Each is specified as a recipe of the primitives above (gloss = a top-half white-to-clear linear fill plus a bottom inner shadow; brushed metal = an angular gradient plus a tiled noise image bundled with the renderers; plastic grain = tiled noise at low opacity; CRT = scanline tile plus a radial vignette). Renderers may implement a material natively (Metal) as long as the reference fixture passes within tolerance. Material recipes live in the standard parts library so a renderer without `materials` can expand them.

### 6. Controls, inputs, hit areas

#### 6.1 Kinds

| `kind` | Inputs | Hit behaviour |
|---|---|---|
| `button` | one or more classic input names; several = combo (classic `inputs` array) | frame + `hit.extend` |
| `trigger` | one analog input (`l`, `r`, `l2`…); pressure if the device has it, else 1.0 | as button |
| `dpad` | `{up, down, left, right}` | frame split 3×3 (centre dead zone 20 % of the side); diagonals press two; rolling between zones is tracked |
| `thumbstick` | `leftThumbstick`/`rightThumbstick` (`cStick`, `nunchukStick` as aliases per game type) plus optional `click` | frame; the knob child follows the touch within `travel`; axis values = offset / travel clamped to the unit circle |
| `touchSurface` | `touchScreen`, `pointer`, `lightGun`, `trackpad` | frame; touches are forwarded as normalised coordinates |
| `action` | one app action | frame; fires on touch-down only |

Input names are the classic ones so the bake is lossless; the per-system vocabulary and the token→core-button tables stay in the apps (`DeltaSkinInputHandler`, Provenance's binding tokens). The validator checks inputs against `gameTypes` using the same table the catalog's health check uses.

#### 6.2 Art roles

Inside a control, children are art. `role: knob` marks the thumbstick knob (moves with the touch; baked as the classic `thumbstick` asset), `role: base` the part that stays, `role: highlight` a child drawn only while pressed (an alternative to `states` for simple cases).

#### 6.3 Hit areas

The hit frame is the resolved frame outset by `hit.extend`. Shapes are never hit-tested (all three apps already test frames; iCube's cosmetic octagon gate is explicitly not the hit geometry). Controls may overlap visually but the validator rejects overlapping hit frames in any baked trait set, except a `touchSurface`, which sits under everything. Multi-touch: one touch per control, several controls per finger drag (the classic cluster behaviour), as `OverlayTouchCluster` and `TouchOverlayCluster` do today.

#### 6.4 States

```json
"states": { "pressed": { "scale": 0.92, "patch": [ { "target": "#body", "fills": [ "…" ] } ] },
            "pressed.up": { "patch": [ { "target": "#arrow[0]", "fills": [ { "type": "solid", "color": "$glow" } ] } ] } }
```

A state is a scale/opacity for the control plus a list of patches on descendants by id (same patch shape as `when`). Transitions: scale eases 80 ms, everything else switches (iCube's finding about animated shadows). States are not baked (classic has no pressed art) except into Provenance's additive `states.pressed` image when the baker runs with `--states`.

### 7. Tokens, themes, variants

**Tokens** are typed: `"tokens": {"glow": {"color": "#9E7AF2"}, "gap": {"length": 8}, "label": {"string": "A"}}`; the short form `"glow": "#9E7AF2"` / `"gap": 8` infers colour/number. `$name` anywhere a value of that type is allowed. A theme is a partial token map: `"themes": {"wii": {"glow": "#52A0FF", "neutralTop": "#FFFFFF"}}`. The app's theme picker (`DeltaSkinThemePickerView`, #49) lists them; the baker emits one classic `themes` entry per theme with re-rendered PDFs.

**Variants** replace classic `gameOverrides` and `altRepresentations` for 2.0 skins:

```json
"variants": {
  "sixButton": { "label": "6 buttons", "match": { "any": true }, "patch": [ { "target": "#face", "visible": true }, "…" ] },
  "mario64":   { "match": { "md5": ["…"], "title": ["Super Mario 64"] }, "patch": [ "…" ] },
  "alt":       { "toggle": true, "patch": [ "…" ] } }
```

`match` reuses the matching order of the game-overrides work (#48): md5, crc, filename, title; `any: true` makes it a player-selectable layout (Provenance's `ControllerLayoutVariant` subtypes, iFly's styles, iCube's pad kinds). `toggle: true` is the Ignited alternate layout, flipped by an `action` control `toggleAltRepresentations`. A patch targets nodes by `#id` and may set any node field; variants apply before `when`. At bake time a `match` variant becomes a `gameOverrides` entry, the `toggle` variant becomes `altRepresentations`, and `any` variants become separate baked skins in a catalog family (`groupId`, `variantLabel`, per the variants design).

### 8. Bake to classic

The baker turns `skin.json` into the `info.json`, PDFs and preview the bundle ships. It is deterministic: same input, same bytes.

#### 8.1 Trait sets

| Device · displayType | Portrait canvas, safe area (t,l,b,r) | Landscape canvas, safe area |
|---|---|---|
| iphone · standard | 414×736, 0 | 736×414, 0 |
| iphone · edgeToEdge | 393×852, 59/0/34/0 | 852×393, 0/59/21/59 |
| ipad · standard | 834×1194, 24/0/20/0 | 1194×834, 24/0/20/0 |
| ipad · splitView | 639×1194, 24/0/20/0 | 639×834 (landscape only in classic) |
| tv · standard | — | 1920×1080, 60/80/60/80 (title-safe) |

Sizes are the `mappingSize` written per representation. A skin may restrict the sets with `"bake": {"traits": ["iphone.edgeToEdge", …]}`; the validator requires at least iPhone standard and edgeToEdge in both orientations (the base `representations` must be a complete skin). Ones a 2.0 renderer draws live (Mac, web, odd windows) are not baked.

#### 8.2 Algorithm, per trait set and per theme

1. Resolve the tree on the trait's canvas (section 4) with no edits, flags off, the theme's tokens, and the base variant.
2. **Background PDF**: draw every node that is not a control's knob and not a screen into a vector PDF page of `mappingSize` (Core Graphics `CGPDFContext` in Swift, `pdf-lib` plus the shared path/paint emitter in TS). Fills, strokes and paths stay vector; shadows, blur, materials and CI filters are rasterised into an embedded image at 3× (per node, clipped to its bounds plus the blur radius) so the PDF stays small. Text is emitted as glyph outlines (no fonts in the PDF). Controls' static art is part of the background, as every generated skin draws it today.
3. **Items**: one classic item per control: `inputs` (dpad → the four directions with `up/down/left/right`; thumbstick → `{"up","down","left","right"}` plus `thumbstick: {name, width, height}`), `frame` = resolved frame, `extendedEdges` = `hit.extend`, `haptic` passed through, `kind` for `touchSurface` roles (`touchScreen` input). `action` controls become items with the app-action input names Delta understands (`menu`, `quickSave`, `quickLoad`, `fastForward`, `toggleAltRepresentations`); unknown ones are dropped with a warning.
4. **Thumbstick knobs**: each `role: knob` subtree is rendered to its own PDF (`bake/<id>-knob.pdf`) at its resolved size.
5. **Screens**: `outputFrame` = resolved frame; `inputFrame` from the game type's native size (`system-native-resolutions.json`), `placement`, `filters`, `maintainAspectRatio: true`; dual screens by role order.
6. `translucent: false`, `extendedEdges` from the skin's default `hit.extend`, assets `{"resizable": "bake/<trait>.pdf"}`.
7. Preview: the iPhone edgeToEdge portrait trait rasterised at 2× to `preview.png`.

Themes: steps 1–7 per theme into `themes[name]` (Provenance's additive key; the base theme is the base `representations`). `match` variants: `gameOverrides[key]` with their own representations. `toggle` variant: `altRepresentations`. `any` variants: separate bundles named `<name> — <label>`.

#### 8.3 Classic-only keys

The baker writes `name`, `identifier`, `gameTypeIdentifier` (first of `gameTypes`; one bundle per game type otherwise), `debug: false`, and `format2` (section 1). Mapping is lossy in one direction only: states, materials and responsive layout are gone in classic, which is the point of keeping the source in the bundle.

#### 8.4 Where it runs

`SkinKit2Bake` (Swift, macOS and iOS; CoreGraphics) is canonical and is what the apps use to export and what CI uses to verify. `skins/tools/skin2/bake.js` (TS, Node and browser) is the website's and the health check's. Both must produce byte-identical `info.json` and PDFs whose rasterisations agree with the parity tolerance; the TS PDF bytes need not match.

#### 8.5 Export in apps

"Export as classic skin" in the skin options sheet (editing-tools design) runs the baker and shares the bundle. iCube/iFly/Provenance ship their default 2.0 skins already baked, so a first launch never bakes.

#### 8.6 Catalog

A 2.0 entry in `catalog.json` is a normal entry (old apps install the classic part) with `format2: true`. `link_health.py` validates `skin.json` (schema, `requires` vs content, overlapping hit frames, inputs vs game type), re-bakes with the TS baker and diffs `info.json`; a mismatch hides the entry like a missing artwork does.

### 9. Two renderers, one result

#### 9.1 Renderers

- **Swift**: `SkinKit2Core` (model, validator, preprocessor, resolver; no UI) and `SkinKit2Render` in `SkinKitUI` (Core Graphics drawer plus a SwiftUI `Canvas` host with hit testing and states; `GraphicsContext.withCGContext` as in the spike so there is one drawer). `DeltaSkin+Rendering.swift` keeps drawing classic skins; `SkinView` picks the 2.0 path when `format2` is present and supported.
- **TypeScript**: `skins/docs/js/skin2/` (`model.ts`, `layout.ts`, `render.ts` on Canvas 2D, `bake.ts`), ES modules with no build step beyond `tsc`, consumed by the site's preview, the editor and the RetroArch converter.

#### 9.2 Shared fixtures

`SkinKit/Tests/Format2Fixtures/<name>/skin.json` plus `expected/<trait>@2x.png` and `expected/<trait>.layout.json` (every node's resolved frame and hit frame). The Swift renderer generates the expected files on a `--record` run; both renderers must then reproduce them. Fixture set:

| Fixture | Exercises |
|---|---|
| `gamecube-icube` | the spike skin: parts, tokens, themes, stacks, when, repeat, path shapes |
| `snes-provenance`, `dreamcast-ifly` | the other two apps' defaults after migration |
| `shapes` | every parametric kind at three sizes and rotations |
| `paths` | every SVG command, relative and absolute, non-uniform boxes |
| `paint` | gradients with 2–8 stops, image tiles, opacity stacking |
| `strokes` | widths, alignments, dashes, caps, joins |
| `effects` | shadow lists, inner shadows, blur, blend modes, group effects |
| `text` | weights, sizes, `fit`, a bundled font |
| `layout` | anchors to every area, min/max/sum, insets, explicit frames, iPad and tv traits |
| `stacks-grids` | both axes, alignments, spaceBetween, hidden children, a keypad grid |
| `states` | pressed, per-direction, knob displaced (rendered with a state set) |
| `variants` | match, any, toggle; themes |
| `dual-screen` | DS and 3DS stacks with a touch surface |

The `skins` repo vendors the fixtures (git submodule or a copy checked by a hash test) so the TS tests run without SkinKit.

#### 9.3 Tolerances and the hard cases

- Layout JSON must match exactly after rounding to 0.5 pt.
- Images: `pixelmatch` with threshold 0.1 per channel; at most 0.25 % of pixels may differ for shape/paint/layout fixtures, 1.0 % for effects (blur kernels differ), measured at 2×.
- Text: both renderers draw glyph outlines (CoreText `CTFontCreatePathForGlyph`, opentype.js in TS) from the same bundled font, with no hinting or subpixel positioning, so text is a shape. The default font is bundled with both renderers (an OFL face, one weight axis).
- Gradients interpolate in sRGB with no dithering (Core Graphics `CGGradient` and Canvas 2D agree within the threshold at 8-bit).
- Shadows: Gaussian σ = radius/2; the TS renderer blurs an offscreen canvas with a separable kernel rather than `shadowBlur`, so the kernel is known.
- Squircles: the TS renderer uses the same cubic approximation as the Swift one (both custom; no `.continuous` in SwiftUI), so the fixture matches exactly.

CI: SkinKit's `xcrun swift test` runs the Swift side on macOS; the `skins` repo's `npm test` runs the TS side against the vendored fixtures; a SkinKit workflow re-runs the TS tests against the SkinKit copy whenever fixtures change.

### 10. Migrating the three apps' generated skins

Each app converts its generators to data in three steps, behind a flag, with screenshot tests comparing the new rendering against the old on three canvases (iPhone portrait/landscape, iPad landscape) before the generator is deleted.

**iCube** (`TouchOverlayDefaults`, `TouchOverlayArt`, `TouchOverlayModel`): four skins (`gamecube.skin.json`, `wii-remote`, `wii-remote-sideways`, `wii-classic`), each a `gameTypes` entry (`ngc`, `wii`) with the pad kind as an `any` variant where the app picks (`TouchOverlayPadKind` → variant id). The GameCube spike file is the first, with `std.*` parts replacing its inline parts. Microphone: `visible: {flag: "microphone"}`. IR pointer: a `touchSurface` with input `pointer` and `inset: 24`. Input ids: the skin uses classic names; `SkinOverlayInput`'s existing table maps them to `TCButtonType` raw ids. Edits: `TouchOverlayLayoutStore` anchored centres → 2.0 offsets.

**Provenance** (`PVTouchOverlay`): a generator script (`PVTouchOverlay/Tools/export-skins.swift`, run once, checked in) walks `SystemOverlayBindings.table`, and for each binding and each family subtype emits a skin: palette slots → tokens (`shell`, `primary`…), `OverlayFamily.template` for both orientations → one tree with `when: orientation` patches (the family kit's anchors map one-to-one: `centerLeading` → `{x: leading, y: center}`), `OverlayShape` → shape kinds, labels → text, `toggledBy` → `visible: {flag}`, `screenPolicy` → a screen node (`topBand` = portrait screen anchored top with `aspect`; `centerColumn` = landscape screen `inset`; dual policies = two screens). Variants (`genesis-3btn`/`6btn`, `psx-digital`/`dualshock`) → `any` variants in one skin per system. The 18 families become `std.*` parts plus per-family groups. `OverlayLayoutStore` → edits. The `PVTouchOverlay` package shrinks to input dispatch and the editor; `ProgrammaticOverlayView` mounts `SkinKitUI`'s 2.0 view.

**iFly** (`ConsoleOverlayLayout`, `VirtualControllerOverlay`, `ControllerArtKit`): Dreamcast console and arcade layouts become two skins; the centre arithmetic becomes anchors (left column stack, face cluster trailing, triggers anchored to the column tops with `min`), the three `ControllerButtonStyle`s become three themes (flat/glossy/outline differ in fills, strokes and materials only), the arcade palette a fourth. Bundled `ifly.ctrl.*` images become `image` nodes in `assets/`. `ButtonLayoutStore` normalised centres → edits.

Shared: `SkinKitUI` gains the hit-testing and state host for 2.0 controls, built from Provenance's `OverlayTouchCluster` (the most complete). Each app's input sink stays (`OverlayInputSinkAdapter`, `SkinOverlayInput`, iFly's `MultiTouchView` handlers).

### 11. Limits and safety

No code, no URLs, no fonts outside the bundle. Validator limits: ≤ 2,000 nodes after expansion, `repeat` ≤ 64, path `d` ≤ 4 KB, parts depth ≤ 8, image assets per the classic limits (`SkinAssetRenderer` 4096 px / 64 MB cache), `skin.json` ≤ 512 KB. The decoder is strict (unknown keys are ignored, wrong types fail) but the loader never crashes the app: a skin that fails validation falls back to its baked classic part, and a bundle without a valid classic part is rejected at import like today.

## Constraints

- Never break a skin that works in Delta or Manic. Everything 2.0 adds to `info.json` is one ignored key; the baked representations are complete.
- The catalog stays one flat `catalog.json`; `format2: true` is an additive field.
- Swift 5 language mode, iOS 17 / tvOS 17; the resolver and the model have no UI dependency so `xcrun swift test` covers them on macOS.
- The TS side has no build step the site doesn't already have (ES modules; `tsc` in CI only).
- macOS is case-insensitive: asset names and ids compare case-sensitively in the validator so a skin never depends on the file system.

## Order of work

1. Schema, model, validator, preprocessor, resolver in `SkinKit2Core`, with the layout fixtures (issue 1).
2. Swift renderer and the full fixture set, recorded (issue 2). The spike's GameCube file becomes the first fixture.
3. TypeScript model/resolver/renderer against the vendored fixtures (issue 3).
4. Baker, Swift then TS, with the health-check hook (issue 4).
5. Parity CI in both repos (issue 5).
6. iCube conversion first (smallest), then Provenance (largest, scripted), then iFly (issues 6–8).
7. Website docs, wiki, catalog support (issues 9–10).

1–2 and 3 can run in parallel once 1's fixtures exist. 6–8 need 2 and 4.

## Calls I made

- **Points at reference scale, not fractions.** Fractions of the canvas broke iCube's iPad xib on phones; the unit rule all three apps converged on is the one skins should declare.
- **Frames are the hit areas.** Every app tests frames today; shape-based hit testing would make the TS and Swift sides disagree on edges and buy nothing.
- **Explicit frames stay.** Anchors and stacks cover columns and rows; the nested face cluster is a hand-placed group and should say so.
- **Text as outlines.** It is the only way two renderers on two text stacks produce the same pixels, and it keeps fonts out of PDFs.
- **One Swift drawer.** Core Graphics under a SwiftUI `Canvas` (the spike's `withCGContext`) instead of a SwiftUI `Shape` tree per node, because the baker needs the same drawer and SwiftUI view trees are what made the generators slow to type-check.
- **The baker is part of the format.** A 2.0 skin without its baked classic part is invalid; the health check enforces it.
- **Variants replace `themes`/`gameOverrides`/`altRepresentations` at the source and produce them at bake**, so the Stage 2 app work keeps paying off and old apps see the familiar keys.
- **`min`/`max`/`sum` and nothing more.** They cover every rule in the three generators; expressions come back only with an editor that can show them.
- **The TS baker's PDF need not be byte-identical**, only its `info.json` and rendering; PDF writers differ and a byte diff would be busywork.

## Follow-up issues to create

Create these in SkinKit (milestone: Stage 4) after the design is approved; each links back here. Titles and bodies are ready to paste.

**1. Format 2.0: schema, model, validator and layout resolver (`SkinKit2Core`)**

> **Where:** SkinKit `Sources/SkinKit2Core/`, `docs/schema/skin-2.0.schema.json`, `Tests/Format2Fixtures/`
>
> **Do:** Implement the document, node, layout, paint and control model of `docs/specs/2026-11-03-skin-format-2-design.md` §2–§7 as a Decodable model with a preprocessor (tokens, typed part parameters, `use`), a validator (schema, `requires` vs content, limits of §11, overlapping hit frames, inputs vs game type), and the pure layout resolver of §4 (anchors, named areas, min/max/sum lengths, stacks, grids, repeat, `when`, `visible`, edits). Generate the JSON Schema from the model with a test that it validates every fixture. Add the `layout`, `stacks-grids`, `variants` and `dual-screen` fixtures with recorded `layout.json`. Port the spike's `gamecube.skin2.json` to the final schema as the `gamecube-icube` fixture.
>
> **Depends on:** #25 approved.
>
> **Done when:** `xcrun swift test` validates and resolves every fixture on macOS; the schema file is published; no UI code.

**2. Format 2.0: Swift renderer in SkinKitUI with reference images**

> **Where:** SkinKit `Sources/SkinKitUI/Rendering/Skin2/`, `Tests/Format2Fixtures/*/expected/`
>
> **Do:** A Core Graphics drawer for resolved trees (§5: fills, strokes with alignment, effects in the fixed order, materials as recipes, text as glyph outlines from a bundled OFL font, images) hosted in a SwiftUI `Canvas` through `withCGContext`, plus the control host (§6: frame hit testing, d-pad 3×3 zones, thumbstick travel and knob, touch surfaces, actions, states with the 80 ms scale transition, haptics) built from Provenance's `OverlayTouchCluster`. `SkinView` renders a bundle's `skin.json` when `format2` is present and all `requires` are supported, else the classic part. Record the expected PNGs for every fixture at 2× with a `--record` test flag and add the `shapes`, `paths`, `paint`, `strokes`, `effects`, `text`, `states` fixtures.
>
> **Depends on:** issue 1.
>
> **Done when:** every fixture renders within the §9.3 tolerances on iOS and tvOS simulators (`scripts/ci-test.sh`), the GameCube fixture's hit frames match the spike's test values, and the demo harness (`UITesting`) shows it.

**3. Format 2.0: TypeScript renderer for the website**

> **Where:** Provenance-Emu/skins `docs/js/skin2/` (`model.ts`, `layout.ts`, `render.ts`), `tests/skin2/`, vendored `fixtures/format2/`
>
> **Do:** Port the model, preprocessor, validator and resolver of §2–§7 and the drawer of §5 to Canvas 2D as ES modules (no bundler; `tsc` in CI). Text through opentype.js outlines with the same bundled font; shadows via an offscreen separable Gaussian (σ = radius/2); squircles with the shared cubic approximation. Vendor the SkinKit fixtures with a hash test and compare with `pixelmatch` at the §9.3 tolerances; compare `layout.json` exactly. Add a `/preview/?skin=<url>` page that renders a 2.0 skin on the iPhone and iPad canvases of §8.1 in both orientations, used by the editor and the RetroArch converter.
>
> **Depends on:** issue 1 (fixtures); runs in parallel with issue 2 once the expected images exist.
>
> **Done when:** `npm test` passes against every fixture; the preview page renders the GameCube skin identically to the SkinKit PNGs.

**4. Format 2.0: baker to classic skins (Swift and TypeScript)**

> **Where:** SkinKit `Sources/SkinKit2Bake/` and a `skinkit-bake` CLI target; skins `tools/skin2/bake.ts`
>
> **Do:** Implement §8: the trait-set table, per-trait resolution, vector background PDFs (rasterised effects at 3× per node), items with inputs/extendedEdges/thumbstick knobs, screens, themes → `themes`, variants → `gameOverrides`/`altRepresentations`/family bundles, `preview.png`, and the `format2` key. Swift via `CGPDFContext`; TS via pdf-lib with the shared path/paint emitter. Both write byte-identical `info.json`; PDF rasterisations compared at the parity tolerance. Add "Export as classic skin" to the SkinKitUI options sheet. Test: bake every fixture, load the result with `DeltaSkin` and `DeltaSkinValidator`, and diff the Swift and TS outputs.
>
> **Depends on:** issues 1–3.
>
> **Done when:** a baked GameCube bundle installs and plays in Delta and Manic (manual check, recorded in the PR) and in all three apps through their classic paths.

**5. Format 2.0: renderer parity CI across SkinKit and skins**

> **Where:** SkinKit `.github/workflows/`, skins `.github/workflows/`
>
> **Do:** A SkinKit workflow that runs the Swift fixture tests on macOS and iOS, then checks out `skins` and runs its TS fixture tests against SkinKit's fixture directory whenever `Tests/Format2Fixtures/` or the renderer changes; a skins workflow that fails when the vendored fixture hash differs from SkinKit `main`. Publish the diff images of failures as workflow artifacts. Document the `--record` flow (record in Swift, open a skins PR to update the vendored copy).
>
> **Depends on:** issues 2 and 3.
>
> **Done when:** a deliberate one-pixel change in either renderer fails CI with a diff image attached.

**6. iCube: generated pads as format 2.0 skins**

> **Where:** iCube `DolphiniOS/UI/Emulation/TouchOverlay/`, `DolphiniOS/UI/Emulation/Skins/`, bundled `Skins/*.deltaskin`
>
> **Do:** Replace `TouchOverlayDefaults`, `TouchOverlayArt`, `TouchOverlayGroupViews` and `TouchOverlayModel` with four 2.0 skins (GameCube from the spike file; Wii Remote, sideways, Classic from the xib-derived tables), baked and bundled, rendered by SkinKitUI's 2.0 view with `SkinOverlayInput` as the sink (`TCButtonType` table unchanged). Microphone as `visible: {flag: "microphone"}`; the IR surface as a `touchSurface`. Migrate `TouchOverlayLayoutStore` anchored centres to 2.0 edits on first launch. Snapshot tests (`TouchOverlaySnapshotTests`) compare the new rendering with the old on iPhone portrait/landscape and iPad landscape before the generator code is deleted.
>
> **Depends on:** issues 2 and 4.
>
> **Done when:** the four pads play unchanged, edits survive the migration, and the deleted Swift is gone from the target.

**7. Provenance: PVTouchOverlay families as format 2.0 skins**

> **Where:** Provenance `PVTouchOverlay/`, `PVUI/Sources/PVUIBase/SwiftUI/TouchOverlay/`, `PVUI/Sources/PVUIBase/Resources/DefaultSkins/`
>
> **Do:** A checked-in generator (`PVTouchOverlay/Tools/export-skins.swift`) that walks `SystemOverlayBindings.table` and writes one 2.0 skin per system (palette → tokens, family templates per orientation → one tree with `when` patches, `OverlayShape` → shape kinds, `toggledBy` → `visible` flags, `screenPolicy` → screen nodes, subtypes → `any` variants), using the `std.*` parts for the 18 families. Bake and bundle them in `DefaultSkins`. `ProgrammaticOverlayView` mounts SkinKitUI's 2.0 view with `OverlayInputSinkAdapter`; `OverlayLayoutStore` overrides migrate to edits. Delete the family builders, `OverlayArt`, `OverlayScreenPlanner` and `OverlayLayoutEngine` once the per-system snapshot tests pass.
>
> **Depends on:** issues 2 and 4; issue 6 first (smaller proof).
>
> **Done when:** every bound system renders its default controller from a bundled 2.0 skin, the per-game/per-system variant choice still works, and the package only holds input dispatch and the editor.

**8. iFly: Dreamcast and arcade overlays as format 2.0 skins**

> **Where:** iFly `Sources/UI/Views/Controller/`, `Sources/Core/Skins/`
>
> **Do:** Two 2.0 skins (Dreamcast console, arcade) replacing `ConsoleOverlayLayout`, `VirtualControllerOverlay.consoleLayout`, `ArcadePortraitLayout`/`ArcadeLandscapeLayout` and `ControllerArtKit`: the centre arithmetic as anchors and stacks, the three `ControllerButtonStyle`s as themes, the arcade palette as a theme, bundled `ifly.ctrl.*` images as `image` nodes. Keep `EmulationView.emulatorFrame` fed from the skin's screen node. Migrate `ButtonLayoutStore` normalised centres to edits. Snapshot tests before deletion.
>
> **Depends on:** issues 2 and 4.
>
> **Done when:** both overlays and all three styles render from skins, the style picker switches themes, and the generator views are deleted.

**9. Format 2.0: website docs and wiki**

> **Where:** skins `docs/format/` (new section on emuskins.com), SkinKit wiki
>
> **Do:** A reference generated from `docs/schema/skin-2.0.schema.json` (every node type, field, shape kind, paint, effect, condition, with a live preview per example using the TS renderer), a tutorial that builds the GameCube skin from the standard parts, the bake and `requires` rules for app developers, and a "convert your generated controller" page for emulator authors. Wiki: a short overview linking to the site, and the fixture/record workflow for contributors.
>
> **Depends on:** issues 3 and 4 (live previews, bake examples).
>
> **Done when:** every schema key appears in the reference (checked by a script), and the tutorial's final file validates and renders.

**10. Catalog: accept format 2.0 skins**

> **Where:** skins `link_health.py`, `catalog.json` schema, `docs/js/browse.js`
>
> **Do:** Detect `skin.json` + `format2` in a bundle, validate it with the TS validator, re-bake with the TS baker and diff `info.json` (hide the entry on mismatch, like missing artwork), set `format2: true` on the catalog entry, and show a "Responsive" badge with the live preview on the skin page. Keep `catalog.json` flat; old apps ignore the field.
>
> **Depends on:** issues 3 and 4.
>
> **Done when:** the baked GameCube skin is listed, installs in Delta through the catalog, and a tampered copy is hidden by the health check.

## Open questions (left to the builder)

- The trait-set canvases in §8.1 are a first cut; the baker's PR should check them against the sizes Delta actually picks per device and adjust.
- Whether `squircle` needs to match SwiftUI's `.continuous` exactly in the Swift renderer or both renderers use the shared approximation (the design says shared; revisit if designers notice).
- tvOS: 2.0 skins render with no controls (focus-driven UI); whether a skin may declare a tv-only layout with `when: {device: tv}` for the pointer is decided when a tv skin exists.
- Font licensing for the bundled default (an OFL face such as Inter or Atkinson Hyperlegible); pick in issue 2.
