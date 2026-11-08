import Foundation

/// The standard parts library, `parts.std@2.0` (section 3.9): the controller vocabulary the three apps draw, as
/// parts a skin reaches with `"use": "std.faceButton"`.
///
/// The parts are JSON in `Resources/parts/std.json`, the same file the TypeScript port vendors, so both readers
/// expand them identically. They contain no `$token` references (a skin's token table is not theirs): colours and
/// lengths are parameters with literal defaults, and a skin themes a part by passing its own tokens as arguments:
/// `{"use": "std.faceButton", "id": "a", "with": {"input": "a", "label": "A", "top": "$aTop", "bottom": "$aBottom"}}`.
///
/// | Part | Control | Parameters (besides the defaults noted) |
/// |---|---|---|
/// | `std.faceButton` | button, ellipse body | `input`, `label`, `top`, `bottom`, `glow`, `labelColor`, `shape` |
/// | `std.kidneyButton` | button, kidney body | as `std.faceButton` |
/// | `std.pill` | button, capsule body | as `std.faceButton` |
/// | `std.triggerBar` | trigger (or button), tapered bar | `input`, `label`, `kind`, `taper`, `top`, `bottom`, `labelColor` |
/// | `std.dpad` | dpad, cross with lit arrows | `up`, `down`, `left`, `right`, `top`, `bottom`, `glow`, `arrowColor` |
/// | `std.stick` | thumbstick, dished base, octagonal gate, knob | `input`, `knob`, `top`, `bottom`, `glow` |
/// | `std.stickWithClick` | as `std.stick` plus `click` | `input`, `click`, `knob`, `top`, `bottom`, `glow` |
/// | `std.keypadKey` | button, rounded key | `input`, `label`, `color`, `labelColor`, `cornerRadius` |
///
/// Inner nodes carry ids (`body`, `cross`, `arrow`), so each instance needs an `id`; they are scoped to it
/// (`a.body`). A skin may not define parts named `std.*`.
public enum Skin2StdParts {
    public static let featureName = "parts.std@2.0"
    public static let prefix = "std."

    /// Every standard part by name. Empty if the resource can't be read (a skin that uses one then fails to load
    /// with "no part named", and the app falls back to the baked classic skin).
    public static let library: [String: Skin2JSON] = {
        guard let url = Bundle.module.url(forResource: "std", withExtension: "json", subdirectory: "parts")
                ?? Bundle.module.url(forResource: "std", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? Skin2JSON.parse(data),
              let parts = root["parts"]?.objectValue else { return [:] }
        return parts
    }()

    public static var names: [String] { library.keys.sorted() }
}
