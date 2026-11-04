# iCube: NES and SNES skins for Virtual Console, WiiWare and ports

Status: draft for approval · 2026-11-03 · "Later" item of [ROADMAP.md](../../ROADMAP.md), from [SkinKit#26](https://github.com/Provenance-Emu/SkinKit/issues/26)
Repos: iCube (`Provenance/Cores/Dolphin/dolphin-ios/Source/iOS/App`), `Provenance-Emu/SkinKit` (`SkinCatalogKit` shelf presets only)

## Why

A Wii WAD of Super Mario Bros. 3 or Super Metroid is a NES or SNES game, and iCube draws a GameCube pad over it. The catalog has 85 NES and 117 SNES skins against 5 GameCube skins, so for the games people actually play on Virtual Console the skins already exist; iCube just refuses them (`SkinInfo.decode` throws "Unsupported game type" for anything but `gamecube` and `wii`). The same goes for WiiWare titles that are 2D games with a NES-style pad (Mega Man 9, Contra ReBirth) and for disc ports and compilations (Animal Crossing's NES games, Mega Man Anniversary Collection, Sonic Mega Collection), where nothing in the metadata says "this plays like a NES".

## What exists today (researched 2026-11-03)

**Skin model and import (iCube `DolphiniOS/UI/Emulation/Skins/`).**
- `SkinGameType.swift`: `enum SkinGameType { case gameCube, wii }`, built from the last component of `gameTypeIdentifier` (`ngc`/`gc`/`gamecube`, `wii`). `manicIdentifier` and `retargetSuffix` serve the install-time rewrite; `padKinds` says which `TouchOverlayPadKind`s a skin of that type can replace (`gameCube` → `[.gameCube]`, `wii` → the three Wii pads).
- `SkinInfo.swift`: decodes through `SkinKitCore` (`DeltaSkin.Info.decode(_, options: .lenient)`), then maps `DeltaSkinGameType` to `SkinGameType` and throws for everything else. `DeltaSkinGameType` already has `.nes`, `.snes` and `.n64` cases and understands both Delta and Manic spellings.
- `SkinLibrary.swift`: `importSkin(from:retargetingTo:)` unpacks, optionally **rewrites `info.json`** (`retarget(folder:to:)`: `gameTypeIdentifier` becomes the target's Manic id and `identifier` gets `-gamecube`), installs under `<root>/<identifier>/`, and keeps the player's picks in `selection.json` keyed `"<padKind>.<orientation>"`. `select(_:for:orientation:)` refuses a skin whose `gameType.padKinds` does not contain the pad kind.
- `SkinInputMap.swift`: one table per pad kind from skin input names to `TouchOverlayControlKind` (`TouchOverlayDefaults.ButtonID`: `gcA = 0, gcB = 1, gcStart = 2, gcX = 3, gcY = 4, gcZ = 5, gcDpadUp = 6, gcMainStick = 10, gcCStick = 15, gcTriggerL = 20`, `wii* = 100…`, `nunchuk* = 200…`, `classic* = 300…`). **This is how N64 works today**: the GameCube table already knows N64 names (`cUp`/`c-up`/`c▲` → C-stick half-axes, `r1` → Z, `l2`/`r2` → triggers), and the store rewrites an N64 skin to `ngc` on install, so at runtime it is a GameCube skin with N64 labels. The GameCube table has no `select`.
- `SkinLayout.swift`, `SkinOverlayInput.swift`, `SkinOverlayView.swift`: pure layout and hit testing, agnostic of the console once `SkinInputMap` has resolved the inputs.

**Pad choice at runtime** (`Common/Swift/EmulationScreen+TouchAndMotion.swift`): `programmaticPadKind()` returns `.gameCube`, or `.wii(classicActive:sideways:)` from the bound Wii Remote's extension and orientation (`DOLWiimoteBridge`), or `nil`. `SkinMount.overlayChoice(padKind:orientation:library:)` then picks the skin the player selected for that pad kind and orientation. The screen decides Wii vs GameCube with `inferIsWii(from: TVGameItem)`: `gameID` first letter `R`/`S` → Wii, `G` → GameCube, else file extension (`wbfs`/`wad` → Wii, `gcm` → GameCube).

**Game metadata.** `TVGameItem` (`Common/UI/SoftwareList/TVGameItem.h`) exposes `gameID`, `titleIDHex`, `platform` (the raw `DiscIO::Platform`: `gameCubeDisc = 0, triforce = 1, wiiDisc = 2, wiiWAD = 3, elfOrDOL = 4`, mirrored in `DiscIOPlatform` in `Common/Swift/LibraryPlatformCategory.swift`) and `filePath`. The library already sorts games into GameCube / Wii / WiiWare (`LibraryPlatformMapper.detectedCategory`: `wiiWAD` or a `.wad` extension → `.wiiWare`) and lets the player override that per file (`LibraryPlatformOverrideStore`, UserDefaults `library_platform_overrides`, keyed by `filePath`, set from the multi-select Platform menu).

**Store.** `SkinStorePolicy.iCube` (SkinKit `Sources/SkinCatalogKit/SkinStorePolicy.swift`) has shelves `.gameCube`, `.wii`, `.nintendo64` (`SkinStoreSection.swift`; N64 is `retarget: .always("gamecube")`) and `gameTypeSuffixSystemCodes` for `ngc`/`gc`/`gamecube`/`wii`/`n64`. iCube's `SkinKitSetup.libraryInstallStep` turns the retarget id into `SkinGameType(retargetID:)`, which knows only `"gamecube"`. `SkinStoreView.swift` maps shelf ids to header, note and badge copy; `SkinStoreViewModel` groups the catalog by `policy.sections(for:)`. `SkinPickerView.swift` lists installed skins per pad kind (`ControllerSetupSystem.skinPadKinds`) and orientation.

**Virtual Console title ids.** A WAD's `gameID` is four characters; the first says what it is: `F` NES (Famicom), `J` SNES, `N` N64, `L` Master System, `M` Mega Drive, `E` Neo Geo, `C` C64, `X` MSX, `P` TurboGrafx-16, `Q` TurboGrafx-CD, `W` WiiWare, `H` channels. VC and WiiWare titles share the `00010001` title type (`titleIDHex` upper half). Nintendo's VC emulators read the GameCube controller and Classic Controller with fixed mappings: NES `A`/`B` on `A`/`B`, `Start` on `Start`/`+`, `Select` on `Z`/`−`; SNES adds `X`/`Y`/`L`/`R` on the same-named buttons; NES on a sideways Wii Remote uses `2` for `A`, `1` for `B`, `+`/`−` for `Start`/`Select`.

## Goals

1. A NES or SNES Delta/Manic skin installs in iCube from the store or a file, and shows up in the skin picker for the pads that can play it.
2. When a Virtual Console NES or SNES title runs, iCube uses the player's NES or SNES skin automatically, and goes back to the GameCube or Wii skin for everything else.
3. For WiiWare and disc ports the player can say "this game plays like a NES" once, per game, and get the same behaviour.
4. The button mapping follows what Nintendo's VC does on a GameCube pad and a Classic Controller, and the player can change it.

## Non-goals

- Other VC systems (N64 WADs, Master System, Mega Drive, TurboGrafx, Neo Geo, C64, MSX). The N64 shelf already exists as a GameCube-pad layout; a per-game N64 family is an open question. The rest have few or no catalog skins and no demand yet; the design leaves the door open (the family enum is extensible) without building them.
- Changing SkinKit's skin model. `SkinKitCore` already decodes NES and SNES game types; only `SkinCatalogKit` gains two shelf presets.
- Making a NES skin drive the upright Wii Remote with Nunchuk or the GameCube pad's sticks. NES and SNES have no sticks; a skin's `leftThumbstick`, if present, is ignored on those pads as unknown inputs are today.
- Detecting ports from title databases. There is no reliable list of "GameCube discs that are NES games inside"; the per-game override covers it.

## Anti-goals

- A player who never touches Virtual Console sees any change: no new picker tabs, no store shelves they did not ask for, the GameCube pad unchanged.
- A NES skin picked for a GameCube game by mistake silently replaces the GameCube pad for every disc. Family picks are separate from the default pick.
- The N64 path changes behaviour. It keeps rewriting to `ngc` on install and keeps working as a general GameCube layout.

## Design

### 1. `SkinGameType` grows two cases; nothing is rewritten on install

```swift
enum SkinGameType: Equatable {
  case gameCube
  case wii
  case nes
  case snes
}
```

`init?(identifier:)` accepts the suffixes `nes` and `fds` for `.nes` and `snes`/`sfc` for `.snes` (Delta spells them `com.rileytestut.delta.game.nes`/`.snes`; Manic uses `public.aoshuang.game.nes`/`.snes`; the catalog's `SYSTEM_MAP` files `fds` under `nes`). `SkinInfo`'s private `init?(_ kit: DeltaSkinGameType)` maps `.nes` and `.snes` through. `manicIdentifier` returns the Manic ids; `retargetSuffix` is never used for these because **NES and SNES skins install as-is**, unlike N64. The reason: an N64 skin is a GameCube skin with other labels, useful for every GameCube game, so rewriting its type is honest. A NES skin is for NES games; keeping its type is what lets iCube pick it automatically for VC titles and keep it away from Metroid Prime.

`padKinds`:

| `SkinGameType` | Pads it can replace | Why |
|---|---|---|
| `.nes` | `.gameCube`, `.wiiClassic`, `.wiiRemoteSideways` | Every pad a VC NES title accepts |
| `.snes` | `.gameCube`, `.wiiClassic` | SNES VC does not use the sideways remote |

So a NES skin appears in the picker under GameCube, Classic and Sideways; `SkinLibrary.select` keeps refusing a pad the type cannot serve.

### 2. Input retargeting tables

`SkinInputMap` keeps its per-pad tables and gains a first lookup keyed by `(SkinGameType, TouchOverlayPadKind)` for the two new types. `action(for:padKind:)` and `dpad(padKind:)` take the skin's `gameType` (every caller has `SkinInfo` at hand). The defaults follow Nintendo's VC mapping, button name to button name, which is also what the catalog's skins expect of their own labels:

**NES → GameCube pad**

| Skin input | GameCube control | `ButtonID` |
|---|---|---|
| `a` | A | `gcA` |
| `b` | B | `gcB` |
| `start` | Start | `gcStart` |
| `select` | Z | `gcZ` |
| d-pad | D-pad | `gcDpadUp` base |
| `menu`, `quickSave`, `quickLoad` | app actions, unchanged | |

**NES → Classic Controller**: `a` → `classicA`, `b` → `classicB`, `start` → `classicPlus`, `select` → `classicMinus`, d-pad → `classicDpadUp`.

**NES → sideways Wii Remote**: `a` → `wiiTwo`, `b` → `wiiOne`, `start` → `wiiPlus`, `select` → `wiiMinus`, d-pad → `wiiDpadUp` (the sideways pad's rotation is already the overlay's concern, as for the Swift-drawn pad).

**SNES → GameCube pad**: NES rows plus `x` → `gcX`, `y` → `gcY`, `l` → `gcTriggerL` (axis button, full press), `r` → `gcTriggerR`.

**SNES → Classic Controller**: NES rows plus `x` → `classicX`, `y` → `classicY`, `l` → `classicTriggerL`, `r` → `classicTriggerR`.

Why by name and not by position: the VC emulator inside the WAD reads the GameCube pad with Nintendo's fixed mapping (A is A), so the only choice iCube has is which GameCube button a skin's `A` presses, and pressing A is the one that works. SNES `Y` (left) landing on GameCube `Y` (top) feels wrong on the real controller, but on a touch skin the art is where the creator drew it, so the thumb finds the right picture regardless.

**Remappable by the player.** Settings › Controllers › On-Screen Controls › Skins gains "NES buttons" and "SNES buttons": for each of `a`, `b`, `x`, `y`, `l`, `r`, `start`, `select`, a picker of the target pad's buttons, per target pad (GameCube and Classic; Sideways for NES). Stored as JSON in UserDefaults (`skin_vc_remap`), merged over the defaults in `SkinInputMap`, with "Reset to Virtual Console defaults". D-pad and the app actions are fixed. The remap exists because some VC titles (and WiiWare) do not follow Nintendo's defaults and because Dolphin's own controller profile may already be remapped by the player; it is kept small and off the main path.

### 3. Detecting which games are Virtual Console, and letting the player say so

A pure function, `VirtualConsoleFamily.detect(for item: TVGameItem) -> SkinFamily?`, with `enum SkinFamily: String { case nes, snes }` (room for `n64` and others later), in `DolphiniOS/UI/Emulation/Skins/SkinFamily.swift`:

1. If `item.platform == DiscIOPlatform.wiiWAD.rawValue` or the file extension is `wad`, look at `item.gameID.first`: `F` → `.nes`, `J` → `.snes`, anything else → `nil`. `W` (WiiWare) is `nil` on purpose: WiiWare is Wii software and most of it wants a Wii pad.
2. Discs, DOLs and everything else → `nil`.

Then the override: `SkinFamilyOverrideStore`, a copy of `LibraryPlatformOverrideStore` (UserDefaults `skin_family_overrides`, `filePath` → `"nes"`/`"snes"`/`"none"`), consulted first. `"none"` exists so a player can turn detection off for one WAD whose id lies. The override is set from two places that already exist: the game's **Properties** sheet (reached from `LibrarySelectionActionBar`'s Properties action) gets a "Controls layout" row with Auto / GameCube or Wii / NES / SNES, and the in-game pause menu gets the same row so a player who notices mid-game can fix it without leaving. Both call `SkinFamilyOverrideStore.set(_:forFilePath:)` and post `SkinLibrary.didChangeNotification` so the running overlay rebuilds, the way a pick change does today.

`EmulationScreen` computes `activeSkinFamily = SkinFamilyOverrideStore.override(for: game.filePath) ?? VirtualConsoleFamily.detect(for: game)` where it computes `isWiiSystem` (`EmulationScreen.swift` around lines 1227 and 1322) and hands it to the overlay plan.

### 4. Picking the skin: family slots beside the default pick

`SkinLibrary`'s `selection.json` keeps its `"<padKind>.<orientation>"` keys for the default pick and adds `"<padKind>.<orientation>.<family>"` for a family pick. New API:

```swift
func selectedSkin(for padKind: TouchOverlayPadKind, orientation: TouchOverlayOrientation, family: SkinFamily?) -> InstalledSkin?
func select(_ skin: InstalledSkin?, for padKind: TouchOverlayPadKind, orientation: TouchOverlayOrientation, family: SkinFamily?)
```

The two-argument forms stay and mean `family: nil`. Resolution in `SkinMount.overlayChoice(padKind:orientation:family:library:)`: with a family, the family pick if it exists and has a layout for this device and orientation, else the default pick, else `.programmatic`. A family pick is only offered for skins whose `gameType` matches the family (`.nes` skins in the NES slot), so a GameCube skin cannot become the NES pick and the default slot cannot hold a NES skin. That is the rule that keeps a NES skin out of Metroid Prime: it can only ever be chosen into a family slot, and family slots only apply when the running game is of that family.

`SkinPickerView` gets a third segmented control, **Game type**, with "All games" plus one segment per family for which a skin is installed (so it is invisible until the player installs a NES or SNES skin). With a family selected, the list shows that family's skins for the current pad kind and orientation, and the "Swift-drawn (default)" row reads "Same as all games". The thumbnails already render any installed skin.

**Default pad for a VC title.** `programmaticPadKind()` is unchanged: a WAD running with a GameCube controller configured in Dolphin shows the GameCube pad, with a Wii Remote the Wii pads. The NES skin follows that pad kind through `padKinds`. A player who wants the sideways remote for NES VC configures that in Dolphin as today.

### 5. Store: two shelves, filtered like the others

In SkinKit (`SkinCatalogKit`), two presets:

```swift
static let nes = SkinStoreSection(id: "nes", title: "NES", systemCodes: ["nes", "fds"])
static let snes = SkinStoreSection(id: "snes", title: "Super NES", systemCodes: ["snes"])
```

`SkinStorePolicy.iCube` becomes `sections: [.gameCube, .wii, .nintendo64, .nes, .snes]` and `gameTypeSuffixSystemCodes` gains `"nes": "nes"`, `"fds": "nes"`, `"snes": "snes"`, `"sfc": "snes"`. Both shelves are `retarget: .asIs`, so `SkinKitSetup.libraryInstallStep` installs them unchanged (it already passes `nil` when there is no retarget). In iCube, `SkinStoreView`'s private `SkinStoreSection` extension adds header, badge and note copy: header "NES" / "Super NES", badge "NES" / "SNES", note "For Virtual Console and WiiWare games. iCube puts A, B, Start and Select on the GameCube pad or Classic Controller the way the Virtual Console does; the skin picker lets you choose one per game type." The empty-store text changes from "No GameCube or Wii skins" to name the systems the policy lists.

Shelf order puts the two VC shelves after N64 so the first screen of the store is unchanged for GameCube and Wii players. 202 entries is a lot of cards; the shelves are collapsed to one row with "Show all" on the shelf header, which is a `SkinStoreView` change that every shelf gets. `sample`-tagged and `mature`-tagged visibility rules apply as they do to every shelf (`SkinContentVisibility`).

### 6. Settings

Settings › Controllers › On-Screen Controls › Skins:

- **Virtual Console skins** (toggle, default on): when off, `activeSkinFamily` is always `nil`, so family picks are ignored and WADs get the default pick. It exists so a player who prefers one GameCube skin for everything can keep it without deleting NES skins.
- **NES buttons**, **SNES buttons** (§2 remap screens).
- The per-game "Controls layout" row lives in the game's Properties sheet and the pause menu, not here, because it is per game.

### 7. What SkinKit needs

- `SkinCatalogKit`: the two `SkinStoreSection` presets, the `iCube` policy change, tests in `SkinStorePolicyTests` (a NES entry lands on the NES shelf; an entry with `gameTypeIdentifier` `com.rileytestut.delta.game.snes` and no `systems` lands on SNES; a GameCube entry still wins the GameCube shelf). A SkinKit release and iCube's pin bump.
- `SkinKitCore`, `SkinKitManager`: nothing. `DeltaSkinGameType` already has the cases; iCube's `SkinInfo` does the mapping.

### 8. Tests in iCube

`DolphiniOSTests`: `SkinGameType(identifier:)` for the Delta and Manic NES/SNES spellings; `SkinInputMap` tables per `(gameType, padKind)` against the rows in §2, with a remap applied; `VirtualConsoleFamily.detect` on fixture `TVGameItem`s (`F`-id WAD, `J`-id WAD, `W`-id WAD, `G`-id disc, `.wad` extension with empty id); `SkinLibrary` family selection and fallback; `SkinMount.overlayChoice` with and without a family; the installer round trip for a NES fixture skin (a `fixtures/variants`-style NES skin added to SkinKit's test fixtures, as `skinkit/icube-support` did for GameCube).

## Order of work

1. SkinKit: shelf presets and policy (small, releasable alone).
2. iCube: `SkinGameType` cases, `SkinInfo` mapping, `SkinInputMap` tables, store copy. At this point NES/SNES skins install and can be picked under the GameCube pad like any skin. This is a usable first release.
3. iCube: detection, overrides, family slots, picker segment, settings.
4. Remap screens.

## Calls I made

- **Install as-is, not rewritten to `ngc` like N64.** The type is what makes automatic selection possible and keeps NES skins off GameCube discs.
- **Family slots beside the default pick, not a mode.** A player keeps one GameCube skin for all games and adds a NES skin for VC without the two fighting.
- **Detection by WAD + `gameID` letter, override per game.** It is what the metadata can tell us; the override reuses the library's existing per-file override pattern, and covers ports and WiiWare.
- **WiiWare is not a family by default.** Most WiiWare wants a Wii pad; the override is one tap away for the 2D exceptions.
- **Mapping by name, VC defaults, remappable.** It is what the hardware does; the remap handles the exceptions.
- **No N64 family in this project.** Changing a shelf that works for a different purpose is its own decision (open question 1).
- **VC shelves after N64, collapsed.** The store's first screen stays what GameCube and Wii players know.

## Left to the builder

The exact Properties-sheet row and pause-menu placement; the remap screen's layout; the collapsed-shelf affordance; how `activeSkinFamily` reaches `TouchPadsContainer`/`HostedOverlayRoot` (a plain value alongside `isWii`, following the `irMode` pattern); the NES fixture skin's art.

## Follow-up issues

**SkinCatalogKit: NES and Super NES shelves for iCube**
**Where:** Provenance-Emu/SkinKit `Sources/SkinCatalogKit/SkinStoreSection.swift`, `SkinStorePolicy.swift`, `Tests/SkinCatalogKitTests/SkinStorePolicyTests.swift`
**Do:** Add `SkinStoreSection.nes` (`["nes", "fds"]`) and `.snes` (`["snes"]`), both `.asIs`; `SkinStorePolicy.iCube` lists them after `.nintendo64` and maps the `nes`/`fds`/`snes`/`sfc` game-type suffixes. Tests for shelf placement and precedence.
**Depends on:** nothing
**Done when:** Tests pass on the host; a SkinKit release is tagged for iCube to pin.

**iCube: accept NES and SNES skins (model, input tables, store copy)**
**Where:** iCube `DolphiniOS/UI/Emulation/Skins/SkinGameType.swift`, `SkinInfo.swift`, `SkinInputMap.swift`, `Common/UI/Settings/SwiftUI/SkinStoreView.swift`, `DolphiniOSTests/`
**Do:** `.nes`/`.snes` cases with suffixes and `padKinds` (§1); `SkinInfo` maps `DeltaSkinGameType.nes/.snes`; `(gameType, padKind)` tables with the VC defaults (§2) consulted before the pad tables, `select` added; store header/badge/note copy and the empty-state text; collapsed shelves with "Show all". Pin the SkinKit release from the shelf issue. Tests for type parsing and every table row.
**Depends on:** the SkinCatalogKit shelf issue
**Done when:** A catalog NES skin installs from the store, appears in the picker under GameCube, Classic and Sideways, and in a VC NES title every labelled button presses what it says on all three pads; a GameCube skin is unaffected.

**iCube: Virtual Console detection, per-game "Controls layout", family picks**
**Where:** iCube `DolphiniOS/UI/Emulation/Skins/SkinFamily.swift` (new), `SkinLibrary.swift`, `SkinMount.swift`, `Common/Swift/EmulationScreen.swift`, `EmulationScreen+TouchAndMotion.swift`, `Common/UI/Settings/SwiftUI/SkinPickerView.swift`, the game Properties sheet and pause menu, `DolphiniOSTests/`
**Do:** `VirtualConsoleFamily.detect` and `SkinFamilyOverrideStore` (§3); family keys in `selection.json` with the fallback rule (§4); `activeSkinFamily` into the overlay plan; the picker's Game type segment; "Controls layout" row in Properties and the pause menu; "Virtual Console skins" setting (§6). Tests listed in §8.
**Depends on:** the accept-skins issue
**Done when:** Launching a `F`-id WAD uses the NES pick and a GameCube disc the default pick without the player touching anything; setting "Controls layout: NES" on a WiiWare title switches it mid-game; turning the setting off restores the default pick everywhere.

**iCube: NES and SNES button remapping**
**Where:** iCube `Common/UI/Settings/SwiftUI/` (new `SkinVirtualConsoleRemapView.swift`), `DolphiniOS/UI/Emulation/Skins/SkinInputMap.swift`
**Do:** Per-family, per-target-pad pickers for `a b x y l r start select`, stored in UserDefaults `skin_vc_remap`, merged over the defaults, with reset. Tests for merge and reset.
**Depends on:** the accept-skins issue
**Done when:** Swapping NES `a`/`b` in Settings swaps what the skin's buttons press in a running VC title.

**SkinKit: NES fixture skin for iCube's round-trip tests**
**Where:** Provenance-Emu/SkinKit `Tests/SkinKitCoreTests/Fixtures/`, skins `scripts/generate_variant_fixtures.py`
**Do:** A small generated-art NES skin (`a`, `b`, `start`, `select`, d-pad; iPhone and iPad layouts) in the style of `fixtures/variants/`, published like the other samples (tag `sample`) so iCube's store tests can install it.
**Depends on:** nothing
**Done when:** The fixture decodes in SkinKit's tests and installs through iCube's `SkinStoreInstaller` test path.

## Open questions

1. **Should N64 become a family too?** Today an installed N64 skin replaces the GameCube pad for every disc, by design. Making `N`-id WADs auto-pick an N64 skin is a few lines once families exist, but it changes what the N64 shelf means. Joe's call; the design leaves it as is.
2. **WiiWare `W` titles: detect anything?** Some WiiWare is NES-like (Mega Man 9 and 10, Contra ReBirth, Castlevania ReBirth). A small hand-kept list of `gameID`s → family in `SkinFamily.swift` would cover the well-known ones; the per-game override covers the rest. Default here: no list, override only, until someone asks.
3. **Sideways remote for SNES skins?** SNES VC does not accept it, so the design excludes it. If a WiiWare title plays with a sideways remote and a SNES-style skin, the override plus `padKinds` would need `.wiiRemoteSideways` on `.snes` too.
4. **Collapsed shelves for every shelf, or only the VC ones?** The design collapses all for consistency; the N64 shelf (51 entries) benefits too. If GameCube and Wii players dislike the extra tap, collapse only shelves over a size threshold.
5. **Does the remap belong in Dolphin's controller profile instead?** Remapping the touchscreen profile (`Touchscreen.ini`) would also remap the Swift-drawn pad. The design keeps it skin-side so the GameCube pad is untouched; this is the more conservative choice, not the only one.
