# TV bezels: scenes drawn for the screen's shape

Date: 2026-11-23. Status: draft for owner approval.

## Why

The built-in TVs (Living Room TV, Studio Monitor, Computer Monitor) are format 2 skin
documents drawn on a fixed 1920x1080 canvas. On a 16:9 screen that is the whole screen. On
anything else the app has two bad choices:

- fit the scene inside the screen, which leaves black bars (the iPad complaint that started
  this), or
- cover the screen and crop the scene (shipped in Provenance `8b6e86d1a4` on 2026-11-23 as a
  stopgap). On an iPad this clips the Living Room TV's speaker grilles.

The owner chose to fix this properly: draw the room for the screen's real shape, so nothing
is cropped and there are no bars, and make "where you sit" a real distance.

## Goals

- On any landscape screen from 4:3 to 2.4:1 a built-in TV fills the screen with no bars and
  no cropped cabinet, at the default seat.
- A 16:9 screen at the default seat looks the same as today (same tube size and position,
  same cabinet). This is the regression check.
- The Seat setting moves the player closer or further by changing how much room is drawn,
  not by cropping a fixed picture.
- The three apps that share SkinKitBezels (Provenance, iFly, iCube) get this from the
  package; app-side changes are small.

## Non-goals

- Off-centre tubes. The shader's centre parameters use mismatched units; tubes stay centred.
- Image bezels (imported PNGs, The Bezel Project). They are laid out by a different path.
- Third-party "standalone" shader presets that draw their own cabinet (`TVBezel.presetID`).
  They keep a fixed 16:9 scene and today's cover-and-crop framing.
- New artwork or new TVs. The three documents are re-laid out, not redesigned.
- Portrait. TVs show in landscape only, as today.

## Anti-goals

- A TV whose tube changes size or shape between screen shapes at the same seat. The tube is
  the thing the player looks at; only the room around it may grow or shrink.
- A second copy of each document per screen shape (approach B below).
- Any change that makes the GPU work harder than the stopgap does on iPad. A GPU hang is
  fatal for the session on iOS.

## What was measured

`append-uborder-bezel-reflections` was rendered on a Mac GPU at four output sizes with
`fr_aspect_x/y` = 4:3, `fr_zoom` = 39.375, centre parameters 0, a flat white source:

| Output | Tube found | Tube height / output width |
| --- | --- | --- |
| 1920x1080 | 1004x754, centred | 39.3% |
| 1440x1080 | 754x564, centred | 39.2% |
| 2560x1080 | 1340x1004, centred | 39.2% |
| 1080x1080 | 566x424, centred | 39.3% |

So `fr_zoom` is the tube's height as a percentage of the output's **width** at every shape,
the tube keeps its aspect, and it stays centred. The preset does not assume 16:9; only our
code does (`TVBezelShader.sceneAspect`, the `9/16` factor in `geometryValues`, and
`TVBezelArtwork.canvas`).

Not measured: `uborder-koko-ambi` (the room-light preset). The builder must repeat the
measurement for it before relying on it; see "Room light".

## Approaches considered

- **A. Screen-shaped canvas (chosen).** Resolve the same document on a canvas with the
  screen's proportions; rewrite the documents with anchors so the wall fills, the cabinet and
  tube stay centred at a fixed size, and the floor sticks to the bottom. Nothing cropped, no
  bars, one document per TV. Cost: the documents must be rewritten and a wide cabinet needs a
  narrow form.
- **B. A layout per screen shape.** Exact control, but three times the artwork, and shapes in
  between are still cropped or barred.
- **C. Keep the zoom, narrow the Living Room TV.** Cheapest; the room is still cropped.

The owner picked A on 2026-11-23. C's zoom stays in the app as the fallback for standalone
presets and for screens outside the supported range.

## Design

### The canvas rule (SkinKitBezels, pure)

A new rule gives the canvas for a screen:

- Canvas height is the seat's height in points: Back 1080, Middle 980, Front 900.
  (A shorter canvas shows less room, so everything on it is drawn larger.)
- Canvas width = height x the screen's width / height, with that ratio clamped to
  4:3 ... 2.4. The width is not rounded: the canvas has exactly the drawable's proportions,
  so one scale factor maps canvas points to drawable pixels. (The scene cache is keyed by
  pixel size, which is already whole.)
- A screen whose ratio is outside the clamp (a Stage Manager window narrower than 4:3, a
  32:9 display) gets the clamped canvas; the app then places it with the framing it already
  has (cover, tube kept on screen).
- 4:3 is the floor because the monitors' tube is 1008 points wide and their cabinets 1176
  and 1260: they fit a 1440-point Back canvas and the tube still fits a 1200-point Front one.
  Nothing narrower than 4:3 ships as a landscape screen.

At 16:9 and Back this gives 1920x1080: today's canvas.

`TVBezelArtwork.canvas` (the static 1920x1080) stays as the default for callers that pass
none, so existing callers and the picker thumbnails keep working.

### Artwork and scene

- `TVBezelArtwork.init(data:canvas:)` and `init(bezel:canvas:)` resolve the document in an
  environment of that size. The artwork remembers its canvas. `image(pixelWidth:)` scales by
  `pixelWidth / canvas.width`.
- `TVBezelScene` gains `canvas: CGSize`. `tubeRect` is in that canvas's points.
  `TVBezelScene.make` takes the canvas; the cache key includes the canvas size.
- `TVBezelShader.geometryValues` takes the tube's aspect and the tube's height as a fraction
  of the canvas **width** and sets `fr_zoom` to that x 100. The `sceneAspect` constant is
  kept only for standalone presets.

### The three documents

Each is rewritten so that it resolves correctly at any canvas the rule can produce:

- The wall fills the canvas. Repeated wall details (panel seams and the like) are laid out
  from the centre or given enough repeats to cover a 2.4:1 canvas; overflow is clipped.
- Vertically the room is always 1080 points tall, centred in the canvas: a "room" group of
  100% width and 1080 height. The floor band (carpet, skirting, desk) is anchored to the
  bottom of that group, not of the canvas, and spans the width. So the cabinet's feet always
  stand on the floor, and at Middle and Front the canvas is a centred vertical crop of the
  Back room: moving closer pushes the floor and ceiling off screen, while the room still
  widens or narrows with the screen.
- The cabinet, everything on it, and the tube form one group centred in the canvas at a
  fixed size in points. The tube's size and aspect do not depend on the canvas.
- Legs and stands hang off the cabinet group, not off canvas coordinates.
- The cabinet must fit the narrowest canvas at Back (1080 points wide) with a visible margin
  of wall. The Living Room TV's cabinet is 1620 points wide today, so its base form is the
  narrow one (tube surround plus a slim frame) and the speaker wings are added by a
  conditional `visible` (`{ "minWidth": ... }`) once the canvas is wide enough to show them
  whole. An override can show or hide a node and change its layout, but cannot add one, so
  the wings are in the document and hidden on narrow canvases. `minWidth` compares canvas
  points (the documents pin their scale to 1).
- At Middle and Front the cabinet may touch or pass the canvas edges, as it does at Front
  today. The tube must stay inside the canvas at every seat and every shape from 4:3 to 2.4:1.
- `repeat` takes a fixed count (at most 64), so wall details get a count that covers a
  2.4:1 Back canvas (2592 points).

No schema change is needed: `anchor`, `inset`, `size`, percentage and `min`/`max` lengths,
`repeat` and `when` conditions (`minWidth`, `minHeight`) already exist.

### App side (Provenance; iFly and iCube follow)

- The seat applies on every screen, Apple TV and external displays included; only Back at
  16:9 is the "same as today" case. For standalone presets the seat keeps its meaning from
  the stopgap (cover, zoom 1 / 1.1 / 1.2).
- The seat enum maps to the canvas height. "Whole Room" (bars) is removed: with a
  screen-shaped canvas there are no bars to show. A stored `wholeRoom` reads as Back.
- For a built-in TV the scene rect is the whole drawable when the screen's ratio is inside
  the clamp; outside it, the existing cover framing is used with the clamped canvas.
- `GameExternalOutputView` asks the rule for the canvas from the drawable size and the seat,
  passes it to `TVBezelScene.make`, and uses `scene.canvas` (not the static canvas) for the
  tube texture's size and for `bezelPictureFrame`.
- Apple TV keeps the full-screen picture view added in `8b6e86d1a4`.
- Pins: SkinKit revision in `PVUI/Package.swift`, `PVTouchOverlay/Package.swift` and every
  `Package.resolved`, bumped by hand.

### Room light

`uborder-koko-ambi` runs extra passes. Before it is allowed on a non-16:9 canvas the builder
measures it the same way as the table above. If its tube drifts or its ambient passes
misbehave off 16:9, room light uses the plain preset on non-16:9 canvases until fixed, and
the report says so.

### GPU cost

The scene is now exactly the drawable's size, which is smaller than the stopgap's
cover-and-crop scene on iPad (about 1.33 times the drawable). Cost goes down, not up.

## Tests

- Canvas rule: 16:9 Back is 1920x1080; 4:3, 3:2, 19.5:9, 21:9; the clamp at both ends; the
  three seats; rounding.
- Each bundled document, resolved at 4:3, 16:9 and 2.4:1 and at each seat: exactly one
  screen; the tube is centred, has the same size and aspect at every shape for a given seat,
  and lies inside the canvas; at Back the cabinet lies inside the canvas and its feet touch
  the floor band.
- 16:9 Back regression: the tube rect of each TV equals today's
  (Living Room 960x720 at 480,180; the two monitors 1008x756 at 456,162).
- `geometryValues`: `fr_zoom` equals tube height / canvas width x 100 for a 4:3 and a 16:9
  canvas.
- App: scene rect is the drawable inside the clamp; the picture frame uses the scene's own
  canvas.

## Checks before it is called done

- Simulator screenshots of all three TVs on an iPad (4:3) and an iPhone (19.5:9) in
  landscape at each seat, and one at 16:9 compared with today's.
- Room light on and off on a non-16:9 simulator.
- Apple TV and a real iPad are the owner's device checks; say plainly if they were not run.

## Left to the builder

- Exact point sizes of the narrow Living Room form and the width at which the wings appear.
- Whether wall details are centred repeats or over-long repeats.
- Whether the canvas rule lives on `TVBezelArtwork` or in a small type of its own.
- The names of the new parameters.

## Calls made after the builder check (owner to confirm while reading)

- The supported range starts at 4:3, not 1:1, so the monitors keep their tube size.
- Closer seats crop the room top and bottom; the floor is not re-laid out per seat.
- Canvas width is not rounded.
- The seat applies on Apple TV and external displays too.

## Open questions for the owner

- Seat heights (1080 / 980 / 900) are a first guess; they are easy to change after seeing
  screenshots.
