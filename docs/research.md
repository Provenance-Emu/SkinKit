# Research notes (2026-10-23)

What the code and the ecosystem do today. Paths are relative to each repo. Line numbers drift, so search for the symbol if one is off.

## Variant formats in the wild

- **Split files** (Manic, deltastyles, most creators): one skin file per variant, each with its own `identifier`; the user assigns a skin per game, system or globally, per orientation. Manic's source (Manic-EMU/ManicEMU, AGPL-3.0) reads only `name, identifier, debug, gameTypeIdentifier, representations`, and rejects a second import with the same identifier. The catalog groups split files with `groupId`/`groupOrder`.
- **`altRepresentations`** comes from Ignited, LitRitt's fork of Delta (`LitRitt/DeltaCore` `DeltaCore/Model/ControllerSkin.swift:81-149`). It's a full second `representations` tree; a skin without one uses `representations` for both sets. A skin button with input `toggleAltRepresentations` flips the set during play. 5 catalog skins use it, all DS (Ignited DS, epicpal DS+, OBSIDIAN NDS, Titanium One L/R). Upstream `rileytestut/DeltaCore` doesn't have it. Whether Ignited persists the choice is unverified.
- **`themes` / `gameOverrides`** are Provenance only (`DeltaSkin.swift`, PRs #3145, #3256). `themes` swaps artwork; the user picks one, but `DeltaSkinThemePickerView` is never shown anywhere. `gameOverrides` swaps a whole layout per game, but the game key passed is only `game.title` (`EmulatorWithSkinView.swift` sets `gameIdentifier: gameTitle`). No skin anywhere uses either.

## The three apps' skin code isn't shared

- **Provenance** (`PVUI/Sources/PVUIBase/SwiftUI/DeltaSkins/`): the superset.
  - `DeltaSkin.swift` decodes `keyboardOverlay`, `themes`, `gameOverrides`, `caseController`, `backgroundAnimation`, item `haptic`/`states`, and screen `maintainAspectRatio`.
  - Its catalog layer (`Models/SkinCatalog.swift`) is strict, has no `groupId`, and fetches the raw GitHub URL only.
  - Dual screen: `PVEmulatorViewController+DualScreen.swift`, `core.supportsDualScreens` (Azahar, emuThree, melonDS).
  - Special inputs: `DeltaSkinInputHandler.swift` and `PVTouchOverlay/.../TouchInputRole.swift`.
  - Artwork lookup is lenient (`Archive.entry(matchingAssetNamed:)`): exact path, then case-insensitive filename, then the same stem as .pdf/.png/.svg.
- **iFly** (`Sources/Core/Skins/`, `Sources/UI/Views/Skins/`): a trimmed copy of Provenance's model, without themes or gameOverrides. Its store layer (`Store/SkinCatalog*.swift`, `SkinStorePolicy.swift`) is lenient and decodes `groupId`/`groupOrder` but never uses them. It fetches `provenance-emu.com/skins/catalog.json`, falling back to raw GitHub. It accepts Dreamcast/NAOMI/Atomiswave plus MAME and other systems retargeted to the Dreamcast pad.
- **iCube** (`DolphiniOS/UI/Emulation/Skins/`): an independent, smaller model (`SkinModel.swift`) with lossy decoding and `//` stripping. Its store layer was ported from iFly's. It accepts GameCube/Wii, plus N64 retargeted. It uses only the first screen.
- No app groups by `groupId`, and none handles `toggleAltRepresentations`.

## Catalog (Provenance-Emu/skins)

- About 1,270 visible skins. `link_health.py` checks each download weekly, the way the app installs it, including artwork presence. `repack_skins.py` rehosts zip packs on the `mirror` release.
- The website clusters `groupId` families (`docs/js/browse.js` `clusterByGroup`, `generate_author_pages.py` `cluster_groups`) and parses variant names from " — label" suffixes.
- Mature-sounding skins exist ("Ahegao GBA", "Bitches Be Crazy"); there's no content rating yet.
- deltastyles.com returned 403s to the thumbnail job right after the health check's burst. That looks like a rate limit, so crawl politely.

## Delta compatibility

- Delta and Manic draw PDF and PNG artwork only; Provenance also draws SVG.
- Unknown `info.json` keys are ignored by Delta and Manic, so additive keys are safe.
