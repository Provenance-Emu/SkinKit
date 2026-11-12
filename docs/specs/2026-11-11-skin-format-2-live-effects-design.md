# Skin format 2: live effects (design)

Date: 2026-11-11. Status: approved by the owner 2026-11-11, as drafted. Nothing here is built.

Extends [`2026-11-03-skin-format-2-design.md`](2026-11-03-skin-format-2-design.md) ("the 2.0 design"; section numbers such as §5.3 refer to it). It is "Piece 3" of Provenance's `docs/superpowers/specs/2026-11-11-external-display-tv-bezels-design.md`.

## Why

Format 2 describes a skin as a static tree. The game picture is a hole the app fills, nothing moves except pressed buttons, and no node can see the picture. Provenance now draws TVs around the picture on an external display, and it had to keep half of each TV outside the format: the cabinet is a format 2 document, but the glass, the reflections, the room light and the tube look are numbers in a separate catalogue that only Provenance's code understands.

The format is not published yet, so it can grow before anyone depends on it. This design adds what a skin needs to put the game inside its artwork and react to it: the live picture as an input, effects on and around it, values that follow the game and the device, and simple animation.

## Who decided what

The owner decided (2026-11-11): the format may grow because it is unpublished; it may gain Core Image filters, embedded shaders, glow, reflection, ambient and screen effects, and effects driven by the camera, face detection and gyro; the emuskins site and its docs change with it. He delegated the shader rule, and the call recorded then was: shaders only as compiled slang presets, compiled by the site, declared by the skin, with no scripting.

The owner then asked for this draft without a round of questions, and approved it as drafted. Every other choice below was the builder's and is listed under "Calls I made".

## What exists today (checked 2026-11-11)

- **SkinKit** (`main` at `fc3a6cc`): `SkinKit2Core` (model, validator, resolver), `SkinKit2Render` (one Core Graphics drawer; `Skin2Renderer.image` returns a `CGImage`), `SkinKit2Bake`. A `screen` node is not drawn; apps put their video in its frame. `Skin2Effect` has a `ci` type, but neither renderer runs it and `effects.ci` is not in either renderer's supported set, so a skin that lists it falls back to its bake. A screen node carries classic `filters` only so the baker can copy them into `info.json`.
- **skins** (`main`): the TypeScript renderer, baker and validator are in `docs/js/skin2/`, the vendored fixtures in `fixtures/format2/`, and the format's pages in `docs/format/` (`index`, `reference`, `tutorial`, `examples`, `playground`, `migration`, plus a copy of the schema).
- **Provenance** (`develop` at `ceb014c192`): `TVBezelCatalog` reads `Resources/TVBezels/catalog.json`. Each TV names a format 2 document (the cabinet and room, with one `screen` node, the tube) and carries `frame` (values for a `bezel/uborder` slang preset), `look` (a filter id and values), `lightsRoom` and `preferredSystems`. `TVBezelShader` turns the tube's rect into the preset's geometry parameters (`fr_zoom` is the tube's height as a percentage of the scene's width). Drawing is two stages: the screen filter into a tube-sized texture, then the bezel preset over the 16:9 scene with the rendered cabinet as its `BORDER` texture.
- **Delta screen filters in Provenance**: `PVMetalViewController.skinFilteredFrame` runs a classic skin's `filters` through Core Image over the core's frame at native resolution (`FrameImageFilter`, `DeltaSkinScreenFilter.run`). A filter the player picks replaces them.
- **A "compiled slang preset" is not machine code.** `PVSlangRuntime`'s container is a directory with `shader.json` (passes, parameters, LUT list) and one `<NAME>__<file>` image per LUT. Each pass holds generated Metal Shading Language text (slang → SPIR-V → MSL), which `MTLDevice.makeLibrary(source:)` compiles on the device. The bezel-only uborder preset is 53 KB of JSON plus 366 KB of textures.
- **Signal sources that already exist in Provenance**: the thin libretro front end answers `GET_LED_INTERFACE` (cores report drive lights), `GCControllerHapticsManager` knows what rumble the game asks for, and the camera and motion usage strings are in the Info.plists. Nothing measures the audio level or the picture's colours yet.

## Goals

- A skin places the game inside its artwork: art over the picture, and the picture reused elsewhere (a reflection, a glow on the wall).
- A skin reacts: lights and layers follow the picture, the sound, rumble, disk and save activity, and the device's motion.
- A skin moves a little by itself: a warm-up, a flicker, a pulsing light.
- A skin can give its screen a look, with Core Image filters or a shader, and can run a shader over a scene (glass, reflections, room light).
- Provenance's three built-in TVs become one format 2 file each, and adding a TV is adding a file.
- The Swift and TypeScript renderers still agree on fixtures for everything they both draw.

## Non-goals

- Scripting, and expressions beyond the value forms in §3 below. A value is a constant, a mapped signal, an animation, a flag switch or a measured length. Nothing combines them.
- Shader source a person wrote (slang, GLSL, MSL, Core Image kernels) running on a device unchecked.
- Timelines, sprite sheets, video, particles, physics, or animated layout. Animation changes how a finished layer is composited, never where nodes are laid out.
- Audio output from a skin.
- Sharing display skins (TVs) through the emuskins catalogue. A TV has no controls and no classic equivalent, so it needs its own bundle and bake rules. That is a later, separate design.
- Running slang shaders in the site's TypeScript renderer.

## Anti-goals (failure even if it works)

- A skin that costs frames. The game's frame rate comes first; a live effect that cannot keep up is switched off, and the skin is drawn without it.
- A skin that shows a broken controller when a live feature is missing. Every skin must be acceptable as its static tree.
- A skin that learns something about the player and can pass it on. Signals flow into drawing only; a skin has no network, no storage and no output but pixels.
- The camera running without the player having said yes in the app, for that purpose.
- Two renderers that drift on what both claim to draw.
- A flashing skin. Fast, strong flicker is rejected by the validator.

## Design

### 1. A frame is a function of its inputs

Today a skin is drawn once per environment. With live effects it is drawn per frame, and a frame is fully defined by four inputs:

| Input | What it is |
|---|---|
| Environment | canvas, safe area, device, flags (unchanged, 2.0 §4) |
| Pictures | one image per screen node: the game's current frame |
| Clocks | three times in seconds (§4 below) |
| Signals | a table of named numbers and colours (§5 below) |

Given the same four inputs both renderers must produce the same pixels for everything they both support. That is what keeps the fixture promise: a fixture pins the inputs.

The **rest frame** is the frame with no pictures, every clock at "finished" and every signal at its rest value. Static contexts draw the rest frame: the baker, catalogue thumbnails, the editor's canvas, and any app that lacks a live feature.

**Layers.** Layout is untouched: the resolver runs as in 2.0 and nothing live can move or resize a node's resolved frame. A new pure step, the **live plan**, walks the resolved tree in draw order and cuts it into layers:

- a **static layer**: a run of nodes with nothing live in them, drawn once by the existing drawer and kept;
- a **live layer**: a node with a `live` block, a picture paint, or an effect with a live value. Its subtree is drawn once and kept; its live values are applied each frame when it is composited;
- a **screen**: the picture, through the screen's effects;
- a **shader group**: a group with a scene shader (§7 below).

Live layers nest (opacities multiply, transforms compose), three deep at most. The plan is data: it lives in `SkinKit2Core` and in the TypeScript model, and both are tested against the same recorded plans.

### 2. The picture in the tree

**Draw order (`screen.overlay`).** A screen node is drawn where it stands in document order. Nodes after it are drawn over the picture: glare on the glass, a cabinet lip that overlaps the tube's edge, scan-line art. Every 2.0 skin written so far keeps working, because none overlaps its screen. A host that shows the game in its own view splits the plan at the screen into an under part and an over part.

**The shown picture.** A screen's frame is the budget the game is fitted into (2.0 §4.8). As soon as a screen has effects, or another node uses its picture, the screen's *shown picture* is the whole frame: the game fitted inside it over black, then the screen's effects. Bars inside the glass are correct, as on a real set.

**Picture paint (`paint.picture`).** A new paint type, allowed in a shape's `fills`:

```json
{ "type": "picture", "screen": "#tube", "fit": "stretch", "flip": "y", "blur": 24, "gain": 1.2, "opacity": 0.35 }
```

| Key | Type | Notes |
|---|---|---|
| `screen` | `#id` | which screen; default the first |
| `fit` | `stretch` \| `fill` \| `fit` | how the shown picture maps onto the shape's frame; default `stretch` |
| `flip` | `none` \| `x` \| `y` \| `xy` | mirror, for reflections |
| `blur` | L | Gaussian, σ = radius / 2, applied after the picture is scaled to the frame; at most 200 pt |
| `gain` | number or live value | multiplies RGB, clamped; default 1 |
| `opacity` | 0–1 or live value | |

The shape clips it, and the shape's other fills and strokes draw under and over it in listed order. With the existing `blend` effect this covers a reflection on a frame (flipped, blurred, low opacity), a glow on the wall (a large blurred ellipse, `plus`), and a second, smaller copy of the game. A shape with a picture paint is a live layer. At most four picture paints per skin.

In the rest frame a picture paint draws nothing. A renderer that is handed a still image as the picture (a fixture's test card, the playground's sample) draws it, so the paint is covered by fixtures in both renderers.

### 3. Live values and the `live` block

A **live value** stands where a number or a colour is allowed, in the places this document names. It is one of:

| Form | Example | Evaluated |
|---|---|---|
| constant | `0.4`, `"#FF2020"` | never |
| signal → number | `{"signal": "audio.level", "in": [0, 1], "out": [0.3, 1], "curve": "easeOut"}` | per frame |
| signal → colour | `{"signal": "audio.level", "out": ["#200000", "#FF3030"]}` or `{"signal": "picture.edge.left", "gain": 1.4}` | per frame |
| animation | `{"animate": {…}}` (§4) | per frame |
| flag switch | `{"flag": "flatGlass", "then": 0, "else": 1}` | at layout |
| measure | `{"measure": ["#tube", "height"], "over": ["canvas", "width"], "scale": 100, "add": 0}` | at layout; shader parameters only |

A signal binding clamps the signal into `in` (default `[0, 1]`), applies `curve` (`linear`, `easeIn`, `easeOut`, `easeInOut`, `step`) and maps onto `out`. Colours interpolate in sRGB, as gradients do. A binding is a pure map: smoothing belongs to the signal (§5), so a frame never depends on the frames before it. `measure` divides one resolved length (`x`, `y`, `width`, `height`, `midX`, `midY` of a node, or `width`/`height` of `canvas`) by another, then scales and adds. It exists so a shader can be told where a screen is without the skin repeating the screen's frame as numbers.

Forms do not combine. To multiply two (a warm-up times a flicker), nest two layers.

**The `live` block (`live`).** Any node may carry one. The node becomes a live layer, and these apply when it is composited:

```json
"live": { "opacity": {"signal": "activity.disk", "out": [0.15, 1]},
          "tint": {"signal": "picture.average", "gain": 1.3},
          "offset": [{"signal": "motion.tilt.x", "in": [-1, 1], "out": [-6, 6]}, 0],
          "scale": 1, "rotate": 0 }
```

`opacity` multiplies the node's opacity. `tint` multiplies the layer's colour. `offset` is in points at reference scale; `scale` and `rotate` (degrees) are about the frame's centre. Hit frames never move: a control with a `live` block is still hit-tested on its resolved frame.

Live values are also allowed in a picture paint's `gain` and `opacity`, in the `params` of `ci` and `shader` effects, and nowhere else. A skin holds at most 64 of them and 16 live layers.

### 4. Animation (`live.animate`)

Two kinds, both pure functions of a clock:

```json
{ "animate": { "clock": "gameStart", "keyframes": [[0, 0], [0.35, 1.25, "easeOut"], [1.2, 1]], "repeat": "once" } }
{ "animate": { "clock": "run", "wave": "noise", "period": 0.9, "min": 0.94, "max": 1, "seed": 7 } }
```

- **Keyframes**: `[seconds, value, curve into this keyframe?]`, 2 to 16 of them, times rising. `repeat` is `once` (holds the last value), `loop` or `pingPong`. Values are numbers or colours.
- **Waves**: `sine`, `triangle`, `square` or `noise` between `min` and `max` with a `period` in seconds and an optional `phase` (0–1). `noise` is value noise, specified exactly so both renderers agree: with `i = floor(t / period)` and `f` its fraction, the value is `mix(h(i), h(i + 1), f·f·(3 − 2f))`, where `h(n)` is the 32-bit hash `lowbias32(seed · 0x9E3779B9 + n)` divided by 2³².

**Clocks.** `appear` counts from when the skin appeared on this display, `gameStart` from the game's first frame (it restarts on reset), `run` is total running time. All three stop while the game is paused, so a paused skin is still and costs nothing. In the rest frame, `once` animations are finished and loops and waves sit at phase 0.

**Flashing.** The validator rejects a loop or wave on `opacity`, `tint` or `gain` that repeats more often than three times a second and changes the value by more than 0.1. A CRT flicker of a few percent passes; a strobe does not. When the system's Reduce Motion or Dim Flashing Lights setting is on, the host draws the rest frame's values for every animation and for the motion and viewer signals.

### 5. Signals

A signal is a named value the host supplies each frame. The host smooths it with the time constant given here, so skins look the same in every app. A signal the host does not have (feature missing, permission refused, sensor absent) holds its rest value, and the skin is not told why.

| Signal | Type | Rest | Meaning | Smoothing | Feature |
|---|---|---|---|---|---|
| `picture.average` | colour | black | mean colour of a screen's shown picture | 150 ms | `signals.picture` |
| `picture.edge.left` `.right` `.top` `.bottom` | colour | black | mean colour of the outer eighth along that edge | 150 ms | `signals.picture` |
| `picture.luma` | 0–1 | 0 | mean Rec. 709 luma | 150 ms | `signals.picture` |
| `audio.level` `audio.left` `audio.right` | 0–1 | 0 | RMS of the game's output over 50 ms; −60 to 0 dBFS maps linearly to 0–1 | 30 ms up, 250 ms down | `signals.audio` |
| `rumble` | 0–1 | 0 | the strongest motor the game is driving for player 1 | 30 ms up, 150 ms down | `signals.rumble` |
| `activity.disk` | 0 or 1 | 0 | the core reports media access (libretro LED interface, or a native core's own report) | held at least 100 ms | `signals.activity` |
| `activity.save` | 0 or 1 | 0 | a battery save or save state is being written | held at least 250 ms | `signals.activity` |
| `game.running` | 0 or 1 | 1 | 0 while paused | none | `live` |
| `motion.tilt.x` `motion.tilt.y` | −1 to 1 | 0 | the device's tilt from the pose it had when the skin appeared; 30° is 1 | 100 ms | `signals.motion` |
| `viewer.x` `viewer.y` | −1 to 1 | 0 | where the player's head is, relative to the middle of the device's screen | 150 ms | `signals.viewer` |
| `viewer.distance` | 0–1 | 0.5 | near to far, 25 cm to 75 cm | 150 ms | `signals.viewer` |

Picture signals take an optional `"screen": "#id"` in the binding; the default is the first screen. Hosts sample them from a copy of the picture no larger than 32×32, at least ten times a second.

**Permission, in three tiers.**

1. **From the game itself** (picture, audio, rumble, activity, running): no permission. The values never leave the renderer.
2. **Device motion**: iOS has no prompt for it. The skin must list `signals.motion`, the app shows "uses motion" in the skin's details, and one app setting turns motion off for all skins. On by default; off while Reduce Motion is on.
3. **The viewer (camera)**: needs the system's camera permission *and* an app setting, "Head tracking for skins", which is off by default. The first time a player selects a skin that lists `signals.viewer`, the app asks whether to turn it on, saying the camera is used to find the position of their head, on the device, and nothing is stored or sent. The camera runs only while such a skin is on screen and the game is running. Frames are reduced to three numbers on the device and dropped. It is never used on an external display (the camera cannot see where the viewer is relative to that display) or on tvOS.

`signals.motion` and `signals.viewer` may only be listed as optional (§8 below): a skin must not depend on something the player can refuse.

### 6. Core Image effects (`effects.ci`)

The 2.0 design named `{ "type": "ci", "name", "params" }` and left it unbuilt. This design defines it in three places, Apple platforms only:

- **On a screen**: the entries run on the picture, in order. This is where a Delta skin's screen filters live.
- **On a live layer or picture-paint shape**: they run each frame when the layer is composited, after its live values.
- **On a static node**: they run once when the layer is drawn, and the Swift baker bakes them in.

**Parameters** take the forms classic screen filters take (`DeltaSkin.FilterInfo`: numbers, vectors, points, rects, colours), a live value where the filter wants a number or a colour, and three image forms for filters with a second image input (`CIBlendWithMask`, `CIDisplacementDistortion`): `{"src": "assets/…"}`, `{"picture": "#id"}` and `{"content": true}` (the node's own drawn content). Any built-in Core Image filter may be named. A filter or key Core Image does not have is skipped and logged once, as the classic path does since SkinKit #147. Filters that need a model, a URL or code cannot be configured from JSON and so cannot be used.

**Delta `filters` map one to one.** A screen node's `filters` key stays, and is defined as shorthand: its entries are `ci` effects that run before the node's `effects`. The baker writes every `ci` entry of a screen, from either key, into the classic `filters` (as `{name, parameters}`), so a round trip through the baker loses nothing. A classic skin converted to format 2 keeps its `filters` as they are. A screen's effects are never drawn into the baked background (a screen is not part of it); only `ci` effects on other static nodes are baked into the artwork, as 2.0 §8.2 says.

**Order on a node that is not a screen.** 2.0 §5.3 fixes the order of shadows, content, blur and blend. `ci` entries, then a `shader` entry, run after blur and before blend, each in listed order.

**The screen's pipeline.** On a screen the list runs in listed order. The game is fitted into the frame; `ci` effects run at the resolution of their input (so classic filters still see the core's native frame); a `shader` effect outputs at the screen's size in display pixels; later entries see that output.

**The player's filter wins.** When the player has chosen a filter for that display, it replaces the screen's own `filters` and `effects`, as it replaces a classic skin's filters today. Scene shaders (§7) are not replaced. "The TV's Own" in Provenance's picker means the screen node's own list.

### 7. Shader effects (`effects.shader`)

**Where a preset comes from.** A skin names presets in a document-level table and uses them by name:

```json
"shaders": {
  "look":  { "preset": "library:crt/crt-aperture" },
  "glass": { "preset": "library:bezel/uborder/preset_tools/append-uborder-bezel-reflections",
             "when": [ { "flag": "roomLight", "preset": "library:bezel/uborder/uborder-koko-ambi" } ] },
  "mine":  { "preset": "bundle:shaders/mine" }
}
```

- `library:<id>` is a preset in the app's own slang library, by its libretro slang-shaders path: the ids of the `JoeMatt/slang-shaders-metal` release the app bundles (Provenance's `ShaderID.slang(<id>)`). Nothing is carried in the skin. This is the normal case and what the built-in TVs use. An app's hand-written filters (Provenance's native Metal ones) are not in that library and cannot be named by a skin, because no other app has them.
- `bundle:shaders/<name>` is a preset carried in the skin (below).
- `when` switches the preset on a condition (same conditions as node `when`, 2.0 §4.6), so one effect entry serves two presets that share parameters. The entry resolves to the last matching `when` whose preset the host has, else to the base preset, and only when that is missing too does the effect not run. A parameter the resolved preset does not declare is ignored, so the effect can carry values for both.
- The site's validator needs the library's preset ids and parameter ranges. The `skins` repository pins the same release tag Provenance does (`Scripts/shaders/slang-shaders.lock.json`) and generates `docs/format/shader-library.json` from it; a preset an older app's library lacks simply does not run there.

**The effect.**

```json
{ "type": "shader", "shader": "glass", "source": "#tube",
  "params": { "bz_red": 22, "bz_ref_str": 0.3,
              "h_curvature": {"flag": "flatGlass", "then": 0, "else": 1},
              "fr_zoom": {"measure": ["#tube", "height"], "over": ["canvas", "width"], "scale": 100} },
  "textures": { "BORDER": {"content": true} } }
```

| On | Its `Source` is | Its output covers |
|---|---|---|
| a screen | the picture, after earlier effects | the screen's frame |
| a group (or the root) with `source: "#screen"` | that screen's shown picture; the screen must be inside the group and is not drawn on its own | the group's frame |
| a group, shape, image or text without `source` | the node's own drawn content | the node's frame |

- On a group, the shader's output replaces the group's content. The content (everything in the group except the source screen) is available to the shader as a texture through `{"content": true}`. It is composited from the group's own layers: once, when nothing in it is live, and again each frame when it holds a live layer, which costs a few layer blits and no redrawing. So a pulsing light inside a TV's scene pulses, and the glass reflects and dims it like the rest of the cabinet.
- Everything inside a shader group is the shader's input, including nodes after the screen. Art that must sit over the shader's output (glare that the glass should not bend) goes in a sibling after the group, so a scene with such art puts its shader on a child group, not on the root.
- A scene shader's output is the group's frame in the skin's canvas. The host scales the canvas into the display as it does today (Provenance letterboxes the 1920x1080 `tv` canvas on a display that is not 16:9), so `measure` values, which are ratios of resolved canvas lengths, hold on every display.
- `params` are the preset's parameters by name. Values are clamped to the range the preset declares. A name the preset does not declare is ignored (a validator warning where the validator can see the preset; an error on the site, which has the library's manifest).
- `textures` binds the preset's LUTs by name to `{"content": true}` or `{"src": "assets/…"}`. An unbound LUT uses the preset's own file.
- The host supplies the standard slang inputs: `Source`, `Original`, `OutputSize`, `FinalViewportSize` (both the output in pixels), `FrameCount` (the `run` clock × 60, whole), history and feedback as the runtime supports.
- A preset written for a whole display, as the bezel presets are, sees its output rect as the display. It goes on the root or on a group that is the scene.
- At most one shader effect per screen and two elsewhere in a skin.

**A preset in the bundle.**

```
MySkin.deltaskin/
  skin.json
  shaders/
    mine/
      shader.json        the compiled preset, in the container PVSlangRuntime loads
      NOISE__noise.png   one file per LUT, named <LUT name>__<file name>
      source/            the slang it was compiled from (.slangp, .slang, includes)
```

Authors never upload `shader.json`. They submit slang source with the skin; a macOS job in the `skins` repository compiles it with the toolchain that builds the app's library (`oeshaders`), checks the limits, renders it on the runner's GPU against a test card, and writes the compiled files into the bundle. A person reviews the slang in that pull request before it merges.

**Approval list.** Because the container holds generated Metal source that the device compiles, "compiled by the site" has to be something an app can check. emuskins publishes `https://emuskins.com/shaders/approved.json`: the SHA-256 of every approved `shaders/<name>/` directory (sorted paths, each as path, length and bytes, `source/` excluded), with the skin's identifier and the date, plus a `revoked` list. `SkinCatalogKit` fetches it with the catalogue and each app build bundles a snapshot. An app runs a bundled preset only when its hash is on the list and not revoked. Otherwise the effect does not run, the reason is logged once, and the skin's details say so. Each app may offer authors a developer switch, "Run unapproved skin shaders", off by default.

**What a shader can and cannot do.** It runs on the GPU. It cannot read files, use the network or run CPU code. It reads only the textures bound to it (the picture, the skin's own art, its own LUTs) and writes pixels to the screen. The real risks are wasted GPU time, which the budget in §9 handles, and bugs in the shader compiler or driver, which is why source is reviewed, only the site's compiler output is accepted, and an approved hash can be revoked.

**Limits for a bundled preset**: two per skin; 8 passes; `shader.json` at most 512 KB; 8 LUTs, each at most 2048 px a side and 4 MB; `shaders/` at most 12 MB, `source/` at most 1 MB; 2 frames of history; 128 parameters; no pass target larger than 4096 px a side or more than twice the output's pixel count. Library presets ship with the app and are bound only by the runtime budget.

### 8. `requires`, `optional` and the new feature names

`requires` keeps its meaning: a reader that lacks one entry draws the baked classic skin. A new document key, `optional`, lists features the skin uses when they are there. A reader that lacks an optional feature draws the skin without it. The validator checks that every feature the content uses is in one list or the other.

| Feature | Covers |
|---|---|
| `screen.overlay` | nodes after a screen draw over the picture |
| `paint.picture` | picture paints |
| `live` | `live` blocks, flag-switch values, `game.running` |
| `live.animate` | keyframes and waves |
| `signals.picture`, `signals.audio`, `signals.rumble`, `signals.activity` | those signal groups |
| `signals.motion`, `signals.viewer` | optional only |
| `effects.ci` | Core Image effects (now built) |
| `effects.shader` | shader effects with library presets, `measure` values |
| `effects.shader.bundled` | presets carried in the bundle |

The live features belong in `optional` unless the skin is truly unusable without one. Listing one in `requires` only changes what happens on a reader that lacks the feature. A failure at run time (a preset is missing, unapproved or over budget; a permission is refused) always ends in the skin drawn without that effect, never in the bake. This changes one sentence of 2.0: a skin that uses `effects.ci` no longer has to list it in `requires` and so no longer falls back to its bake in the browser; listed as optional, it is drawn there without the filters.

**Display documents.** A TV is a bare `skin.json` the host loads itself. It is not a bundle and has no bake. A new document key marks it:

```json
"display": { "prefers": ["com.provenance.c64", "com.provenance.dos"] }
```

A document with `display` is a display skin: art around one or more screens, for the `tv` canvas. The validator skips the checks that only make sense for controllers (the required bake families, control sizes, inputs against game types), requires at least one screen, and rejects controls. It is never baked. `prefers` lists the systems it is the natural screen for; it ranks, it never restricts, and any display skin may be used with any system. On a reader that lacks one of its `requires`, the host does not offer it. How display skins are bundled and listed on emuskins is the later design named under Non-goals; this key is the part of it the built-in TVs need now.

`formatVersion` stays `"2.0"`. No reader of 2.0 has shipped, so these are additions to 2.0 before it is published, not a 2.1.

### 9. When an effect cannot run, and what it may cost

Each effect fails on its own and always in the same direction, toward the static tree:

| Cannot run | Drawn instead |
|---|---|
| shader on a screen | the picture through the rest of its effects |
| scene shader on a group | the group's content, with the screen's picture in the screen's frame |
| `ci` entry | the list without it |
| picture paint | nothing in its place |
| signal | its rest value |
| animation (Reduce Motion) | its rest value |

**Budget.** The live compositor measures GPU time per frame. If the median over two seconds is above a quarter of the display's frame time, it switches off, in order, scene shaders, screen shaders that came from the skin, blurred picture paints, then everything live, and stays that way for the session. The host also draws the rest frame in Low Power Mode and when the device reports a serious thermal state. The game's own frame is never delayed for a skin.

### 10. What each renderer and the baker does

| Feature | Swift static drawer and baker | Swift live compositor | TypeScript renderer and baker |
|---|---|---|---|
| `screen.overlay` | draws over the placeholder; bakes over-art into the background (classic apps put their video on top) | composites over the picture | same as Swift static |
| `paint.picture` | draws a supplied still; nothing in the rest frame and in bakes | the live picture | same as Swift static; the playground supplies a sample |
| `live`, `live.animate`, signals | evaluates a given frame; the rest frame by default and in bakes | every frame | same as Swift static; the playground has a time scrubber and signal sliders |
| `effects.ci` | applied; baked in | applied | skipped |
| `effects.shader` | skipped | run through the host's runner | skipped |
| classic `filters` | written to `info.json` from every screen `ci` entry | run as `ci` | written to `info.json` identically |

Both bakers still write byte-identical `info.json`. Classic skins get the rest frame.

**Fixtures.** A fixture may add `frames.json`: named frames, each giving clocks, signal values and a picture (a test card in the fixtures folder). Expected images are recorded per trait and frame (`expected/<trait>@<frame>@2x.png`), and the plan is recorded as `expected/<trait>.plan.json`. New fixtures: `picture-paint`, `screen-overlay`, `live-values`, `animate` (keyframes, each wave, the noise function at fixed times), `signals`, and `tv` (a cabinet with a tube, glare over it and a glow behind it). Tolerances are those of 2.0 §9.3; blurred picture paints use the 1.0 % effects tolerance. `effects-ci` is recorded and checked in Swift only, marked in the fixture manifest. Shader effects are tested in Swift against a fake runner (bindings, clamping, fallbacks); real preset rendering is tested where the runtime is, in Provenance.

### 11. Where the code goes

- **`SkinKit2Core`**: the model and schema additions, validator rules and limits, the live plan, and frame evaluation (live values, animation, the noise function). Pure, tested on macOS, ported to `skins/docs/js/skin2/`.
- **`SkinKit2Render`**: the drawer takes a frame (clocks, signals, still pictures) and applies `ci` effects on Apple platforms.
- **`SkinKit2Live`** (new, Apple only, Core Image and Metal): the per-frame compositor. It is given the plan, a Metal texture per screen, the clocks and the signals, and draws the under part, the over part or the whole skin into a texture. Picture paints, live values and `ci` effects are a Core Image graph over cached layers. It holds the budget logic.
- **Host protocols** in `SkinKit2Live`: `Skin2ShaderRunner` (given a preset reference, source texture, parameter values and texture bindings, draw into a target) and `Skin2SignalSource`. SkinKit does not contain a slang runtime. Provenance implements the runner with `PVSlangRuntime`; an app without one does not list `effects.shader` as supported.
- **`SkinCatalogKit`**: fetches and caches the approval list.

### 12. Provenance's TVs as one file

Each catalogue entry folds into its skin document:

| Catalogue field | Becomes |
|---|---|
| `id` | the file's name; `identifier` stays `org.provenance-emu.tv.<id>` |
| `name` | `name` |
| `preferredSystems` | `display.prefers` (§8); `gameTypes` stays `["org.provenance-emu.tv"]` as in today's files |
| `artwork` | the file itself |
| `frame` values | `params` of a scene shader effect on the root, with `source: "#tube"` and `"BORDER": {"content": true}` |
| `lightsRoom` | a `when: [{flag: "roomLight", preset: …koko-ambi}]` on the `glass` shader; a TV that should not light the room has no such entry |
| `look` | a `shader` effect on the tube's screen node |
| `TVBezelShader.geometryValues` | two `measure` values (`fr_zoom`, `fr_aspect_x`) and constants (`fr_aspect_y`, the centre parameters at 0) in `params` |
| `TVBezelShader.neutralTubeValues` | constants in `params`; the bezel-only preset ignores them |
| the flat-glass rule | `"h_curvature": {"flag": "flatGlass", "then": 0, "else": 1}` |

The Studio Monitor, shortened:

```json
{ "formatVersion": "2.0", "identifier": "org.provenance-emu.tv.studio-monitor", "name": "Studio Monitor",
  "gameTypes": ["org.provenance-emu.tv"], "display": { "prefers": [] },
  "requires": ["shapes.parametric", "paint.gradients", "effects.shadow", "text", "layout.repeat"],
  "optional": ["effects.shader", "live", "live.animate", "signals.activity"],
  "reference": { "shortSide": 1080, "minScale": 1, "maxScale": 1 },
  "shaders": {
    "look":  { "preset": "library:crt/crt-aperture" },
    "glass": { "preset": "library:bezel/uborder/preset_tools/append-uborder-bezel-reflections",
               "when": [ { "flag": "roomLight", "preset": "library:bezel/uborder/uborder-koko-ambi" } ] } },
  "root": { "type": "group",
    "effects": [ { "type": "shader", "shader": "glass", "source": "#tube",
                   "textures": { "BORDER": {"content": true} },
                   "params": { "bz_red": 22, "bz_green": 23, "bz_blue": 26, "bz_middle_bezel_x": 0.075, "bz_ref_str": 0.3,
                               "h_curvature": {"flag": "flatGlass", "then": 0, "else": 1}, "AMBI_POWER": 0.7,
                               "fr_zoom": {"measure": ["#tube", "height"], "over": ["canvas", "width"], "scale": 100},
                               "fr_aspect_x": {"measure": ["#tube", "width"], "over": ["#tube", "height"], "scale": 8},
                               "fr_aspect_y": 8, "CN_MASK_STRENGTH": 0 } } ],
    "children": [
      { "type": "shape", "id": "wall", "…": "the room and cabinet, as today" },
      { "type": "shape", "id": "tally", "…": "the tally light",
        "live": { "opacity": {"animate": {"clock": "run", "wave": "sine", "period": 2.4, "min": 0.7, "max": 1}} } },
      { "type": "screen", "id": "tube", "layout": {"frame": [456, 162, 1008, 756]},
        "effects": [ { "type": "shader", "shader": "look" } ] } ] } }
```

Without `effects.shader` this draws the cabinet with the game in the tube, which is a usable TV.

**What it means for `TVBezelCatalog`.** `catalog.json` shrinks to version 2: an ordered list of file names. `TVBezel` becomes a thin view over a `Skin2Document` (id, name, preferred systems). `TVBezelScene` stops building a `ResolvedShader` from catalogue values and asks SkinKit for the live plan; `presentOnExternalOutput` runs that plan through `SkinKit2Live` with Provenance's shader runner. `TVBezelShader` keeps only the app's rules about the player's filters (which library filters draw their own bezel, which parameters switch a filter's own curvature off) and loses `presetID`, `geometryValues`, `neutralTubeValues` and `values`. Provenance sets two flags and never overrides a skin's shader parameters by name: `roomLight` (from "Light the Room") and `flatGlass` (set when the filter in the tube bends the picture itself and cannot be told not to). Its other curvature rule, switching off a library filter's own curvature inside a TV, acts on the player's filter, which is the app's, not the skin's. If the library lacks the room-light preset, the `glass` entry resolves to its base preset (§7), which is today's behaviour. The stored setting values (`studio-monitor`, …) do not change. An imported RetroArch bezel (piece 2 of the TV design) is written by the importer as a format 2 document with an `image` node and a `screen` node, so imported and built-in TVs are the same kind of thing.

### 13. Where it runs first

The format does not distinguish displays: a live skin is valid on a phone, a tablet, a TV or an external display. The rollout does.

1. **Provenance's external display TVs.** The two-stage GPU path already exists there and the compositor owns the picture. This is where the TVs fold into one file.
2. **Skins on the device.** The game stays in the app's own view, so the compositor draws an under part and an over part around it and receives the picture as a texture for picture paints and signals. Provenance's device-side skin code has some 35 places that move or re-frame the GPU view, so this is its own piece of work with its own short design. Until then a live skin on the device draws its rest frame, with controls working as now.
3. **iCube and iFly** get `live`, animation, signals, picture paints and `ci` through `SkinKit2Live` when they adopt it. Shader effects need a slang runtime, which only Provenance has.

Dual-screen layouts, and cores that present on their own surface (Dolphin, Azahar, native PPSSPP), give the host no picture texture. For those, picture paints, picture signals and screen effects are unavailable and fall back as in §9; the rest still works.

### 14. Changes to the text of the 2.0 design

- **Anti-goal**, replacing "Downloaded content that runs code. No scripting, no shader source, no URL-fetching nodes.":

  > Downloaded content that runs code on the CPU, or GPU code nobody checked. No scripting, no expressions beyond the declared value forms, no URL-fetching nodes. A skin never carries shader source a person wrote. The only GPU programs a skin can cause to run are presets in the app's own shader library, named by id, and presets that emuskins compiled from slang source it holds and reviewed, carried in the bundle in the app's compiled container and run only while their hash is on emuskins' approved list. That container holds generated Metal source, which the device compiles; the approved list is what makes it trusted.

- **Non-goals**: "animation beyond state transitions" becomes "animation beyond the keyframes and waves of the live effects design"; "raw shaders" stays.
- **§1 feature table**: add the rows of §8 above and the `optional` key; `effects.ci` loses "the TS renderer ignores it" in favour of the table in §10 above.
- **§3**: `screen` gains `effects`; `filters` is defined as shorthand; the common fields gain `live`; the document gains `optional`, `shaders` and `display`. **§5.1** gains the `picture` paint. **§5.3** gains the `shader` effect, the `ci` definition of §6 above, and live values in `params`.
- **§8.2 and §9.2**: the rest frame and frame fixtures.
- **§11**: the limits below.

### 15. emuskins documentation pages that change

| Page (`skins/docs/format/`) | Change |
|---|---|
| `index.html` | "What readers need" explains `optional`, the static fallback and the live feature names; a new section "What a live skin can know" (signals and permission) |
| `reference.html` | generated from the schema, so it gains `liveValue`, `animate`, `picturePaint`, `shaderEffect`, `shaders`, `live`, the screen's `effects`; the script that checks every schema key is documented covers them |
| `skin-2.0.schema.json` | regenerated from the Swift model |
| `live.html` (new) | the frame model, the `live` block, value forms, animation with a scrubber, the signal table with rest values, the three permission tiers, limits, how effects fall back |
| `shaders.html` (new) | library presets by id, parameters, `measure`, textures, how to submit slang for a bundled preset, the approved list, what a shader cannot do |
| `tutorial.html` | a new chapter, "Put the game inside the art": a small TV with glare over the tube, a glow behind it and a pulsing light |
| `examples.html`, `examples/` | `tv.json`, `ambient-glow.json`, `activity-light.json`; previews get a sample picture |
| `playground.html` | a picture source (test card or sample clip), a time scrubber, signal sliders, and a note on any `ci` or `shader` effect that it is not previewed in the browser |
| `migration.html` | Delta screen `filters` → screen effects; RetroArch bezels and overlays → a screen node with art over it |

The SkinKit wiki's overview gains a paragraph and links to the two new pages. Provenance's wiki page on external display TVs says a TV is a format 2 file.

## Limits (added to 2.0 §11)

16 live layers, nested at most 3 deep; 64 live values; 4 picture paints, blur at most 200 pt; 16 keyframes per animation; 3 shader effects (one per screen, two elsewhere); 8 `ci` entries per node; the bundled-preset limits of §7; the flashing rule of §4. A skin that breaks a limit fails validation and is drawn as its bake, as in 2.0.

## Calls I made (not the owner's words)

1. **An approved list makes "compiled by the site" checkable.** The compiled container is generated Metal source, so without a check any sideloaded skin could run any GPU program. A hash list needs no signing keys and gives revocation for free. Library presets, named by id, are the normal path and carry no code at all.
2. **Camera and face effects go only as far as three numbers** (head x, y, distance), behind the system permission and an app setting that is off by default, never on an external display, and built last. Face expression, gaze and identity are not signals.
3. **The format makes no distinction between the device and an external display; the rollout does.** External display TVs first, device skins as a separate piece.
4. **Effects in this order of importance**: the picture in the tree and live layers; the glass, reflection and room-light shaders the TVs already use; lights that follow activity and sound; Core Image on screens; motion; the viewer.
5. **`optional` beside `requires`**, so "draws the static tree" and "falls back to the bake" are two different, declared things.
6. **Still 2.0**, not 2.1, because nothing has shipped.
7. **Bindings are pure and hosts smooth.** A frame does not depend on earlier frames, which is what lets two renderers agree on a fixture.
8. **Animation is composite-time only**: opacity, offset, scale, rotation, tint and effect parameters. Layout never animates, and fills are not re-drawn per frame.
9. **No operators on live values.** Nesting layers multiplies; anything more is the scripting the format refuses.
10. **`measure` and the flag switch** exist so a TV states its tube once and the flat-glass rule is data.
11. **The picture is a paint**, not a new node type, so reflections and glows use the shapes, clips and blends the format already has.
12. **A `display` key marks a TV** and carries its preferred systems, so the validator stops applying controller rules to it. Bundling and listing display skins on emuskins stays a later design.
13. **SkinKit gets a compositor but no slang runtime.** The runner is a protocol the host implements.
14. **The player's filter replaces a screen's own effects, never a scene shader**, matching how classic skin filters behave today.
15. **Reduce Motion, Dim Flashing Lights, Low Power Mode and thermal pressure all mean the rest frame**, and fast strong flicker fails validation.
16. **Bundled shaders are approved by a reviewed pull request** in `skins`, never automatically.
17. **Signal names, rest values and smoothing constants** as in §5.
18. **A skin can name only slang library presets**, never an app's hand-written filters, so a skin means the same thing in every app.
19. **A shader group's content is re-composited each frame when it holds a live layer**, so lights inside a TV's scene animate and are reflected.

## Tasks

In dependency order. Each becomes an issue in the repository named.

**SkinKit**

1. Model, schema and validator for everything in §2 to §8 (`optional`, `shaders`, `live`, live values, picture paint, screen `effects`, `shader` effect, limits, the flashing rule); the live plan and frame evaluation in `SkinKit2Core`; plan fixtures.
2. `SkinKit2Render`: frames (clocks, signals, still pictures), overlay order, picture paints, `ci` effects; record the new fixtures. Baker: rest frame, `ci` → classic `filters`.
3. `SkinKit2Live`: the Core Image and Metal compositor, under and over parts, the budget and fallbacks, `Skin2ShaderRunner` and `Skin2SignalSource`, tested with a fake runner.
4. `SkinCatalogKit`: the approval list (fetch, cache, bundled snapshot, revocation).
5. Edit the 2.0 design as in §14.

**skins (emuskins)**

6. TypeScript: model, validator, plan, frame evaluation, picture paints and overlay order against the vendored fixtures; baker parity.
7. Docs: the pages of §15, the playground's picture, scrubber and sliders, and the generated `shader-library.json` the validator checks library presets against.
8. Bundled shaders: the compile-and-check job on a macOS runner, `shaders/approved.json`, the submission and review steps. Needed only for `effects.shader.bundled`; everything else ships without it.

**Provenance**

9. A `Skin2ShaderRunner` on `PVSlangRuntime`; `presentOnExternalOutput` runs a skin's live plan; the three TVs rewritten as one file each; `TVBezelCatalog` version 2; `TVBezelShader` reduced. Depends on 1 to 3.
10. Signal sources: picture colours, audio level, rumble, disk (LED interface) and save activity, the pause-aware clocks. The audio tap goes in the shared audio engine's output; a core that plays through its own audio path reports the rest value until it is given a tap, and the builder lists which cores those are.
11. A classic skin's screen filters, and a format 2 screen's effects, applied when the device's skin frames the picture on the external display.
12. Live skins on the device: its own short design first (§13).
13. Motion, then the viewer signal with its setting and prompt. Last.

Tasks 1, 2 and 6 can start together once 1's fixtures exist. 9 and 10 are what make the TVs one file. 8, 12 and 13 can wait without holding anything else up.

## Left to the builder

- The exact Core Image graph for a picture paint (where to downsample before a large blur), within the fixture tolerance.
- Whether static layers are kept as `CIImage`s or Metal textures, and how they are invalidated when a control's pressed state changes.
- The budget's exact window and thresholds, once it has been timed on an iPad with a 4K display.
- The wording of the app settings and the head-tracking prompt.
- How the viewer's position is found (ARKit face anchors or Vision), judged on battery cost.
- The schema's exact definition names.

## Open point the owner may want to weigh

Off-centre tubes still do not work with the uborder presets (their centre parameters use mismatched units; see the TV design). `measure` can express the mapping once it is worked out, so this design does not block it, but it does not solve it either.
