# SkinKit

Shared controller-skin code and planning for [Provenance](https://provenance-emu.com), iFly, iCube and [emuskins.com](https://emuskins.com).

- [ROADMAP.md](ROADMAP.md): stages and what's in each
- [AGENTS.md](AGENTS.md): how to pick up work (for people and AI agents)
- [docs/research.md](docs/research.md): how skins work today across the apps and formats
- [docs/specs/](docs/specs/): designs

The Swift package arrives in stage 1. Work is tracked in this repo's issues.

## GitHub repair agent

After `codex-repair.yml` is merged, maintainers with write access can comment
`@codex fix <instructions>` on an open issue or PR, apply the `codex` label to an issue, or run
**Codex repair** manually with an issue number. Failed pushes to `main` in **CI**
also start a repair. The agent reads the issue and failed job logs, tests a scoped
patch, and opens a draft PR. An existing repair PR suppresses duplicate runs.
PR comments produce a follow-up fix against `main`; they do not edit the original PR branch.

Configure an `OPENAI_API_KEY` Actions secret in this repository or grant access to
an organization secret. Enable **Allow GitHub Actions to create and approve pull
requests** in Settings → Actions → General (the workflow only creates PRs).
This uses the [Codex GitHub Action](https://developers.openai.com/codex/github-action),
with API billing, and needs no Codex cloud environment. The native Codex connector
may still reply about a missing environment; this workflow runs independently.
Native `@codex review` commands remain handled by that connector.

The agent job has read access and no stored checkout credentials. A separate job
publishes the patch without executing it. Fork and PR CI failures never start an
automatic repair. Drafts need maintainer review and are never auto-merged. If a
`GH_PAT` secret is available, it publishes the PR so normal PR workflows can run;
otherwise `GITHUB_TOKEN` is used, and marking the draft ready starts **CI**.

## Prebuilt XCFrameworks

Each release has static XCFrameworks attached, built by [release-xcframeworks.yml](.github/workflows/release-xcframeworks.yml) with [scripts/build-xcframeworks.sh](scripts/build-xcframeworks.sh). There is one per module (`SkinKitCore`, `SkinCatalogKit`, `SkinKitManager`, `SkinKitUI`, `SkinKitRetroArch`, `SkinKit2Core`, `SkinKit2Render`) plus `ZIPFoundation`, with slices for iOS, the iOS simulator, tvOS, the tvOS simulator and Mac Catalyst. They are built with library evolution, so newer compilers can use them.

- Link the modules you use and every module they depend on, `ZIPFoundation` included. Each library holds only its own module's code.
- Static libraries carry no resources. Add the bundles from `SkinKit-Resources-<version>.zip` to the app's Copy Bundle Resources phase. `SkinKitCore`, `SkinKitRetroArch` and `SkinKit2Render` read theirs at runtime.
- `checksums.txt` lists each zip's SwiftPM checksum, for a `.binaryTarget(url:checksum:)`.

To build them locally: `scripts/build-xcframeworks.sh <version> [ios ios-sim tvos tvos-sim catalyst]`. The output goes to `dist/`.
