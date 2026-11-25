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

## Bake a format 2 skin

On macOS, run `xcrun swift run skinkit-bake path/to/skin.json path/to/output`.
The baker reads `assets/` beside the source and writes classic `.deltaskin`
archives with the original format 2 source, a preview, and per-trait PDF artwork.
It writes the base and selectable layouts for each listed game type. Use an
empty output directory to keep the numbered archives separate from earlier bakes.

## Prebuilt XCFrameworks

A version tag resolves to prebuilt XCFrameworks: the tag's `Package.swift` is one
`binaryTarget` per module, pointing at the tag's GitHub Release, so an app that depends on
a version compiles none of SkinKit. The frameworks are dynamic and carry their own
resources (the default font, the bundled TVs, the JSON tables); an app adds nothing to its
Copy Bundle Resources phase. `main` and every other branch build from source.

ZIPFoundation comes from [PVDependencies](https://github.com/Provenance-Emu/PVDependencies),
a prebuilt copy shared with the apps. An app that uses SkinKit takes ZIPFoundation from
there too: a package graph cannot hold that copy and the upstream package at once.

To build a tagged version from source (to step into it in the debugger, say), set
`PV_BUILD_FROM_SOURCE=1` in the environment `xcodebuild` or Xcode starts in, then resolve
packages again.

To release, run **Release XCFramework** from the Actions tab with the new version. Do not
push version tags by hand: such a tag has no binary and builds from source.
[How releases work](https://github.com/Provenance-Emu/.github/blob/main/docs/xcframework-releases.md).
Releases up to 0.7.0 carry static XCFrameworks and a separate resources zip instead;
nothing resolves to those.
