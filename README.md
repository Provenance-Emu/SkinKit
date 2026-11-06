# SkinKit

Shared controller-skin code and planning for [Provenance](https://provenance-emu.com), iFly, iCube and [emuskins.com](https://emuskins.com).

- [ROADMAP.md](ROADMAP.md): stages and what's in each
- [AGENTS.md](AGENTS.md): how to pick up work (for people and AI agents)
- [docs/research.md](docs/research.md): how skins work today across the apps and formats
- [docs/specs/](docs/specs/): designs

The Swift package arrives in stage 1. Work is tracked in this repo's issues.

## Prebuilt XCFrameworks

Each release has static XCFrameworks attached, built by [release-xcframeworks.yml](.github/workflows/release-xcframeworks.yml) with [scripts/build-xcframeworks.sh](scripts/build-xcframeworks.sh). There is one per module (`SkinKitCore`, `SkinCatalogKit`, `SkinKitManager`, `SkinKitUI`, `SkinKitRetroArch`, `SkinKit2Core`, `SkinKit2Render`) plus `ZIPFoundation`, with slices for iOS, the iOS simulator, tvOS, the tvOS simulator and Mac Catalyst. They are built with library evolution, so newer compilers can use them.

- Link the modules you use and every module they depend on, `ZIPFoundation` included. Each library holds only its own module's code.
- Static libraries carry no resources. Add the bundles from `SkinKit-Resources-<version>.zip` to the app's Copy Bundle Resources phase. `SkinKitCore`, `SkinKitRetroArch` and `SkinKit2Render` read theirs at runtime.
- `checksums.txt` lists each zip's SwiftPM checksum, for a `.binaryTarget(url:checksum:)`.

To build them locally: `scripts/build-xcframeworks.sh <version> [ios ios-sim tvos tvos-sim catalyst]`. The output goes to `dist/`.
