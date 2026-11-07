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
        "parts", "tokens", "themes", "variants", "states",
        "controls.dpad", "controls.thumbstick", "controls.touchSurface",
    ]

    /// True when this renderer draws every feature in `requires`.
    public static func supports(_ requires: [String]) -> Bool {
        requires.allSatisfy { supportedFeatures.contains($0) }
    }
}

/// The `format2` key of a bundle's `info.json` (section 1): where the 2.0 source is and what it needs.
public struct Skin2SourceInfo: Equatable, Sendable {
    public var source: String
    public var formatVersion: String
    public var requires: [String]

    public init(source: String, formatVersion: String, requires: [String]) {
        self.source = source
        self.formatVersion = formatVersion
        self.requires = requires
    }

    /// Reads `info.json`'s `format2` entry; nil when absent or malformed. `source` defaults to `skin.json`.
    public init?(infoJSON: [String: Any]) {
        guard let f = infoJSON["format2"] as? [String: Any] else { return nil }
        self.init(source: f["source"] as? String ?? "skin.json",
                  formatVersion: f["formatVersion"] as? String ?? "2.0",
                  requires: f["requires"] as? [String] ?? [])
    }

    /// True when this reader should draw `source` instead of the baked classic skin: any `2.x`, every `requires`
    /// entry supported, and a source path that stays inside the bundle.
    public var isRenderable: Bool {
        Skin2SourceInfo.accepts(formatVersion: formatVersion) && SkinKit2Render.supports(requires)
            && !source.isEmpty && !source.hasPrefix("/") && !source.split(separator: "/").contains("..")
    }

    /// A reader accepts any `2.x` (minor bumps add optional keys).
    public static func accepts(formatVersion: String) -> Bool {
        formatVersion.hasPrefix("2.") && formatVersion.count > 2
    }
}
