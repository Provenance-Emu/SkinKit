// SkinKit2Render: the Core Graphics drawer for resolved skin format 2.0 layouts (section 5, 6.4, 9.1), plus the
// control hit testing of section 6. No UIKit or SwiftUI, so it builds and is tested on the macOS host; SkinKitUI
// hosts it in a SwiftUI `Canvas` through `GraphicsContext.withCGContext`.
//
// The context's user space is canvas points, top-left origin, y down (what SwiftUI's `Canvas` hands over).
// `Skin2Renderer.image(...)` makes such a context over a bitmap for the reference images.

import Foundation
import SkinKit2Core

public enum SkinKit2Render {
    /// Bumped when the module's public API changes.
    public static let version = "0.1.0"

    /// The feature names (section 1) this renderer draws. An app renders `skin.json` only when every entry of the
    /// skin's `requires` is in this set; otherwise it draws the baked classic skin. `effects.ci` is not here:
    /// Core Image entries are skipped, so a skin that lists it falls back to its bake.
    public static let supportedFeatures: Set<String> = [
        "layout.anchors", "layout.stack", "layout.grid", "layout.repeat",
        "shapes.parametric", "shapes.path",
        "paint.gradients", "paint.image",
        "effects.shadow", "effects.blur", "effects.blend",
        "materials", "text",
        "parts", "parts.std@2.0", "tokens", "themes", "variants", "states",
        "controls.dpad", "controls.thumbstick", "controls.touchSurface",
    ]

    /// True when this renderer draws every feature in `requires`.
    public static func supports(_ requires: [String]) -> Bool {
        requires.allSatisfy { supportedFeatures.contains($0) }
    }
}
