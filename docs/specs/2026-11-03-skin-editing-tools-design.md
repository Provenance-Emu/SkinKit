# Skin editing tools: web editor, in-app nudges, and merging split variants

Status: draft for approval · 2026-11-03 · "Later" item of [ROADMAP.md](../../ROADMAP.md), from [SkinKit#26](https://github.com/Provenance-Emu/SkinKit/issues/26)
Repos: `Provenance-Emu/skins` (emuskins.com, catalog scripts), `Provenance-Emu/SkinKit` (`SkinKitManager`, `SkinKitUI`), Provenance, iFly

## Why

Making or fixing a skin today means unzipping it, editing `info.json` by hand in a text editor, guessing frame coordinates, re-zipping, and AirDropping the file to a phone to see whether a button landed where it should. The editors that exist are Delta's community tools (desktop web, Delta-only inputs) and nothing of ours. Three things keep coming up:

- Creators want to **lay out a skin visually** on a device frame and get a `.deltaskin` out, without installing anything.
- Players want to **nudge a button** that sits under their thumb wrong on their phone, without becoming a creator. Provenance already ships half of this twice (see below) and neither half is finished.
- The catalog has **164 variant families shipped as separate files** (55 with exactly two members, 101 with three or more). Stage 2 grouped them on the site and in the stores, but a player who wants "the Doom layout and the AvP layout" of one skin still installs two files, and the single-file formats Provenance can now play (`altRepresentations`, `themes`, `gameOverrides`) are used by 5 catalog skins plus our own fixtures. The variants design left "a manual merge tool" to this project.

## What exists today (researched 2026-11-03)

**On the website (`skins/docs`).** No editor. `submit.html` already loads JSZip 3.10.1 from cdnjs and reads `info.json` out of a skin in the browser (`docs/js/submit.js`), so a client-side zip stack is established. `browse.js` has the family clustering (`clusterByGroup`, `variantLabelOf`, `familyName`, `innerVariantLabels`) and knows when it runs inside an app (`isInApp`). Stage 3's converter (#22, not started) will add PDF rasterizing to the same page family.

**In SkinKit, two unfinished editors.**

| | `DeltaSkinButtonOffsets` + `DeltaSkinEditModeOverlay` | `DeltaSkinEditorViewModel` + `DeltaSkinEditOverlay` |
|---|---|---|
| Where | `Sources/SkinKitUI/Models/DeltaSkinButtonOffsets.swift`, `Views/Components/DeltaSkinEditModeOverlay.swift` | `Sources/SkinKitUI/Models/DeltaSkinEditorViewModel.swift`, `Views/Editor/DeltaSkinEditOverlay.swift` |
| What it edits | A per-button position offset | A per-button frame (move, and the panel can type a size) |
| Keyed by | `skinIdentifier + buttonId`, **not** by device, display type or orientation, so a nudge made in portrait also moves the landscape button | The traits being previewed; cleared when traits change |
| Persisted | `UserDefaults` `com.provenance.deltaskin.buttonoffsets.v1.<skinId>` | Not persisted; export only |
| Applied live | Yes: `DeltaSkinView` reads `buttonOffsets.offset(for:skinIdentifier:)` when it lays out buttons (`DeltaSkinView.swift:1783`) and has an `isEditMode` binding | No |
| Output | None | `DeltaSkinExporter.export(skin:traits:modifiedFrames:)` (`SkinKitManager`) patches `items[].frame` in the raw `info.json` dictionary and rewrites the archive as `<name>-edited-<id>.deltaskin` for a share sheet. The `identifier` inside is unchanged |
| Reachable from | `DeltaSkinFullscreenPreview` pencil button (the view hosts both overlays) | Same screen, export button |

Nothing in-game toggles `isEditMode`; Provenance's pause menu has no "edit controls". iCube has its own layout editor for its Swift-drawn pads (`TouchOverlayLayoutStore`) and does not use `DeltaSkinView`, so none of this applies to it.

**Variant formats** are as the variants design describes: `altRepresentations` (Ignited), `themes` and `gameOverrides` (Provenance), all decoded by `SkinKitCore` (`DeltaSkin.Info`), all additive, all ignored by Delta and Manic. The catalog's `variants.json` sidecar (`scripts/variants_sidecar.py`) lists what a single file carries. `scripts/repack_skins.py` already rewrites archives, uploads them to the `mirror` GitHub release (`MIRROR_TAG = "mirror"`, 147 entries hosted there today) and writes new entries with `groupId`/`groupOrder`/`variantLabel` and `originalURL`; `link-health.yml` runs it weekly with `--from-health --upload`. All 55 two-member families share one `gameTypeIdentifier` across both members.

## Goals

1. A creator can open a skin on emuskins.com, move and resize its buttons and screens on a device frame, change the `info.json` fields and artwork, and download a working `.deltaskin`/`.manicskin`, with nothing installed and nothing uploaded.
2. A player in Provenance or iFly can nudge a button during a game, the nudge sticks for that skin on that device and orientation, and resets in one tap. The same screen offers the skin's theme, alternate layout and game override.
3. A creator can merge a split family into one file from the website, and the catalog publishes a merged file for the families where the merge is mechanical and safe, without touching the original entries.

## Non-goals

- Drawing or painting artwork. The web editor swaps image files; it does not edit pixels or PDFs.
- Skin format 2.0. This is a classic-format editor. The editor's model layer is kept separate from its canvas so the 2.0 project can replace the renderer, not the tool.
- Editing screens in-app. Game-screen placement is tied to the viewport and dual-screen code; in-app edits are buttons only.
- In-app editing in iCube. It has its own pad editor and skin model. It can read the same offsets file later (open question).
- Hosting creators' uploads on emuskins.com. The editor downloads a file; publishing still goes through `submit.html` and a URL the creator hosts.
- Converting `gameOverrides` automatically in the catalog. Split files don't say which game each variant is for; only a creator knows.

## Anti-goals

- A skin edited or merged by these tools stops loading in Delta or Manic. Everything written is a complete classic skin plus additive keys.
- A merged file replaces or hides the original split entries, their authors' credit or their download counts.
- A player's nudges change the skin file. Nudges live beside the skin; the file is only rewritten when the player explicitly exports a copy.

## Design

### 1. Web editor on emuskins.com (`skins/docs/edit.html`, `docs/js/editor/`)

Scoped to what a GitHub Pages static site can do: everything runs in the browser, the file never leaves the device.

**Loading a skin.** Three ways in: drop or pick a `.deltaskin`/`.manicskin`/`.zip`; `edit.html?skin=<catalog id>`, which fetches `downloadURL` from `catalog.min.json`; and an "Edit a copy" button on every skin page and in `renderModal` (browse.js) that opens the former. Fetching by URL only works for hosts that send CORS headers: GitHub release assets (the `mirror`) and `raw.githubusercontent.com` do; deltastyles.com (995 entries) is not known to, so when the fetch fails the page says "Download it, then drop it here" with the download link. The converter (#22) has the same constraint, so the loader lives in a shared module, `docs/js/skin/source.js`.

**Shared skin stack (`docs/js/skin/`), used by the editor, the converter and the merge tool:**
- `zip.js`: JSZip 3.10.1 (already on `submit.html`) wrapped to read `info.json` at the archive root or one folder down (the rule `repack_skins.py` and `SkinLibrary.skinFolder` use), to strip `//` comments the way the apps do (`DeltaSkin.stripComments`: whole-line and trailing, never inside strings), and to write a new archive.
- `info.js`: the `info.json` model as a plain object graph that round-trips unknown keys untouched. Edits are patches on the raw dictionary, the way `DeltaSkinExporter.patchItems` does it, so a skin with `keyboardOverlay`, `haptic`, `states` or keys we have never heard of comes out with them intact.
- `art.js`: rasterizes artwork for the canvas. PNG via `<img>`; PDF via pdf.js (`pdfjs-dist` from cdnjs, pinned) rendered at the mapping size; SVG via `<img>` with a note that Delta and Manic will not draw it. The converter needs exactly this to emit PNGs.
- `validate.js`: a port of `link_health.py`'s rules (`classify_archive`, `_has_artwork`, `find_asset`): `info.json` present, required keys, every layout's artwork resolvable the lenient way the apps resolve it (exact path, then case-insensitive file name, then same stem as `.pdf`/`.png`/`.svg`). The editor shows the result before export, so what the catalog's health check would hide never gets submitted.
- `inputs.json`: the known input names per `gameTypeIdentifier` (Delta and Manic spellings, plus Provenance's extras such as `toggleAltRepresentations`, `quickSave`, `menu`), used for the input picker. This is the same table the RetroArch converter needs for its left-hand column; see the RetroArch design for how it is shared with SkinKit.

**The canvas.** A device frame picker lists every trait the skin has representations for (`iphone`/`ipad` × `standard`/`edgeToEdge`/`splitView` × `portrait`/`landscape`; iPad model keys and `tv` when present), plus "Add layout" which copies an existing one. The frame is the `mappingSize` drawn to fit, with the background asset underneath. Items are rectangles with handles: drag moves the `frame`, corner handles resize it, a dim outset shows `extendedEdges`. Screens are rectangles too: `outputFrame` on the canvas, `inputFrame` as a second rectangle on a strip of the native resolution, with aspect lock on by default. Arrow keys nudge by one mapping point, shift by ten; snapping to other items' edges and to the frame center is on by default. Undo/redo is a plain command stack over the model.

**Panels.** Skin: `name`, `identifier` (with a warning when it still equals the loaded skin's, because Manic rejects a second import with the same identifier), `gameTypeIdentifier` (a dropdown of known types, Delta and Manic spellings), `debug`. Item: inputs (multi-select from `inputs.json`, or free text), `frame`, `extendedEdges`, per-item Manic asset, thumbstick image and size. Layout: `mappingSize`, `extendedEdges`, `translucent`, assets per size class (`resizable`, `small`/`medium`/`large`), and "Replace artwork", which swaps the file in the zip and keeps the old name unless the new file has a different extension, in which case it updates every reference. Variants: the `themes`, `altRepresentations` and `gameOverrides` of the loaded skin are listed read-only in this version, with the merge tool (§3) as the way to create them.

**Export.** "Download" writes `<identifier>.deltaskin`, or `.manicskin` when the game type is a `public.aoshuang.game.*` one, with `info.json` pretty-printed and comments gone (the apps strip them anyway; Delta reads plain JSON). The page keeps a draft in IndexedDB so a reload does not lose work, and "Submit to the catalog" opens `submit.html` with the metadata fields prefilled; the file itself the creator must host, as today.

**Phones.** The editor is for a desktop or iPad browser. On an iPhone it opens read-only with the panels, because the canvas and a panel do not fit; in-app nudging (§2) is the phone story.

**No build step.** The site has none (`browse.js` is hand-written ES modules), and adding one for the editor would make every other page's workflow different. The editor is ES modules under `docs/js/editor/` with the shared code in `docs/js/skin/`.

### 2. In-app editor in SkinKitUI: layout nudges and a skin options sheet

Finish the two half-editors into one, and keep it small: a player moves buttons, the move sticks, and the same sheet exposes the skin's variants. Format 2.0's notes say "default positions are hints; player edits are saved as offsets", so this is also the first piece of that model, built where 2.0 will need it.

**One store: `DeltaSkinLayoutEdits` in `SkinKitManager`.** A non-UI, testable type that replaces `DeltaSkinButtonOffsets`' storage and `DeltaSkinEditorViewModel.modifiedFrames`. It keeps, per skin identifier and per trait key (`<device>.<displayType>.<orientation>`, the same spelling `DeltaSkinExporter.displayTypeKeys` walks), a map of button id to `{dx, dy, scale}` in mapping points. It persists as one JSON file per skin in `<skinsDirectory>/edits/<identifier>.json` through `DeltaSkinStorage`, not `UserDefaults`, because a file beside the skin survives an app reinstall that restores Documents, can be exported with the skin, and is already the shape a 2.0 renderer reads. `DeltaSkinButtonOffsets` stays as a thin `@MainActor` facade over it so `DeltaSkinView`'s call sites (`offset(for:skinIdentifier:)`, `setOffset`, `resetOffsets`, `hasCustomOffsets`) do not change; it gains the trait parameter. Existing `v1` UserDefaults offsets are migrated on first read by applying them to every trait the skin has, then the key is deleted; that keeps what players did and ends the portrait-moves-landscape bug.

**Editing in a game.** `DeltaSkinView` already has `isEditMode`. Provenance's pause menu gets "Edit controls", which sets it, dims the game, and shows `DeltaSkinEditModeOverlay` with three additions: a pinch gesture on a button sets its `scale` (clamped 0.5–2.0), a tap selects a button and shows "Reset this button", and a bar at the top offers "Reset all" and "Done". Screens have no handles. tvOS keeps the overlay as a visual only, as it does now. iFly gets the same through its existing in-game skin hooks (`DeltaSkinAppHooks`). `DeltaSkinFullscreenPreview` keeps its pencil button and uses the same overlay, so previewing and playing edit the same offsets.

**Export as a new skin.** `DeltaSkinExporter` learns to bake `DeltaSkinLayoutEdits` for every trait that has them (today it takes one traits value and a frame map), scales item frames about their center for `scale`, and changes `identifier` to `<identifier>.edited` and `name` to `<name> (edited)`, so Manic and Delta accept the copy beside the original. The file name stays `<name>-edited-<id>.deltaskin`. This is the hand-off to the web editor: a player's nudges become a creator's starting point.

**Skin options sheet: `DeltaSkinOptionsView` in `SkinKitUI`.** One sheet, reachable from the pause menu ("Skin options") and from `SystemSkinSelectionView`'s row for the selected skin, with: `DeltaSkinThemePickerView` (exists; hidden when the skin has no `themes`); "Alternate layout" toggle bound through `DeltaSkinAltRepresentationsStoring` (exists; hidden without `altRepresentations`); a read-only line "Layout for: Doom" when a `gameOverrides` key matched the running game (Provenance passes the keys in `DeltaSkinTraits.gameIdentifier`); "Edit controls"; "Reset edits for this skin"; "Export as new skin". No new persistence: themes and the alt choice already have stores.

### 3. Merge split variants into one file

Two implementations of one set of rules: a web tool a creator drives, and a catalog job that runs unattended. They agree on what a merge is and share test fixtures; they differ in what they are allowed to decide.

**The compatibility rule, stated once.** The merged skin's `representations` is the base variant's tree, byte for byte apart from JSON formatting, with the base variant's artwork under its original file names. Everything the merge adds is a new top-level key (`altRepresentations`, `themes`, `gameOverrides`) plus artwork files with new names. Delta and Manic ignore the new keys and load the base; Provenance and Ignited load the extras. The merged `identifier` is `<base identifier>.allinone`, so a user who has a split member installed can install the merged file beside it, and the `name` is the family name (`familyName` in browse.js, `derive_variant_label`'s inverse in `skin_schema.py`) plus " (All variants)".

**Classifying a family.** Given N members sharing a `groupId`, ordered by `groupOrder`, each with its parsed `info.json`:

1. If the members do not all share one `gameTypeIdentifier`, or the base lacks a layout the others have, or any member is itself a single-file variant skin (has `altRepresentations`, `themes` or `gameOverrides`), **keep split**.
2. If every non-base member has the same trait set as the base and, per trait, identical `mappingSize`, `extendedEdges`, `translucent`, `items` (frames, inputs, extended edges, thumbsticks, with per-item Manic assets allowed to differ) and `screens`, and only `assets` differ: **themes**. Base artwork stays; each other member becomes `{ "id": slug(variantLabel), "name": variantLabel, "assets": { device: { displayType: { orientation: assets } } } }` with its files renamed `<themeId>__<original name>` so two variants' `iphone_portrait.pdf` do not collide. Flat names, not folders, because Provenance's lenient asset lookup (`Archive.entry(matchingAssetNamed:)`) falls back to a case-insensitive file-name match anywhere in the archive, and a theme file in a folder with the base's name could shadow it when the exact path misses. This also works for N ≥ 3, which the "exactly two" rule below does not cover.
3. Else if N is exactly 2: **altRepresentations**. The second member's `representations` tree becomes `altRepresentations`, its artwork renamed `alt__<original name>`, its asset references rewritten. Two variants that differ in layout is what Ignited's format was made for (the five DS skins in the catalog), and with three or more there is no second slot.
4. Else **keep split**.

A `toggleAltRepresentations` button is the only way to reach the alternate set in Ignited, and split skins never have one. The two implementations handle this differently, below.

**Web tool (`docs/edit.html` "Merge" mode, `docs/js/skin/merge.js`).** The creator picks a family (from the catalog, or drops several files). The tool classifies, shows the result and the reason, and lets the creator override: force themes with a per-trait diff of what would be lost, pick which member is the base, and for layout variants with N ≥ 2 choose **game overrides** by naming the game each member is for (free text matched the way Provenance matches `gameOverrides`: md5, crc, file name, then title; a title is the usual choice). For an alt merge it offers to add a toggle button: a generated glyph PNG (two overlapping rectangles, from the same style as `generate_variant_fixtures.py`) placed as an item with input `toggleAltRepresentations` in both sets, where the creator drags it; default position is the top-right corner clear of screens and items when such a spot exists. The output goes through the editor, so the creator can adjust and download.

**Catalog job (`skins/scripts/merge_variants.py`).** Runs in `link-health.yml` after `repack_skins.py`, reusing `polite_http` downloads from the run's cache, `extract_skins`/`parse_info_json` from `repack_skins.py`/`link_health.py`, and `upload()` to the `mirror` release. For every family whose members are all healthy and whose classification is themes or alt, it builds the merged archive, uploads `<new id>.<ext>` to `mirror`, and writes **one additional entry** `skins/<system>/<slug>-allinone-<id6>.json`:

- `id`: `make_id("emuskins-merge", "<groupId>#allinone")`, stable across runs.
- `source`: the base member's `source`; `author`, `systems`, `gameTypeIdentifier`, `tags` from the base; `thumbnailURL` left for the thumbnail job.
- `groupId`: the family's, `groupOrder`: 0, `variantLabel`: "All variants", so it sits first in the family on the site and in the stores.
- `mergedFrom`: the member ids in base-first order, and `mergedHash`: sha256 of the members' `downloadURL`s and `id`s. New optional fields validated by `skin_schema.py` (`mergedFrom` ids must exist and share the entry's `groupId`). Both are ignored by the apps' lenient decoders; Provenance's catalog layer is now `SkinCatalogKit`, also lenient.

The job never injects a toggle button: that puts our art inside a creator's skin unasked. A merged alt skin's second layout is reachable in Provenance through the options sheet (§2); Ignited users keep the split files, which stay in the catalog unchanged. The job is idempotent: a family whose `mergedHash` matches is skipped; a changed or shrunk family gets its merged file rebuilt and re-uploaded with `--clobber`; a family that drops below two visible members has its merged entry deleted. A merged file is a normal catalog entry from then on: the health check covers it, the sidecar computes its `variants`, hiding rules apply, and `build_catalog.py` never downloads anything.

**Website and apps.** The family card already lists members by `variantLabel`; "All variants" appears as the first member with an "Includes N variants" badge from the sidecar, and the skin page says "Merged by emuskins from N files by <author>" with links to each. `SkinFamily` in `SkinCatalogKit` needs no change; `SkinDownloadPlan` for "Download all" should skip the merged member when the user chose the members, or install only the merged member when the user chose it, so a player never gets both (one new rule in `SkinDownloadPlan`).

**Shared rules, two codebases.** The classification is small enough to write twice. What keeps them equal is `fixtures/merge/`: a set of tiny families (generated like `fixtures/variants/`, with the generator extended) with an `expected.json` naming the outcome and the renamed files for each. `tests/test_merge_variants.py` runs the Python over them; `tests/test_merge_js.py` runs `node docs/js/skin/merge-cli.mjs` over the same fixtures when `node` is on `PATH` (the way `test_browse_index.py` already treats the site's JS) and skips otherwise.

**Scale.** 55 two-member families today, all sharing a game type, are alt or theme candidates; the 101 larger families are theme candidates only. The first run is `--dry-run` and prints the classification per family, so we see the real counts before anything is uploaded.

## Order of work

1. Shared skin stack on the site (`docs/js/skin/`: zip, info, art, validate, inputs) with the converter (#22), which needs the same modules. Either project can land first; whichever is second reuses.
2. `DeltaSkinLayoutEdits` and the options sheet in SkinKit, then Provenance's and iFly's pause-menu entries. Independent of the site.
3. Web editor on top of 1.
4. Merge: fixtures and Python job first (they make the rules concrete), then the web tool on top of 1 and 3.

## Calls I made

- **The web editor is static and client-side.** The site is GitHub Pages with no server; a server-side editor would need hosting, accounts and moderation we do not have. Everything a creator does stays on their machine until they submit a URL.
- **No build step on the site**, matching `browse.js`. The editor is ES modules, pinned CDN libraries, no bundler.
- **Nudges are per trait and live in a file beside the skin**, not in `UserDefaults`. The current per-skin key moves buttons across orientations, which players notice; the file is the 2.0 shape and ships with exports.
- **In-app editing is buttons only**: move and scale. Screens stay where the creator put them.
- **Exports get a new identifier** (`.edited`, `.allinone`) so Manic and Delta accept them beside the original.
- **Merged files are added, never substituted.** The variants design's reasons still hold (identity, download counts); adding an entry costs one more line in a family card and loses nothing.
- **The catalog job merges only themes and two-member alts, and never adds art.** Game overrides need a human to name the games, and a toggle glyph is a creative decision; both are web-tool only.
- **Flat renamed artwork** for themes and alts, because of Provenance's lenient asset lookup.

## Left to the builder

The canvas's exact gestures and snapping thresholds; the IndexedDB draft schema; the glyph for the toggle button; how `DeltaSkinOptionsView` is styled per app (SkinKitTheme); the merge job's log format; which CDN pin of pdf.js.

## Follow-up issues

Ready to paste. Each should link this document.

**Website: shared client-side skin stack (`docs/js/skin/`)**
**Where:** Provenance-Emu/skins `docs/js/skin/`
**Do:** `zip.js` (JSZip read/write, `info.json` at root or one folder down, comment stripping as `DeltaSkin.stripComments`), `info.js` (raw-dictionary round trip with patch helpers), `art.js` (PNG, pdf.js for PDF, SVG via `<img>`), `validate.js` (port of `link_health.py` `classify_archive`/`_has_artwork`/`find_asset`), `inputs.json` (known inputs per game type), `source.js` (file drop or catalog id, CORS fallback message). Unit tests for `validate.js` against `fixtures/variants/` and a deliberately broken skin.
**Depends on:** nothing (shared with #22)
**Done when:** `validate.js` agrees with `link_health.py` on every fixture, and `submit.js` uses `zip.js` instead of its own JSZip code.

**Website: skin editor page (`docs/edit.html`)**
**Where:** Provenance-Emu/skins `docs/edit.html`, `docs/js/editor/`
**Do:** Device frame picker, canvas with draggable/resizable items and screens (extended edges shown, aspect lock, snapping, keyboard nudges, undo), panels for skin fields, item fields, layout assets and "Replace artwork", validation before export, `.deltaskin`/`.manicskin` download, IndexedDB draft, "Edit a copy" entry from skin pages and `renderModal`, read-only on iPhone.
**Depends on:** the shared skin stack issue
**Done when:** A skin from `fixtures/variants/` opened, edited (move a button, swap one PDF, rename) and downloaded installs in Provenance, Delta and Manic with the edits visible, and unknown `info.json` keys survive the round trip.

**SkinKitManager: `DeltaSkinLayoutEdits` (per-trait button offsets and scale, file-backed)**
**Where:** Provenance-Emu/SkinKit `Sources/SkinKitManager/DeltaSkinLayoutEdits.swift`, `Sources/SkinKitUI/Models/DeltaSkinButtonOffsets.swift`, `DeltaSkinExporter.swift`
**Do:** The store described in §2 (JSON per skin under `<skinsDirectory>/edits/`), `DeltaSkinButtonOffsets` as a facade with a trait parameter, migration of `v1` UserDefaults offsets to every trait, `DeltaSkinExporter` baking edits for all traits with `scale` and the `.edited` identifier/name. Tests: round trip, migration, exporter output decodes with the new identifier.
**Depends on:** nothing
**Done when:** `DeltaSkinView` renders offsets per trait (a portrait nudge leaves landscape alone), an exported copy installs beside the original in Provenance, and `xcrun swift test` passes.

**SkinKitUI: in-game edit mode and `DeltaSkinOptionsView`**
**Where:** Provenance-Emu/SkinKit `Sources/SkinKitUI/Views/Components/DeltaSkinEditModeOverlay.swift`, new `Views/Options/DeltaSkinOptionsView.swift`; Provenance `PVUI` pause menu; iFly in-game menu
**Do:** Pinch-to-scale, select-and-reset, "Reset all"/"Done" bar in the edit overlay; the options sheet (theme picker, alternate layout toggle, matched game override line, edit controls, reset, export). Pause-menu entries in Provenance and iFly.
**Depends on:** the `DeltaSkinLayoutEdits` issue
**Done when:** In a running Provenance game: pause → Edit controls → drag and pinch a button → Done; the change persists across relaunch and only for that orientation; the options sheet shows the theme picker on `sample-themes-gba` and the alt toggle on `sample-alt-ds`.

**Catalog: `merge_variants.py` publishes merged families to the mirror**
**Where:** Provenance-Emu/skins `scripts/merge_variants.py`, `scripts/skin_schema.py` (`mergedFrom`, `mergedHash`), `fixtures/merge/`, `tests/test_merge_variants.py`, `.github/workflows/link-health.yml`
**Do:** Classification (§3), archive building with flat renamed artwork, `.allinone` identifier, upload to `mirror`, one additional entry per family with `groupOrder` 0 and `variantLabel` "All variants", idempotence by `mergedHash`, deletion when a family shrinks, `--dry-run` reporting. Fixtures with `expected.json`.
**Depends on:** nothing
**Done when:** The dry run lists every family's outcome and reason; the fixtures pass; a merged `sample-split-family` installs in Delta (base only), Manic (base only) and Provenance (themes or alt present); `build_catalog.py --check-only` validates the new fields.

**Website: merge tool and game-override naming in the editor**
**Where:** Provenance-Emu/skins `docs/js/skin/merge.js`, `docs/js/skin/merge-cli.mjs`, `docs/edit.html`, `tests/test_merge_js.py`
**Do:** Family picker, classification with reasons and overrides, game-override naming, optional toggle-button glyph the creator places, output into the editor. Node CLI over `fixtures/merge/` so the Python tests can check the JS gives the same outcomes.
**Depends on:** the editor page issue and the `merge_variants.py` issue
**Done when:** Every `fixtures/merge/` case gives the same outcome in JS and Python, and a creator can turn `sample-split-family` into a `gameOverrides` skin by typing three titles.

**SkinCatalogKit: download plans skip the merged member or the split members, never both**
**Where:** Provenance-Emu/SkinKit `Sources/SkinCatalogKit/SkinDownloadPlan.swift`, `SkinFamily.swift`
**Do:** Recognize an entry with `mergedFrom` (decode the field), exclude it from "Download all" unless it is the only choice, and when the user picks it, install only it. Site: skin page credit line "Merged by emuskins from N files".
**Depends on:** the `merge_variants.py` issue
**Done when:** Family tests cover a family with a merged member; "Download all" fetches N files, never N+1.

## Open questions

1. **Should emuskins.com host creators' edited skins?** Everything here downloads a file the creator must host. A GitHub-Actions-backed upload (an issue with the file attached, processed into the `mirror` release) would make "edit → publish" one flow, but it makes us the host of record for other people's derivative art. Joe's call; nothing here depends on it.
2. **Should the catalog job put a merged file's download count anywhere?** Today it starts at zero and the split members keep theirs. Summing them on the site would double-count installs.
3. **Does iCube read `edits/<identifier>.json`?** Its `SkinOverlayView` lays out from `SkinLayout.make`; applying offsets there is a few lines, but iCube already has a pad editor and two editors in one app is confusing.
4. **Themes for N ≥ 3 by default, or only on request?** A family of six colorways becomes one 6-theme skin automatically. That is the intent, but the first dry run should confirm the archive sizes are sane (six PDF sets in one file).
5. **The toggle-glyph default position** when no clear spot exists: skip the glyph (the merged alt is reachable only in Provenance) or shrink it. Default in this document: skip, and say so in the tool.
