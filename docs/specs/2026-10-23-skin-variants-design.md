# Skin variants across the catalog, the site, and the apps

Status: draft for approval · 2026-10-23 · Stage 2 of [ROADMAP.md](../../ROADMAP.md)
Repos: `Provenance-Emu/skins` (catalog + site), Provenance, iFly, iCube (`Provenance/Cores/Dolphin/dolphin-ios/Source/iOS/App`)

## Why

A lot of skins come in variants: one design with a version per game (the Jaguar keypad for Doom, Alien vs Predator, Wolfenstein 3D…), per color, or with a second layout for the same game (DS skins that switch screen arrangement). Today:

- The catalog and website already group variants that ship as **separate files** (`groupId`), but none of the three apps groups them. Users see a flat list of near-identical skins.
- Two **single-file** formats exist that none of the apps fully handle: Ignited's `altRepresentations` (5 DS skins in the catalog) and Provenance's own `themes` / `gameOverrides`. No skin anywhere uses the Provenance formats, so they have never been tested end to end.

The goal is that a variant family looks and behaves like one thing everywhere: on emuskins.com, in each app's store, and in each app's skin picker, whether its variants are separate files or packed in one.

## What exists today (researched 2026-10-23)

**Variant formats in the wild**

| Format | Where it comes from | Shape | Chosen by | Catalog skins using it |
|---|---|---|---|---|
| Split files | Manic, deltastyles, most creators | One `.manicskin`/`.deltaskin` per variant, each with its own `identifier` | The user assigns a skin per game / per system / globally, per orientation (Manic: `StoreLevel` game/gameType/global) | Many. The catalog groups them with `groupId`/`groupOrder`. Example: deltastyles "Atari Jaguar Paw" is 7 separate `.manicskin` files |
| `altRepresentations` | Ignited (LitRitt's Delta fork; `LitRitt/DeltaCore` `ControllerSkin.swift:131-149`) | A full second `representations` tree. If absent, the alternate set is the normal set | A skin button with input `toggleAltRepresentations` flips between the two sets during play | 5 (Ignited DS, epicpal DS+, OBSIDIAN NDS, Titanium One L/R) |
| `gameOverrides` | Provenance only (#3256, for Jaguar keypads) | `gameKey → device → displayType → orientation → representation`. Replaces the whole representation, no per-field merge (`DeltaSkin.swift:317-336`) | Automatic, by game. Only `game.title` is ever passed as the key, though the doc comments promise ROM filename and md5 | 0 |
| `themes` | Provenance only (#3145) | `[{id, name, assets: device → displayType → orientation → assets}]`. Swaps artwork only | The user picks one per skin (UserDefaults `com.provenance.deltaskin.theme.<skinId>`). `DeltaSkinThemePickerView` exists but is never shown | 0 |

Manic itself has no single-file variant format: its `ControllerSkin` reads only the five base keys (`Daiuno/DeltaCore` branch `manicemu`), and importing a second skin with the same `identifier` is rejected. Upstream Delta (`rileytestut/DeltaCore`) has no variant keys either. Both ignore unknown keys, so **a skin with any of the single-file keys above still loads in Delta and Manic as its base layout.**

**The three apps don't share skin code.** iFly's skin model is a trimmed copy of Provenance's (`DeltaSkin.swift`, same type names, no `themes`/`gameOverrides`). iCube has an independent, smaller model (`DolphiniOS/UI/Emulation/Skins/SkinModel.swift`). iCube's store layer was ported from iFly's; the two are near-identical, decode `groupId`/`groupOrder`, and fetch `provenance-emu.com/skins/catalog.json` with the raw GitHub URL as fallback. Provenance's catalog layer is a separate, older, strict design that doesn't decode `groupId` and fetches only the raw GitHub URL. No app uses `groupId` in its UI.

**Dual screens.** Only Provenance renders two screens (DS via melonDS, 3DS via Azahar/emuThree; `PVEmulatorViewController+DualScreen.swift`), and it already handles a `reverseScreens` input. iFly and iCube are single-screen.

## Goals

1. **One variant family, one card.** The site, and the store and skin picker in all three apps, show a variant family as one entry with its variants listed, whether the variants are separate files or packed in one.
2. **Download what you want.** From a family, the user can install one variant, several, or all. For split files the app downloads each chosen file. A single-file skin is one download that carries all its variants.
3. **Single-file variants work in Provenance:**
   - `altRepresentations`: the `toggleAltRepresentations` button switches layouts during play, for DS and 3DS dual-screen skins and any other system.
   - `themes`: the user can pick a theme from the skin's settings.
   - `gameOverrides`: matches by ROM md5, then crc, then ROM filename, then title, as the code's doc comments already promise.
4. **The catalog knows what's inside a skin.** A catalog entry for a single-file skin lists its variants, so the site and stores can show them before download.
5. **Testable.** Sample skins exist for each format, and the apps' test suites use them.

## Non-goals

- Turning split files into single-file skins automatically. Split files don't say which game each variant is for (Manic leaves that to the user), so a merge would guess, and it would lose each file's own download count and identity. A manual merge tool belongs to the later editing-tools project.
- Single-file variant *runtime* support in iFly and iCube. They get grouping (goal 1–2) only. iFly has few Dreamcast skins and no variant demand. iCube is GameCube/Wii, with no per-game keypads. Their decoders must keep ignoring the new keys safely.
- The emuskins.com domain move, the RetroArch converter, creator profiles, and gamification. Those are separate projects.
- Accepting new systems in iCube (NES/SNES). That came up, but it's unrelated to variants.

## Anti-goals (failure even if it works)

- A skin that installs in Delta or Manic today stops working there. Single-file variant keys must stay additive; the base `representations` must remain a complete, working skin.
- Grouping hides attribution. Every variant keeps its own creator credit, source link and download count, even inside a family card.
- A family is shown as one card in one app and as a flat list in another, for the same catalog.

## Design

### 1. Catalog schema (`skins` repo, done first; everything else reads it)

Entries stay flat in `catalog.json` (one entry per downloadable file). Add these optional fields:

- `variantLabel` (string): the variant's own name within its group, e.g. "Doom". It replaces the website's current `stripVariantSuffix` name-parsing (`docs/js/browse.js:646-652`). The crawler, `repack_skins.py` and `migrate_deltastyles.py` fill it in when they set `groupId`. The backfill for existing entries takes the " — label" suffix when there is one. Otherwise it uses the same fallback the website's `variantLabel()` uses today: the entry name with the group name stripped. If that leaves nothing, the field stays unset and the UI shows the full name.
- `variants` (array, single-file skins only): `[{ "kind": "alt" | "theme" | "game", "key": string, "label": string }]`.
  - `alt`: one entry with key `"alt"`, present when `altRepresentations` exists.
  - `theme`: one per `themes[]` item (`key` = theme `id`, `label` = theme `name`).
  - `game`: one per `gameOverrides` key (`key` = the game key, `label` = the same unless a later spec adds labels).

  `variants` is computed from each archive's `info.json` and kept in a generated sidecar, `variants.json` (skin id → `{url, variants}`), never in the hand-edited skin JSON:
  - **`link_health.py`** writes a record for every skin it inspects successfully, whether it passes or fails. It replaces that skin's record each run, and drops it when the skin no longer has variants or its URL changed. This is separate from `link-health.json`, which still records only failures.
  - **The crawler and `process_submission.py`** already read `info.json` when importing (`stream_extract_info_json`), so they write the sidecar record at import time. New skins get `variants` straight away instead of waiting for the weekly run.
  - **`build_catalog.py`** merges a record into an entry only when the record's `url` matches the entry's `downloadURL`. An entry with no record publishes without `variants`; the build never downloads anything itself.
  - **Bootstrap:** the first implementation PR seeds `variants.json` with one full run, so the 5 `altRepresentations` skins have their variants from day one.
- `groupId` / `groupOrder`: unchanged.

`skin_schema.py` validates both new fields. `CATALOG_VERSION` gets bumped. Old clients must ignore the new fields; iFly's and iCube's lossy decoders already do. Provenance's strict decoder must be checked, see §3.

**Health check:** a single-file skin's variant artwork is checked like base artwork. A `themes` or `gameOverrides` layout whose art is missing goes into the existing `partialArtwork` record. It doesn't hide the skin, because the base layout still works.

### 2. Website (`skins/docs`)

- A family card (one per `groupId`, as today) lists its variants by `variantLabel`, with a download button per variant plus **Download all**. "Download all" is a client-side loop over the variants' URLs, so no zip is generated on the server.
- A single-file skin with `variants` shows a "Includes N variants" badge and lists them (for example "Alternate layout", "Doom, AvP, Wolf3D"), with one download.
- Author pages get the same treatment (`generate_author_pages.py:cluster_groups`).
- A "Has variants" filter on the browse page.

### 3. Apps

The family and download logic is the same in all three apps, so it lives in **one new Swift package** that all three depend on. It goes in **`Provenance-Emu/SkinKit`**, a multi-module package. Stage 1 creates its modules by moving the apps' existing code in, including `SkinCatalogKit` from iFly's and iCube's store layer. This project then adds the family features to it:

- `SkinCatalogKit`: catalog models (lossy decoding, all catalog fields including `variantLabel` and `variants`), `SkinFamily` grouping (by `groupId`, ordered by `groupOrder`, standalone entries become families of one), the system/section filtering hooks each app already has, and a download plan. A download plan is the list of URLs to fetch for a chosen set of variants: one per chosen split file, or the single file. It is based on iFly's store layer, the newest of the three, with iCube's additions (`gameTypeSuffix`, `sourceHost`) folded in.
- Each app keeps its own skin *model* and renderer. Those differ a lot and are out of scope to unify.
- **"Download all"** fetches one URL per family member file. A member that is a single-file skin is one download that brings all its own variants, and a family can mix both kinds.

Per app:

| | Provenance | iFly | iCube |
|---|---|---|---|
| Adopt `SkinCatalogKit` for catalog fetch + decode | Yes. This replaces the strict `SkinCatalog`/`SkinCatalogEntry`, and adds the `provenance-emu.com/skins` primary URL with raw GitHub as fallback | Yes (replaces its copy) | Yes (replaces its copy) |
| Store shows families; install one/some/all | Yes | Yes | Yes |
| Store surfaces with families | Catalog browser and detail views on iOS and tvOS (`SkinCatalogBrowserView`, `SkinCatalogDetailView`) | `SkinStoreView` | `SkinStoreView` |
| Installed skins grouped by family in the skin picker | Yes, in `SystemSkinSelectionView` (and `SystemSkinBrowserView` if it lists installed skins). Uses the `.skinmeta` sidecar, which gains `groupId`, `groupOrder` and `variantLabel` | Yes, in its picker. `SkinStoreInstalledRecord` gains the same fields | Yes, in `SkinPickerView`, same fields |
| `altRepresentations` + `toggleAltRepresentations` | Yes. The DS/3DS dual-screen path must use the active set's `screens` | Decode safely and ignore (no toggle) | Decode safely and ignore |
| `themes` picker reachable | Yes. Show `DeltaSkinThemePickerView` in the skin's settings and preview | No | No |
| `gameOverrides` matching by md5 → crc → filename → title | Yes | No | No |

Assignment stays per skin. In the picker a family is a disclosure group, and the user still assigns one specific variant to a game or system, exactly as today. `DeltaSkinListView` (the manage-skins list) is out of scope.

**`altRepresentations` is new code in Provenance.** Nothing in PVUIBase decodes it or handles `toggleAltRepresentations` today. Add the model, decoding, and input handling, mirroring Ignited. It follows Ignited's shape:
- The alternate set is the full `altRepresentations` tree, with the normal representation as a per-trait fallback when the alternate set lacks that trait.
- The toggle flips the active set for the running session.
- Whether the choice persists across launches: **per game, persisted, the same scope as the game's skin pick.** That's my call; Ignited's own behavior here is unverified.
- When the alt set lacks `screens` for a trait, screens fall back to the normal set for that trait.
- Toggling mid-session re-runs the dual-screen layout, including the external- or secondary-display path, so a DS skin whose alt set swaps the screens takes effect immediately.

### 4. Sample skins and tests

The skins repo gets `fixtures/variants/`. It holds small sample skins that use simple generated artwork (solid shapes and labels drawn by a script, not third-party art), so they can be published and bundled without any licensing question:

- `sample-alt-ds.deltaskin`: DS, two layouts, `toggleAltRepresentations` button.
- `sample-themes-gba.deltaskin`: GBA, base plus 2 themes.
- `sample-gameoverrides-jaguar.manicskin`: Jaguar, base keypad plus 3 per-game keypads keyed by title, plus one keyed by an md5.
- `sample-split-family/`: three separate skins sharing a `groupId`, for the grouping path.

- `sample-split-family-dc/` and `sample-split-family-gc/`: the same, for Dreamcast and GameCube, so iFly and iCube can exercise grouping.

They're also published as real catalog entries with their **real** `systems` and `gameTypeIdentifier` (nds, gba, jaguar, dreamcast, gamecube), so they show up in the right pickers and can be assigned to games. They carry `source: "provenance-emu"` and the tag `sample`. Every app's store hides `sample`-tagged entries unless a "Show test skins" developer setting is on, and the website hides them from browse but keeps their direct pages. Each app's tests decode them, and Provenance's tests cover theme selection, override matching order, and the alt toggle. `SkinCatalogKit` tests cover family grouping and download plans against a fixture `catalog.json`.

## Constraints

- The catalog stays one flat `catalog.json` that older app builds can still read.
- `catalog.json` is fetched from `provenance-emu.com/skins/catalog.json` by iFly and iCube. The later emuskins.com move must keep that URL working (a redirect that `URLSession` follows is fine).
- The apps' existing per-game skin assignment (Provenance's md5/crc picks, Manic-style) is unchanged. Families make it easier to pick a variant; they don't replace assignment.

## Order of work

1. Catalog schema, sidecar, backfill, validation, and fixtures (skins repo). Everything else reads these.
2. In parallel once step 1 has merged:
   - website family UI
   - `SkinCatalogKit` package
   - Provenance runtime work (alt toggle, theme picker, override matching), which doesn't depend on the package
3. Each app adopts `SkinCatalogKit` for store and picker grouping (Provenance, iFly and iCube in parallel).

## Calls I made

- **`SkinCatalogKit` is the first module of the new `Provenance-Emu/SkinKit` repo** (you chose a new repo). It holds the catalog and family logic. Each app keeps its own skin model for this project, and moving the models into `SkinKit` is the next project. `SkinKit` can't live inside `skins`, because the thumbnails would make every app's package checkout huge.
- **No automatic merging of split files** (see Non-goals).
- **"Download all" is a client loop, not a server-built zip.** That avoids a second copy of every skin and keeps per-file download counts.
- **`variants` lives in a generated sidecar, not in skin JSON**, so hand-edited entries don't drift from what's in the archive.
- **Alt-layout choice persists per game.**
- **Sample skins use generated art**, so they can be published. They're listed under their real systems, tagged `sample`, and hidden unless a developer setting is on.
- **`variants.json` is written for every inspected skin**, by the health check and at import, and merged only when the URL matches.
- **Provenance UI scope:** the catalog browser and detail views on iOS and tvOS, plus `SystemSkinSelectionView` for picking. A family is a disclosure group; assignment stays per variant.
- **"Download all" is one request per member file**, including mixed families.
- **`variantLabel` backfill** reuses the website's current fallback when there's no " — " suffix.

## What comes next (separate projects, not part of this one)

- **Stage 1 (before this, in parallel for catalog/site work): SkinKit extraction.** The apps' existing skin code moves into SkinKit modules with no behavior change. The app-side parts of this design (§3 grouping) build on it; the catalog, website and Provenance-runtime parts don't wait for it.
- **Stage 4: skin format 2.0.** See `2026-10-23-skin-format-2-notes.md`.

## Left to the builder

Visual design of family cards and pickers; `SkinCatalogKit`'s internal API shape; the fixture-generation script; how each app migrates its installed-skin records to the new fields; test structure.
