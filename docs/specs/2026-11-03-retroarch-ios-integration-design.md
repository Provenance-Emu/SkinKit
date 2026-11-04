# RetroArch iOS integration: one tap from a skin to an overlay

Status: draft for approval · 2026-11-03 · "Later" item of [ROADMAP.md](../../ROADMAP.md), from [SkinKit#26](https://github.com/Provenance-Emu/SkinKit/issues/26); builds on stage 3 (#22 converter page, #23 button per skin)
Repos: `Provenance-Emu/skins` (emuskins.com), `Provenance-Emu/SkinKit` (new `SkinKitRetroArch` module), Provenance

## Why

RetroArch is on the App Store, and most of its iOS users play with the stock overlays. Stage 3 gives emuskins.com a client-side converter from a Delta skin to a RetroArch overlay (`.cfg` plus PNGs). What is missing is the last mile: on a phone, the converter's output is a zip in the Downloads folder, and getting it into RetroArch means knowing which folder RetroArch reads and how to point it there. This design makes that one tap where iOS allows it, a short exact recipe where it does not, and gives Provenance a "Send to RetroArch" action that does the conversion natively so a skin a player already likes travels with them.

## What exists today (researched 2026-11-03)

**RetroArch iOS, from `libretro/RetroArch` `master`:**

- `pkg/apple/iOS/Info.plist` registers one URL scheme, `retroarch` (`CFBundleURLTypes`, `CFBundleURLName` `com.retroarch.url`). Its document types are "ROM" (`com.libretro.rom`, `LSHandlerRank` Owner) and "All Files" (`public.data`, `public.content`, rank Alternate). `UTExportedTypeDeclarations` declares about 110 `com.retroarch.<ext>` types, all content formats (`nes`, `sfc`, `gba`, `cue`, `wad`, …); there is no type for an overlay `.cfg` or for a zip. `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` are both true, so the app's `Documents` folder appears in the Files app under On My iPhone › RetroArch, and other apps can save into it.
- `ui/drivers/ui_cocoatouch.m` `application:openURL:options:`: a `retroarch://` URL goes to `openRetroArchURL:`, which understands `retroarch://topshelf?path=&core_path=` (tvOS), `retroarch://start`, `retroarch://game/<filename>` and, when built with `HAVE_RETROARCH_PLAYLIST_MANAGER`, `retroarch://library?scheme=` (hands the game list back to another app). Nothing about overlays, settings or directories. **Any other URL is treated as content**: the file is copied by name into `settings->paths.directory_core_assets` (the "Downloads" directory) unless it is already under Documents, and a database scan is pushed. It is not unzipped and not placed under `overlays`.
- `frontend/drivers/platform_darwin.m` `frontend_darwin_get_env`: on iOS the documents directory is `<Documents>/RetroArch`, `application_data` is the same, and `DEFAULT_DIR_OVERLAY` is `application_data/overlays`, so overlays live at **`Documents/RetroArch/overlays`** (keyboards under `overlays/keyboards`). The list of default directories in the same file spells the base as `~/Documents/RetroArch`.
- Overlay presets (`tasks/task_overlay.c`): a `.cfg` with `overlays = N`; per overlay `overlay<i>_overlay` (background image), `overlay<i>_full_screen`, `overlay<i>_normalized`, `overlay<i>_name`, `overlay<i>_rect`, `overlay<i>_alpha_mod`, `overlay<i>_range_mod`, `overlay<i>_descs = N`; per button `overlay<i>_desc<j> = "<inputs>,<x>,<y>,<radial|rect>,<range_x>,<range_y>"` with optional `_overlay` (its own image), `_alpha_mod`, `_range_mod`, `_saturate_pct` (analog), `_reach_x/_reach_y/_reach_up/_reach_down/_reach_left/_reach_right`. Hitbox types are exactly `radial` and `rect`; analog descs must be `radial`. Inputs are the RetroPad names (`a b x y l r l2 r2 l3 r3 start select up down left right`), `analog_left`/`analog_right`, and actions (`menu_toggle`, `overlay_next`, `save_state`, `load_state`, …); several inputs on one desc are joined with `|`.
- `retroarch.cfg` keys that matter: `input_overlay_enable`, `input_overlay` (the preset path), `input_overlay_opacity`, `input_overlay_scale`, `input_overlay_hide_in_menu`, `input_overlay_behind_menu`, `input_overlay_center_x/y`, `input_overlay_auto_rotate` (`configuration.c`; default on for iOS in `config.def.h`), `overlay_directory`, and the `input_overlay_next` binding. Action inputs in a desc use the bind names without the `input_` prefix that `retroarch.cfg` gives them (`input_menu_toggle` → `menu_toggle`, `input_toggle_fast_forward` → `toggle_fast_forward`). Where RetroArch iOS keeps `retroarch.cfg` under `Documents/RetroArch` I did not verify (see Open questions); the design never needs a user to edit it by hand.

**Ours.** `browse.js` knows when the site runs inside an app (`isInApp`, `ios-install` links) and how to stagger downloads. `SkinKitUI` has `ShareSheet` (a `UIActivityViewController` wrapper) and `SkinCatalogDetailView` with an action section per skin. Provenance's `Info.plist` registers `provenance` and `provenance-ecosystem` URL schemes. The converter (#22) does not exist yet; this design fixes what it must produce and how its mapping is shared.

## Goals

1. From a skin page on emuskins.com on an iPhone, the player gets the overlay into RetroArch's `overlays` folder and knows the three menu taps that turn it on.
2. From Provenance, "Send to RetroArch" on an installed skin does the same with one tap plus a destination pick, using a Swift conversion that produces the same files the website does.
3. The input mapping that both converters use is one JSON file, tested on both sides.
4. A written test plan on a real device, so "loads in RetroArch iOS" (#22's done criterion) means the same thing to everyone.

## Non-goals

- Changing RetroArch. A `retroarch://overlay` URL or an `overlays` document type would be the real one-tap, and §4 proposes the upstream patch, but nothing here waits for it.
- Converting DS touch screens, 3DS second screens, keyboard overlays or Provenance-only inputs that RetroArch has no equivalent for. They are reported, not converted.
- Running RetroArch cores inside Provenance, or reading RetroArch's game library. Out of scope entirely.
- Android or desktop RetroArch. The output works there too (same format), but the delivery paths are iOS-specific.

## Anti-goals

- Two mapping tables that drift. If the website and Provenance disagree on what `cUp` becomes, the feature is broken.
- A delivery step that silently puts the files somewhere RetroArch will not find them. Every path either lands in `overlays` or tells the user exactly where it landed and what to do.
- Overlay images so large RetroArch iOS stalls loading them. Output is bounded.

## Design

### 1. What the converter produces (fixing #22's output contract)

One folder per skin, `<slug>/`, containing `<slug>.cfg` and PNGs. The folder, not a loose `.cfg`, because RetroArch resolves `overlay<i>_overlay` and `_overlay` images relative to the preset and the stock overlays ship as folders too.

- One RetroArch overlay per converted layout, named for RetroArch's auto-rotate: `overlay0_name = "landscape"`, `overlay1_name = "portrait"`. iPhone `edgeToEdge` is preferred, then `standard`; iPad layouts are emitted only when the user asks for an iPad overlay (a separate folder, `<slug>-ipad/`), because one preset is for one device class.
- `overlay<i>_full_screen = true`, `overlay<i>_normalized = true`, every coordinate as a fraction of `mappingSize`; `_alpha_mod` and `_range_mod` left at defaults.
- The background is the layout's `resizable` asset (or the largest size class) rasterized to PNG at 2× the mapping size, capped at 2048 px on the long side. Delta skins keep the game screen transparent; RetroArch draws the game under the overlay, so transparency carries straight through. The `screens[].outputFrame` is not emitted (RetroArch has no screen placement in a preset); the converter reports it so a player can set the video aspect/position if they want to match it.
- Each item becomes a desc: `frame` center and half-sizes plus `extendedEdges` as the hitbox, `rect` for buttons, `radial` for `thumbstick` items mapped to `analog_left`/`analog_right`. A d-pad item becomes nine rect descs (four directions and four diagonals as `up|left` etc., over a 3×3 grid of the frame, centre empty), which is how the stock overlays do it. Per-item Manic artwork becomes the desc's `_overlay` PNG. Alternate layouts (`altRepresentations`) become a second pair of overlays with `overlay_next` descs placed where the skin's `toggleAltRepresentations` button is, so the toggle works in RetroArch too.
- A `README.txt` in the folder with the three menu taps (§3) and the list of inputs that were not converted.

### 2. The shared mapping: `retroarch-input-map.json`

One file, canonical in SkinKit at `Sources/SkinKitRetroArch/Resources/retroarch-input-map.json`, vendored into the site at `docs/js/skin/retroarch-input-map.json`. SkinKit owns it because the Swift module bundles it as a resource and SkinKit has a test suite and tagged releases; the site vendors a copy because GitHub Pages pages should not depend on a cross-origin fetch at runtime and `sw.js` caches the site for offline use. The copy carries the SkinKit tag it came from in a top-level `"source"` field, and `tests/test_retroarch_map.py` in the skins repo fetches that tag's file from `raw.githubusercontent.com` and fails on a byte difference (skipped when offline).

Shape, by example:

```json
{
  "version": 1,
  "source": "SkinKit@0.3.0",
  "common": {
    "menu": "menu_toggle",
    "quickSave": "save_state",
    "quickLoad": "load_state",
    "fastForward": "toggle_fast_forward",
    "toggleFastForward": "toggle_fast_forward",
    "toggleAltRepresentations": "overlay_next",
    "leftThumbstick": "analog_left",
    "rightThumbstick": "analog_right",
    "dpad": ["up", "down", "left", "right"]
  },
  "systems": {
    "nes":     { "assumes": "RetroPad default (Mesen, Nestopia, FCEUmm)", "map": { "a": "a", "b": "b", "start": "start", "select": "select" } },
    "snes":    { "assumes": "RetroPad default (Snes9x, bsnes)", "map": { "a": "a", "b": "b", "x": "x", "y": "y", "l": "l", "r": "r", "start": "start", "select": "select" } },
    "gba":     { "assumes": "RetroPad default (mGBA, VBA-M)", "map": { "a": "a", "b": "b", "l": "l", "r": "r", "start": "start", "select": "select" } },
    "n64":     { "assumes": "Mupen64Plus-Next default", "map": { "a": "a", "b": "b", "z": "l2", "l": "l", "r": "r", "start": "start", "cUp": "analog_right", "cDown": "analog_right", "cLeft": "analog_right", "cRight": "analog_right" }, "aliases": { "c-up": "cUp", "c▲": "cUp" } },
    "genesis": { "assumes": "Genesis Plus GX default", "map": { "a": "y", "b": "b", "c": "a", "x": "l", "y": "x", "z": "r", "mode": "select", "start": "start" } },
    "ds":      { "assumes": "melonDS DS default", "map": { "a": "a", "b": "b", "x": "x", "y": "y", "l": "l", "r": "r", "start": "start", "select": "select" }, "unconvertible": ["touchScreen"] }
  },
  "gameTypes": {
    "com.rileytestut.delta.game.nes": "nes",
    "public.aoshuang.game.nes": "nes"
  }
}
```

Rules the file encodes and both implementations follow: a Delta input not in `map`, `common` or `aliases` is unconvertible and listed in the README; `assumes` names the core whose default RetroPad binding the row matches, so a player on another core knows what to remap; the N64 C buttons map onto `analog_right` as four radial descs at the four poles of one virtual stick (Mupen64Plus-Next reads C buttons from the right stick), which the implementation issue spells out with the exact geometry. The values in the example are the defaults I believe are right; the implementation issue verifies each `assumes` row against the core's `retro_set_controller_port_device` defaults before the file is tagged.

### 3. Delivery from the website (`#23`'s button grows up)

**What "Open in RetroArch" can and cannot do.** Verified above: RetroArch accepts any file through the share sheet ("All Files"), but its handler copies it into the Downloads directory and scans it as content. A zip handed over that way sits in `Documents/RetroArch/downloads/<slug>.zip`, unextracted, where the overlay picker will not look. There is no URL scheme for overlays. So there is no true one-tap on iOS today; the design says that plainly on the page instead of pretending.

**The flow the page offers on iOS Safari**, on the skin page and in `renderModal`, as a "Get for RetroArch" button that replaces #23's plain download:

1. The converter runs in the page and produces the folder as a zip (`<slug>.zip`). Safari saves it to Files › Downloads (default) and shows the download arrow.
2. The page shows the recipe with the exact names, in a numbered list with the folder path copyable:
   - Open **Files**, go to **Downloads**, tap **`<slug>.zip`**: Files unzips it to a folder named `<slug>` beside it.
   - Long-press the **`<slug>`** folder › **Move** › **On My iPhone › RetroArch › RetroArch › overlays** › Move.
   - In RetroArch: **Settings › On-Screen Overlay › Overlay Preset**, browse to **`<slug>/<slug>.cfg`**. To keep it for one game, **Quick Menu › Overrides › Save Game Overrides**.
3. Below the recipe, a copyable `retroarch.cfg` snippet for people who sync or edit configs:
   ```
   input_overlay_enable = "true"
   input_overlay = "~/Documents/RetroArch/overlays/<slug>/<slug>.cfg"
   input_overlay_opacity = "1.000000"
   input_overlay_hide_in_menu = "true"
   ```
   RetroArch expands `~` to the app container on iOS (`platform_darwin.m` lists `~/Documents/RetroArch` as its base).

Two taps fewer are possible through the share sheet: the zip's share arrow › **Save to Files** › pick `RetroArch › RetroArch › overlays` saves the zip straight into `overlays`, and tapping it there unzips in place. The page shows this variant for people who know the share sheet; the Move recipe is the default because it names what is on screen.

**Inside Provenance's web view** (`isInApp`), the button says "Send to RetroArch" and links `provenance://skins/retroarch?skin=<id>`, which hands off to the native path below. Provenance already registers the scheme; the route is new.

### 4. Delivery from Provenance: `SkinKitRetroArch`

**Module.** A new SkinKit target, `SkinKitRetroArch`, depending on `SkinKitCore` and ZIPFoundation only (no UIKit), so it tests on the macOS host with `xcrun swift test`. It has:

- `RetroArchInputMap`: loads the bundled JSON, resolves a Delta input name for a game type to RetroArch inputs, reports unconvertible ones.
- `RetroArchOverlayPreset`: the model of a preset (overlays, descs) and its `cfg` text, written key by key in a stable order so the Swift and JS outputs diff clean.
- `RetroArchOverlayExporter.export(skin: any DeltaSkinProtocol, device: DeltaSkinDevice, options:, rasterize:) throws -> URL`: picks layouts, builds the preset, rasterizes artwork through a caller-supplied `(Data, fileExtension: String, pixelSize: CGSize) -> CGImage?` closure, writes `<slug>/` into a temporary directory and returns it. The closure keeps PDF, PNG and SVG rendering in `SkinKitUI`, which already has it (`UIImage+DeltaSkin`, `SVGRenderer`), and the module itself free of UIKit.

The JS converter (#22) is written against the same preset model (`docs/js/skin/retroarch.js`: `buildPreset(info, traits, map)`, `presetToCfg(preset)`), and a shared fixture set, `Tests/SkinKitRetroArchTests/Fixtures/expected/<skin>/<slug>.cfg` for `fixtures/variants/` skins, is checked byte for byte on both sides. Images are compared by size only, since two rasterizers will not produce identical pixels.

**The action.** `SkinKitUI` gains `RetroArchSendView`, a sheet reached from `SkinCatalogDetailView`'s action section ("Send to RetroArch", shown when the skin is installed and `RetroArchInputMap` knows its game type), from `SystemSkinSelectionView`'s row menu, and from the `provenance://skins/retroarch?skin=` route. It runs the exporter off the main actor, shows what did not convert, then presents `UIDocumentPickerViewController(forExporting: [folderURL], asCopy: true)`. Exporting a **folder** through the document picker is supported and lands the folder itself at the location the user picks; the picker opens at the last location used, so the second time it is "Send to RetroArch" › tap **Save**. The sheet's text names the destination (`On My iPhone › RetroArch › RetroArch › overlays`) and the three menu taps. This is the one-tap-plus-a-pick the issue asks for, with nothing to unzip and no file in Downloads.

A plain share sheet (`ShareSheet`) of the zipped folder is offered as the second button for people who want AirDrop or another app; "Open in RetroArch" is deliberately not offered, because of what RetroArch does with it (§3).

**iFly and iCube** can call the same view; nothing in it is Provenance-specific. They are not in scope for the first release.

### 5. Upstream, in parallel

A small RetroArch patch would make this a real one-tap: in `openRetroArchURL:` handle `retroarch://overlay/install?url=` (download a zip into `overlays/` and extract) or, less invasive, in `application:openURL:options:` route a file whose name ends in `.cfg` and whose zip contains one to `overlays/` instead of `downloads/`. Draft it as a libretro PR once the output format is stable, credit the converter page, and do not plan around it landing.

## Test plan (on a device)

Hardware: an iPhone with a notch or Dynamic Island and an iPad, both on the current iOS. RetroArch from the App Store, and the current TestFlight nightly when the two differ. Skins: `sample-themes-gba`, `sample-alt-ds` (expects the touch screen flagged and `overlay_next` working), `sample-gameoverrides-jaguar` (expects "no mapping for jaguar" until the file has a row), and the top downloaded NES, SNES and GBA skins in the catalog.

1. **Website recipe, Safari on iPhone.** Get for RetroArch › follow the Move recipe › Overlay Preset › pick the cfg. Pass: overlay appears in landscape and portrait, buttons press what their labels say (test every face button, d-pad diagonals, start/select, menu_toggle opens the menu), the overlay is not stretched, and the preset survives a RetroArch relaunch. Note the number of taps.
2. **Share-sheet variant.** Same skin via Save to Files into `overlays` › unzip in place. Pass criteria as 1.
3. **Open in RetroArch, as documented.** Share the zip to RetroArch. Expected: it lands in `Documents/RetroArch/downloads`, no overlay. This confirms the page's wording; if a RetroArch update changes the behaviour, the wording changes.
4. **Provenance "Send to RetroArch".** From the skin's detail view on an iPhone that has RetroArch installed: Send › pick `overlays` › Save. Pass: Files shows `overlays/<slug>/<slug>.cfg` and PNGs, RetroArch loads it with the same results as 1. Repeat from the `provenance://` route opened from the website inside the app.
5. **Alternate layouts.** `sample-alt-ds`: the toggle position flips to the second overlay pair and back.
6. **Auto-rotate.** With RetroArch's overlay auto-rotate on (Settings › On-Screen Overlay), rotating the device switches between the `landscape` and `portrait` overlays. If the setting does not exist in the shipped build, record which build was tested.
7. **Game override.** Quick Menu › Overrides › Save Game Overrides for one game, pick the stock overlay globally, relaunch the game: the skin's overlay comes back for that game only.
8. **Mapping assumptions.** For each `assumes` row, load a game on that core with the core's default binding and press every converted input once. A mismatch is a bug in the JSON, fixed in SkinKit and re-vendored.
9. **Size and speed.** The biggest catalog skin per system converts to under 4 MB of PNG and loads without a visible stall. Record the sizes.
10. **Parity.** `diff` the `.cfg` produced by the website and by Provenance for the same skin and traits: no differences.
11. **Cleanup.** Delete the folder in Files while RetroArch runs; RetroArch falls back without crashing on the next launch.

## Order of work

1. `retroarch-input-map.json` and `SkinKitRetroArch` (model, cfg writer, tests with expected cfgs). This fixes the contract #22 implements.
2. #22 converter page against the same fixtures, #23 button, then the delivery recipe of §3.
3. `RetroArchSendView` and the Provenance route, then the device test plan end to end.
4. Upstream patch draft.

## Calls I made

- **Folder output, not a bare cfg.** Images resolve relative to the preset; the stock overlays are folders; the document picker can export a folder.
- **No "Open in RetroArch" button.** It is verified to land files in `downloads` as content. Offering it would look like it worked.
- **The mapping lives in SkinKit and is vendored into the site**, checked by a test against the tag, rather than fetched at runtime. Offline pages and a tagged source of truth beat one less copy.
- **The Swift module takes a rasterizer closure** so it stays UIKit-free and host-testable, and reuses `SkinKitUI`'s existing PDF/PNG/SVG rendering.
- **C buttons go to `analog_right` poles.** It is what Mupen64Plus-Next reads; an N64 skin with C buttons as digital `x`/`y` would surprise players more.
- **Document picker export over share sheet** for the in-app path: it is the only iOS mechanism that puts a folder exactly where the user points, and it remembers the location.

## Left to the builder

The exact nine-rect d-pad geometry and the C-button pole offsets; PNG scale per device class; the README wording; the `provenance://skins/retroarch` route plumbing in PVUI; how the page detects that RetroArch is installed (it cannot; the recipe assumes it is).

## Follow-up issues

**SkinKitRetroArch: preset model, cfg writer and the shared input map**
**Where:** Provenance-Emu/SkinKit `Package.swift`, `Sources/SkinKitRetroArch/`, `Tests/SkinKitRetroArchTests/`
**Do:** New target depending on `SkinKitCore` and ZIPFoundation. `RetroArchInputMap` over `Resources/retroarch-input-map.json` (shape in the design; verify every `assumes` row against the named core's defaults), `RetroArchOverlayPreset` with a stable-order `cfg` writer, `RetroArchOverlayExporter` with a rasterizer closure, nine-rect d-pads, radial analogs, alt layouts as a second overlay pair with `overlay_next`, unconvertible-input report, 2× capped PNG sizes. Expected `.cfg` fixtures for `fixtures/variants/` skins.
**Depends on:** nothing
**Done when:** `xcrun swift test` passes on the host; the expected cfgs are committed and reviewed against `task_overlay.c`'s parser by loading one in RetroArch iOS.

**Website: converter uses the shared map and matches SkinKit's cfg byte for byte**
**Where:** Provenance-Emu/skins `docs/js/skin/retroarch.js`, `docs/js/skin/retroarch-input-map.json`, `tests/test_retroarch_map.py`, `tests/test_retroarch_cfg.py`
**Do:** Vendor the map with its `source` tag and a test that it matches the tag's file in SkinKit; implement `buildPreset`/`presetToCfg` to the same model; a node CLI the Python tests run over `fixtures/variants/` comparing against SkinKit's expected cfgs.
**Depends on:** the SkinKitRetroArch issue; #22
**Done when:** The cfgs match; the test fails when either copy of the map changes alone.

**Website: "Get for RetroArch" with the Files recipe and cfg snippet**
**Where:** Provenance-Emu/skins `docs/js/browse.js` (`renderModal`), `scripts/generate_skin_pages.py`, `docs/retroarch.html` (the recipe page)
**Do:** Replace #23's download with the zip plus the numbered recipe (Move and Save-to-Files variants), copyable paths and `retroarch.cfg` snippet, the unconvertible list, and `provenance://skins/retroarch?skin=` when `isInApp`. Say plainly that "Open in RetroArch" does not place overlays.
**Depends on:** #23
**Done when:** Test plan steps 1–3 pass on an iPhone and the recipe's tap count is written on the page.

**SkinKitUI/Provenance: "Send to RetroArch" via folder export**
**Where:** Provenance-Emu/SkinKit `Sources/SkinKitUI/Views/RetroArch/RetroArchSendView.swift`, `SkinCatalogDetailView.swift`, `SystemSkinSelectionView.swift`; Provenance `PVUI` URL routing for `provenance://skins/retroarch`
**Do:** The sheet (§4): run the exporter with `SkinKitUI`'s rasterizer, show the report, `UIDocumentPickerViewController(forExporting:asCopy:)` with the folder, share-sheet fallback, destination text. Wire the route.
**Depends on:** the SkinKitRetroArch issue
**Done when:** Test plan steps 4, 5, 7, 10 and 11 pass on a device; iFly and iCube are not required.

**Test plan run and mapping verification on device**
**Where:** Provenance-Emu/SkinKit `docs/testing/retroarch-ios-<date>.md`
**Do:** Run the eleven steps on an iPhone and iPad with the App Store RetroArch (and nightly if different); record build numbers, tap counts, PNG sizes and every mapping mismatch; fix the JSON and re-vendor.
**Depends on:** the three issues above
**Done when:** Every step has a pass or a filed bug, and the map's `version` is bumped if any row changed.

**Upstream: RetroArch iOS overlay install hand-off**
**Where:** libretro/RetroArch `ui/drivers/ui_cocoatouch.m`, `pkg/apple/iOS/Info.plist`
**Do:** Draft a PR adding `retroarch://overlay/install?url=` (download and extract into `overlays`) or routing shared `.cfg`-bearing archives to `overlays`; reference the converter page. Low priority; nothing here depends on it.
**Depends on:** the output format being stable (first two issues merged)
**Done when:** The PR is open and linked from `docs/retroarch.html`.

## Open questions

1. **Where does RetroArch iOS keep `retroarch.cfg`?** `platform_darwin.m` puts everything under `Documents/RetroArch`; I did not confirm the config subfolder. The snippet is for people who already know; the recipe never edits the file.
2. **Does the App Store build expose overlay auto-rotate?** It is in `master` (`input_overlay_auto_rotate`, default on for mobile in `config.def.h`); test plan step 6 records what ships. Without it the page must tell players to pick the landscape or portrait overlay by hand, or we emit two presets.
3. **iPad presets by default, or on request?** The design emits iPad as a separate folder on request. If testing shows players expect one preset for both, emit both into one folder with distinct names.
4. **Should Provenance offer this for skins it did not install from the catalog** (sideloaded files)? The exporter does not care; the button placement does. Default here: yes, anywhere a skin is listed.
5. **The `provenance://skins/retroarch` route** is the first deep link from emuskins.com into the app. Is Joe fine with the scheme carrying skin ids, or should it be a universal link on `emuskins.com` (needs an `apple-app-site-association` file on the site)?
