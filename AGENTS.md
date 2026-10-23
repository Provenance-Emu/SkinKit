# Working on SkinKit (for any agent or LLM tool)

Start here: [ROADMAP.md](ROADMAP.md) for the stages, [docs/research.md](docs/research.md) for what the code does today, and `docs/specs/` for designs.

## Picking up work

1. Pick an open issue with no assignee in the current stage's milestone. Read its whole body and the spec section it links to.
2. Comment on the issue that you're starting it, then branch `<area>/<short-name>` (e.g. `catalog/variant-label`).
3. Work in the repo the issue names. Most issues touch another repo (skins, Provenance, iFly, iCube). The issue lists the paths.
4. Open a PR in that repo. Its description links the issue (`Part of Provenance-Emu/SkinKit#N`) and says how you verified it. Close the issue only when the PR merges.
5. If something in the issue or spec is wrong or unclear, comment on the issue instead of guessing on a decision that changes what gets built.

## Repos and local paths (owner's machine)

| Repo | Local path | What lives there |
|---|---|---|
| Provenance-Emu/SkinKit | `~/Workspace/Provenance/SkinKit` | This hub: roadmap, specs, shared Swift package |
| Provenance-Emu/skins | `~/Workspace/Provenance/skins` | Catalog JSON, crawler, health check, emuskins website (`docs/`). See its `CLAUDE.md` |
| Provenance | `~/Workspace/Provenance/Provenance` | Skin code in `PVUI/Sources/PVUIBase/SwiftUI/DeltaSkins/`; demo harness in `UITesting/` |
| iFly | `~/Workspace/Provenance/iFly/iFly` | Skin code in `Sources/Core/Skins/` and `Sources/UI/Views/Skins/` |
| iCube | `~/Workspace/Provenance/Provenance/Cores/Dolphin/dolphin-ios/Source/iOS/App` | Skin code in `DolphiniOS/UI/Emulation/Skins/`; UI in `Common/UI/Settings/SwiftUI/` |

## Building and testing SkinKit

```bash
xcrun swift test              # non-UI modules on the macOS host (fast)
scripts/ci-test.sh ios        # all modules on an iOS simulator
scripts/ci-test.sh tvos       # all modules on a tvOS simulator
```

Use `xcrun swift`, not bare `swift`. The owner's `PATH` has an old 5.3 toolchain that can't read this package. The package targets iOS 17 / tvOS 17 (the lowest minimum across the three apps) in Swift 5 language mode; macOS 14 is listed only as a test host.

## Rules that bite

- **Never break a skin that works in Delta or Manic today.** New `info.json` keys are additive; the base `representations` must stay a complete skin.
- **The catalog stays one flat `catalog.json`** that old app builds can read. iFly and iCube fetch `https://provenance-emu.com/skins/catalog.json`, so that URL has to keep working through the emuskins.com move.
- **Stage 1 adds no features.** Move code, keep behavior. Put features in their own issues.
- In the skins repo, never hand-edit generated files (`catalog.json`, `docs/systems/`, `docs/authors/`, `thumbnails/`, `link-health.json`, `variants.json`).
- macOS is case-insensitive. Never create paths that differ only by case.
- Be a polite crawler: deltastyles.com rate-limits. Use low concurrency and an honest User-Agent, and never evade blocks.

## Saving tokens

- Use cheap models or subagents for search, file reading and mechanical edits. Save the strongest model for design calls and hard debugging.
- Read the research notes and the spec section before exploring the code. They have file:line pointers.
- Keep PRs scoped to one issue.
