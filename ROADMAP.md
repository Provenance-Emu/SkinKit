# Roadmap

Controller skins for Provenance, iFly, iCube and emuskins.com. Work is tracked as GitHub issues in this repo, grouped into [milestones](https://github.com/Provenance-Emu/SkinKit/milestones): stages 1–4, then one per theme (Creator features, Editing tools, RetroArch iOS, iCube NES/SNES), and Later for real deferrals. Every issue says what it touches, what it depends on, and what done looks like.

Stages 1–3 are done (stage 3 shipped on the website by 2026-11-04). SkinKit 0.4.0 (2026-11-06) has the first format 2.0 modules and the creator features; app adoption of both is in progress.

## Stage 1: SkinKit shared module (done, 0.1.1)

Move the skin code the three apps already share into this package **with no new features**, and get every app building against it with its controls on screen. Nothing user-visible changes.

- Swift package, multi-module, iOS + tvOS:
  - `SkinKitCore`: the `info.json` model, decoding, and layout/trait resolution. Non-UI.
  - `SkinCatalogKit`: catalog models (lenient decoding), the catalog service, and store sections/policy.
  - `SkinKitManager`: import, install, storage, and the per-game/per-system skin selection.
  - `SkinKitUI`: SwiftUI skin rendering and the store/picker views (iOS/tvOS).
  - Shared fixtures (sample skins) and tests.
- Base: Provenance's skin code, which is the superset. iFly's is a trimmed copy; iCube's is an independent model, so it's the riskiest migration.
- Demo harness: Provenance's `UITesting` app (it has a `DeltaSkins` folder) renders skins from SkinKit.
- Done when Provenance, iFly and iCube each build against SkinKit, show their current controls unchanged, and CI is green.

## Stage 2: Variants, website, catalog health (done, 0.2.0)

Design: [`docs/specs/2026-10-23-skin-variants-design.md`](docs/specs/2026-10-23-skin-variants-design.md).

- **Catalog** (`Provenance-Emu/skins`): `variantLabel`, a generated `variants.json` sidecar, backfill, validation, and sample variant skins.
- **Website**:
  - variant family cards, "Download all", and a "Has variants" filter
  - family-friendly defaults (mature skins hidden unless opted in)
  - the emuskins.com domain move, keeping the old `provenance-emu.com/skins/catalog.json` redirecting for shipped builds
  - page speed (skins#13, Lighthouse 58 against a target of 70)
- **Crawler politeness**: fewer requests to deltastyles, download each file once (thumbnails reuse it), and a User-Agent with a contact link.
- **Apps** (after stage 1's `SkinCatalogKit`):
  - family grouping in the stores and pickers
- **Provenance only** (no dependency on stage 1):
  - Ignited `altRepresentations` and the `toggleAltRepresentations` button, including DS/3DS dual screens
  - a reachable theme picker
  - `gameOverrides` matching by md5, then crc, then filename, then title
  - fix the `sanitizeJSON` bug that cuts `//` inside JSON strings

## Stage 3: RetroArch converter (done)

A standalone Delta-skin → RetroArch overlay converter page on emuskins.com, plus a "Convert to RetroArch" button on each skin. It's our own implementation, credited to warmenhoven/skin2overlay as prior art. Shipped in skins#38, #39 and #44. The remaining check, output loading in RetroArch iOS on a device, is #84 in the RetroArch iOS milestone.

## Stage 4: Skin format 2.0 (in progress)

Notes: [`docs/specs/2026-10-23-skin-format-2-notes.md`](docs/specs/2026-10-23-skin-format-2-notes.md).

Design: [`docs/specs/2026-11-03-skin-format-2-design.md`](docs/specs/2026-11-03-skin-format-2-design.md). Issues #91–#100 and #123.

1. Spike: express iCube's generated GameCube skin in a draft format and render it in a throwaway SwiftUI preview. Done.
2. Write the design document. Done (#58).
3. Swift model, resolver and validator (`SkinKit2Core`, #91, done in 0.4.0) and renderer (`SkinKit2Render`, #92, drawing done in 0.4.0, control host still to do). TypeScript renderer for the website (#93). Both are checked against shared reference images (#95).
4. A baker that turns a 2.0 skin into a classic Delta/Manic skin (PDF plus `info.json`).
5. Convert the generated default skins in all three apps to the format.
6. Publish the format docs on the website and the wiki.

## Creator features

Designs: [profiles](docs/specs/2026-11-03-creator-profiles-design.md), [follows](docs/specs/2026-11-03-follow-creators-design.md), [gamification](docs/specs/2026-11-03-gamification-design.md). Catalog, website and SkinKit parts are done: creator profiles, the claim bot, badges and stats, follows, the follow shelf and achievements (SkinKit 0.4.0). Open: app adoption (#126), iCloud entitlements (#63), achievements wiring (#70), website follows (#65), plus clean-up (#127, #128).

## Editing tools

Design: [`docs/specs/2026-11-03-skin-editing-tools-design.md`](docs/specs/2026-11-03-skin-editing-tools-design.md). Done: the shared client-side skin stack, the editor page, `merge_variants.py`, per-item theme artwork and layout edits. Open: in-game edit mode (#75), the merge tool in the editor (#77), link-health for theme items (#124) and on-device checks (#125).

## RetroArch iOS

Done: the converter and "Get for RetroArch" on the website, and `SkinKitRetroArch` (0.3.0). Open: "Send to RetroArch" from the apps (#83) and the device test plan (#84).

## iCube NES/SNES

Done: the NES and Super NES shelves (0.3.0), the NES fixture, and `sfc` read as Super NES (0.4.0). Open: iCube accepting the skins (#87), Virtual Console detection (#88) and button remapping (#89).

## Later

- Daily local notifications for followed creators (#66).
- Upstream RetroArch iOS overlay install hand-off (#85).

## Done

- 2026-10-22: catalog link-health check, zip-pack repacking, and missing-artwork hiding (skins#17, skins#20).
- 2026-11-03: SkinKit 0.2.0 tagged. Stage 1 (#1–#8) and stage 2 (#9–#21, #34) closed: `gameOverrides` matched by md5 → crc → filename → title, `sanitizeJSON` keeps `//` in strings, Ignited `altRepresentations` with the toggle hotspot, a reachable theme picker, variant families in all three stores and pickers (SkinKit #48–#51; Provenance #3788–#3791; iFly #910; iCube #78–#80). Catalog: `variantLabel`, `variants.json`, sample variant skins, `mature` tag hidden by default, `catalog.min.json` browse index, polite deltastyles crawling, repo opt-out, the move to emuskins.com (skins #21–#33).
- 2026-11-04: SkinKit 0.3.0 tagged: NES and Super NES shelves for iCube, `SkinKitRetroArch`, the creator directory, layout edits, theme item art and the `addedAt` Recent sort (SkinKit #101–#110). Stage 3 closed (skins #37–#39, #44). iCube pins 0.3.0.
- 2026-11-06: SkinKit 0.4.0 tagged: `SkinKit2Core` and `SkinKit2Render`, creator follows, profiles, badges and achievements, `sfc` as Super NES, release XCFrameworks (SkinKit #112–#122). Website and catalog: creator profiles, the claim bot, badges, disputes, the editor page and merged variant families (skins #45–#55). Provenance and iFly move to 0.3.0 (Provenance #3804, iFly #915).
