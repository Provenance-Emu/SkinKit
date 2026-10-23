# Skin format 2.0: notes (not a design yet)

From the brainstorm on 2026-10-23. Stage 4, tentative, after the app store releases. This becomes a design document after the spike.

## Why

iCube, iFly and Provenance each generate their default skins in code (iCube first, then iFly and Provenance; Provenance added data structures for per-system designs and variants). As a file format, those skins could be shared, edited on the web, recolored, and published to emuskins.com like any other skin.

## Direction agreed so far

- **A custom declarative format**, not SVG alone and not scripts. A skin is a tree of nodes: groups, shapes, images/textures, text, controls (shapes with inputs), and screens. It's stored as JSON, with YAML maybe as a friendlier format for writing skins by hand. No embedded JS engine, because downloaded code is a security and App Review risk and can't be edited safely by tools. Simple value expressions (`"parent.width * 0.4"`) may come later.
- **Shapes:**
  - Built-in parametric shapes: rect with corner radius, squircle, ellipse, capsule, polygon(sides, rotation), star(points, innerRatio), arc, line.
  - SVG-style path strings for arbitrary curves.
  - Reusable parts with parameters, placed many times with overrides.
  - `repeat` (count, offset, rotate, scale) for stamping, e.g. grilles or keypads.
- **Paint:** stacked fills and strokes (solid, linear, radial and angular gradients, tiled image/texture fills; stroke width, dash, cap, join).
- **Effects:**
  - Portable: shadows, blur, blend modes.
  - Core Image filters as a name-plus-settings list.
  - Named materials (gloss, reflection, brushed metal, plastic grain, CRT), each implemented natively per platform.
  - Raw shader code: later, if ever.
- **Layout:** anchors (struts) to parent or named areas (`screen`, `safeArea`, `controls`) with offsets and fixed, fractional or aspect sizes, min/max. Stacks and grids with flexible spacing act as the springs. One skin adapts to every device and orientation. Default positions are hints; player edits are saved as offsets.
- **Tokens and variants:** named colors and sizes (`$accent`). A theme is a set of token values, and a game variant overrides some nodes. This replaces `themes`/`gameOverrides` for 2.0 skins.

## Non-negotiables

- **Bake to classic.** Every 2.0 skin can be rendered to a classic Delta/Manic skin: a PDF per device/orientation plus classic `info.json` items and screens.
- **Two renderers, one result.** Swift (`SkinKitUI`, Core Graphics/SwiftUI `Canvas`) and TypeScript (website previews and editor), checked against shared reference images.

## Open questions for the design

- How node coordinates are expressed: points in a reference size, or fractions?
- How controls' hit areas derive from shapes (bounds plus extended edges?).
- Versioning and feature detection (`formatVersion`, required features).
- Where the files live inside a skin (`skin.json` next to `info.json`? inside it?).
