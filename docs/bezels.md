# TV bezels (`SkinKitBezels`, `SkinKitBezelsUI`)

A TV or monitor drawn around the game picture, and a strip in the pause menu that previews each TV over
the paused game. Shared by Provenance, iFly and iCube. Design: Provenance
`docs/superpowers/specs/2026-11-19-shared-bezel-module-design.md` and `2026-11-19-bezels-on-by-default-design.md`.

## What an app does

1. **Once at launch**, before anything else here is used:

   ```swift
   BezelEnvironment.current = BezelEnvironment(
       libraryRootURL: documents.appendingPathComponent("Bezels"),
       userAgent: "MyApp",
       settings: UserDefaultsBezelSettings(prefix: "myapp.bezel."),   // or the app's own BezelSettingsStore
       systems: { [.init(id: "com.provenance.dreamcast", name: "Dreamcast")] })
   BezelLog.handler = { level, message in /* the app's log */ }
   ```

   System ids are `SystemIdentifier` raw values (`com.provenance.…`): bundled TVs and The Bezel Project's
   table are keyed by them.

2. **Which TV**, whenever the game, the settings or the preview change (main actor):

   ```swift
   let resolved = BezelChoice.resolve(gameID: gameKey, systemID: systemID, systemSuitsTV: true, preview: preview)
   ```

   `gameKey` is whatever the app keys per-game settings by. `systemSuitsTV` is `false` for a system with a
   screen of its own (a handheld), which then gets no TV under Automatic.

3. **Whether it may show**: `GameplayBezelPlacement.showsTV(.init(isAppleTV:isLandscape:controls:layoutSupportsTV:choiceIsAutomatic:))`
   with `choiceIsAutomatic: resolved.resolution.isAutomatic`. Apple TV always; elsewhere in landscape with a
   controller or generated touch controls, never around a skin.

4. **Show it**. Two ways.
   - *Plain* (no shader, works with any presenter): `TVBezelLayout(bezel:container:pictureAspect:)` gives the
     artwork's frame and the picture's. Put `TVBezelArtworkView(bezel:)` behind the game surface for
     `.behindPicture` (a built-in TV) and above it for `.abovePicture` (an image bezel), and give the surface
     `pictureFrame`. `TVBezelStage` does all of that for a SwiftUI surface.
   - *Shader* (glass, reflections, room light): `TVBezelScene.make` off the main thread, kept in
     `TVBezelSceneCache.shared`. Draw the game into a texture the size of the tube, then run the scene's
     preset over the 16:9 scene with `values` as parameters and `borderPNG` as the `BORDER` texture. The app
     needs the `bezel/uborder` presets in its slang library and must set `BezelEnvironment.hasShaderPreset`.
     Image bezels are always plain.

5. **The switcher**: make the emulator screen (or an adapter) a `BezelSwitcherSession` and show
   `BezelSwitcherHost(session:commands:showsControllerHints:onClose:onMore:)` over the paused game, where
   the game stays visible. `onMore` opens `TVBezelPickerView`. Setting `bezelPreview` must redraw the game
   through step 2.

6. **Game artwork** (optional): `await BezelChoice.fetchGameArtwork(for:)`, then resolve again when it
   returns `true`.

## The bundled TVs

`Resources/TVBezels/catalog.json` lists them in the order the picker shows them. Under Automatic a system
gets the TV whose `preferredSystems` lists it, else `living-room-tv`.

| id | Looks like | Automatic for |
|---|---|---|
| `studio-monitor` | A dark broadcast monitor on a shelf | |
| `living-room-tv` | A wood-grain console set of the 1970s and 80s | every other TV system |
| `computer-monitor` | A beige home-computer monitor | C64, Atari ST, MSX, DOS and the other computers |
| `flat-tube-tv` | A silver flat-glass set of about 2000 on an AV stand | Dreamcast, PlayStation 2, GameCube |
| `dorm-tv` | A small black TV with a tape slot and front jacks | |
| `vga-monitor` | A pale grey 19-inch flat-tube PC monitor (a Dreamcast on a VGA box) | |
| `candy-cabinet` | The front of a white sit-down arcade cabinet | Naomi, Naomi 2, Atomiswave |

![Flat-Tube TV](images/bezels/flat-tube-tv.jpg) ![Dorm TV](images/bezels/dorm-tv.jpg)
![VGA Monitor](images/bezels/vga-monitor.jpg) ![Candy Cabinet](images/bezels/candy-cabinet.jpg)

To add one: write `<id>.skin.json` (a format 2 document on the 1920x1080 canvas, drawn from shapes, with
exactly one `screen` node that is 4:3 and centred both ways), add its catalogue entry, and run
`xcrun swift test --filter SkinKitBezelsTests`. No brand names, logos or photographs: the artwork is
drawn, and a TV is named for what it is. `frame` holds the shader path's cabinet colour and glass values
(the tube's place and shape come from the artwork, never from `frame`); `look` is the filter the TV
suggests and may be left out. A system may be listed by one TV only.

## Rules that bite

- **A GPU hang is fatal for the session.** After two GPU restarts iOS refuses every frame the app submits
  until it is relaunched. With the shader path: draw the plain picture while a TV loads, watch each TV
  frame's command buffer, and on `TVFrameFailure.action(for:) == .dropTV` stop drawing the TV for the rest
  of the game. Room light is off by default before Apple GPU family 7 (`TVBezelRoomLight`).
- **No Bezel Project artwork in any repository**, bundle or test fixture. It is downloaded from the
  project's pages when the player asks.
- A `nil` `BezelPreview?` is "no preview"; a preview whose choice is `""` is Off. Do not fold them.
- Stored ids never change: `living-room-tv`, `slang:bezel/…`, `file:<path inside Bezels>`, `auto`, `""`.
