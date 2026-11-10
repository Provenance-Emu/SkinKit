# Skin format 2.0

Format 2.0 skins describe the game viewport, controls and artwork as a responsive tree in `skin.json`. A baked archive also includes classic `info.json` and artwork so classic readers can install the same file.

The [EmuSkins authoring guide](https://emuskins.com/format/) links to the generated schema reference, a GameCube tutorial and a migration guide for emulator authors. The [format design](https://github.com/Provenance-Emu/SkinKit/blob/main/docs/specs/2026-11-03-skin-format-2-design.md) describes the resolver, renderer and bake rules in detail.

## Record or update a renderer fixture

1. Add or update a fixture under `Tests/Format2Fixtures/`. Keep the source and referenced assets together.
2. Record the expected layouts and images from a SkinKit checkout.

   ```sh
   SKIN2_RECORD=1 xcrun swift test --filter SkinKit2CoreTests
   SKIN2_RECORD=1 xcrun swift test --filter SkinKit2RenderTests
   ```

   Recording deliberately reports a test failure when it rewrites the references. Review the changes and run `xcrun swift test` without the recording flag.
3. After the fixture change merges, refresh the copy in the skins checkout with `node tests/skin2/vendor-fixtures.mjs /path/to/SkinKit/Tests/Format2Fixtures <SkinKit-commit>`. Open a skins PR with the updated fixtures and manifest.

The parity job compares resolved layouts exactly and compares images using the tolerances in the format design. Failed image comparisons attach the actual render and pixel diff to the CI run.
