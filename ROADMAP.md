# Roadmap

Controller skins for Provenance, iFly, iCube and emuskins.com. Work is tracked as GitHub issues in this repo, one milestone per stage. Every issue says what it touches, what it depends on, and what done looks like.

The stages are ordered by what blocks app releases. Stages 1 and 2 run in parallel.

## Stage 1: SkinKit shared module (target: a few days)

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

## Stage 2: Variants, website, catalog health (parallel with stage 1; doesn't block releases)

Design: [`docs/specs/2026-10-23-skin-variants-design.md`](docs/specs/2026-10-23-skin-variants-design.md).

- **Catalog** (`Provenance-Emu/skins`): `variantLabel`, a generated `variants.json` sidecar, backfill, validation, and sample variant skins.
- **Website**:
  - variant family cards, "Download all", and a "Has variants" filter
  - family-friendly defaults (mature skins hidden unless opted in)
  - the emuskins.com domain move, keeping `provenance-emu.com/skins/catalog.json` working
  - page speed (skins#13, Lighthouse 58 against a target of 70)
- **Crawler politeness**: fewer requests to deltastyles, download each file once (thumbnails reuse it), and a User-Agent with a contact link.
- **Apps** (after stage 1's `SkinCatalogKit`):
  - family grouping in the stores and pickers
- **Provenance only** (no dependency on stage 1):
  - Ignited `altRepresentations` and the `toggleAltRepresentations` button, including DS/3DS dual screens
  - a reachable theme picker
  - `gameOverrides` matching by md5, then crc, then filename, then title
  - fix the `sanitizeJSON` bug that cuts `//` inside JSON strings

## Stage 3: RetroArch converter (any time after stage 2's catalog work)

A standalone Delta-skin → RetroArch overlay converter page on emuskins.com, plus a "Convert to RetroArch" button on each skin. It's our own implementation, credited to warmenhoven/skin2overlay as prior art.

## Stage 4: Skin format 2.0 (tentative, after the app store releases)

Notes: [`docs/specs/2026-10-23-skin-format-2-notes.md`](docs/specs/2026-10-23-skin-format-2-notes.md).

1. Spike: express iCube's generated GameCube skin in a draft format and render it in a throwaway SwiftUI preview.
2. Write the design document.
3. Swift renderer (in `SkinKitUI`) and TypeScript renderer (website), both checked against shared reference images.
4. A baker that turns a 2.0 skin into a classic Delta/Manic skin (PDF plus `info.json`).
5. Convert the generated default skins in all three apps to the format.
6. Publish the format docs on the website and the wiki.

## Later (each needs its own design first)

- Creator profiles (bio, pictures, links), following creators, gamification for creators and users.
- Web and in-app skin editing tools, including merging split variants into one file.
- RetroArch integration on iOS.
- iCube accepting NES/SNES skins (Virtual Console, WiiWare, ports).

## Done

- 2026-10-22: catalog link-health check, zip-pack repacking, and missing-artwork hiding (skins#17, skins#20).
