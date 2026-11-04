import Foundation

/// A RetroArch overlay preset: the model behind a `.cfg`, and the writer for its text.
///
/// The format is what `tasks/task_overlay.c` reads:
///
///     overlays = N
///     overlayK_name = "landscape" | "portrait"     auto-rotate matches on these words
///     overlayK_overlay = "image.png"               one image per overlay, next to the .cfg
///     overlayK_full_screen = true                  stretch over the whole screen, not the video
///     overlayK_normalized = true                   desc coordinates are 0..1 of the overlay rect
///     overlayK_aspect_ratio = w/h                  the screen ratio the layout assumes (Auto-Scale)
///     overlayK_rect = "x,y,w,h"                    where on the screen the image goes (0..1)
///     overlayK_descs = M
///     overlayK_descJ = "input,x,y,shape,rx,ry"     center x,y and half extents rx,ry, all 0..1
///     overlayK_descJ_overlay = "image.png"         per-button image (thumbstick caps)
///     overlayK_descJ_movable = true                the image follows the finger
///     overlayK_descJ_next_target = "name"          for overlay_next
///     overlayK_descJ_reach_x / _reach_y = 0.0      removes the hitbox (hidden rotate descs)
///
/// `cfg` writes the keys in one fixed order, so two writers (this one and the website's JavaScript) can be diffed.
public struct RetroArchOverlayPreset: Equatable, Sendable {

    /// Hitbox shape of a descriptor. RetroArch has exactly these two.
    public enum Shape: String, Equatable, Sendable {
        case rect
        case radial
    }

    /// An axis-aligned rectangle in whatever space the caller says (0...1 for `Overlay.rect`).
    public struct Rect: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    /// One touch target: `overlayK_descJ`.
    public struct Desc: Equatable, Sendable {
        /// RetroArch inputs this target presses together (joined with `|` in the file): `["up", "left"]`.
        public var inputs: [String]
        /// Center and half extents as fractions of the overlay (0...1).
        public var x: Double
        public var y: Double
        public var shape: Shape
        public var rangeX: Double
        public var rangeY: Double
        /// `_overlay`: the image drawn for this target (a thumbstick cap).
        public var image: String?
        /// `_movable`: the image follows the finger.
        public var movable: Bool
        /// `_next_target`: the overlay `overlay_next` jumps to.
        public var nextTarget: String?
        /// `_reach_x` / `_reach_y`: 0 removes the hitbox.
        public var reachX: Double?
        public var reachY: Double?

        public init(inputs: [String], x: Double, y: Double, shape: Shape, rangeX: Double, rangeY: Double,
                    image: String? = nil, movable: Bool = false, nextTarget: String? = nil,
                    reachX: Double? = nil, reachY: Double? = nil) {
            self.inputs = inputs
            self.x = x
            self.y = y
            self.shape = shape
            self.rangeX = rangeX
            self.rangeY = rangeY
            self.image = image
            self.movable = movable
            self.nextTarget = nextTarget
            self.reachX = reachX
            self.reachY = reachY
        }
    }

    /// One overlay: `overlayK_*`.
    public struct Overlay: Equatable, Sendable {
        public var name: String
        public var image: String
        public var fullScreen: Bool
        public var normalized: Bool
        public var aspectRatio: Double
        public var rect: Rect?
        public var descs: [Desc]

        public init(name: String, image: String, fullScreen: Bool = true, normalized: Bool = true,
                    aspectRatio: Double, rect: Rect? = nil, descs: [Desc] = []) {
            self.name = name
            self.image = image
            self.fullScreen = fullScreen
            self.normalized = normalized
            self.aspectRatio = aspectRatio
            self.rect = rect
            self.descs = descs
        }
    }

    /// Comment lines at the top of the file, without the leading `# `.
    public var headerComments: [String]
    public var overlays: [Overlay]

    public init(headerComments: [String] = [], overlays: [Overlay] = []) {
        self.headerComments = headerComments
        self.overlays = overlays
    }

    // MARK: Writer

    /// The `.cfg` text. Empty for a preset without overlays.
    public var cfg: String {
        guard !overlays.isEmpty else { return "" }
        var lines: [String] = headerComments.map { "# \($0)" }
        lines.append("")
        lines.append("overlays = \(overlays.count)")
        lines.append("")

        for (k, overlay) in overlays.enumerated() {
            let pre = "overlay\(k)"
            lines.append("\(pre)_name = \"\(overlay.name)\"")
            lines.append("\(pre)_overlay = \"\(overlay.image)\"")
            lines.append("\(pre)_full_screen = \(overlay.fullScreen)")
            lines.append("\(pre)_normalized = \(overlay.normalized)")
            lines.append("\(pre)_aspect_ratio = \(Self.fixed6(overlay.aspectRatio))")
            if let r = overlay.rect {
                lines.append("\(pre)_rect = \"\(Self.fixed6(r.x)),\(Self.fixed6(r.y)),\(Self.fixed6(r.width)),\(Self.fixed6(r.height))\"")
            }
            lines.append("\(pre)_descs = \(overlay.descs.count)")
            for (d, desc) in overlay.descs.enumerated() {
                let key = "\(pre)_desc\(d)"
                let geometry = [Self.fixed6(desc.x), Self.fixed6(desc.y), desc.shape.rawValue,
                                Self.fixed6(desc.rangeX), Self.fixed6(desc.rangeY)].joined(separator: ",")
                lines.append("\(key) = \"\(desc.inputs.joined(separator: "|")),\(geometry)\"")
                if let image = desc.image { lines.append("\(key)_overlay = \"\(image)\"") }
                if desc.movable { lines.append("\(key)_movable = true") }
                if let target = desc.nextTarget { lines.append("\(key)_next_target = \"\(target)\"") }
                if let reach = desc.reachX { lines.append("\(key)_reach_x = \(Self.reach(reach))") }
                if let reach = desc.reachY { lines.append("\(key)_reach_y = \(Self.reach(reach))") }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// A number the way the website writes coordinates: rounded to 6 places, always 6 digits.
    ///
    /// `floor(v * 1e6 + 0.5) / 1e6` and `%.6f`, the same arithmetic as JavaScript's
    /// `(Math.round(v * 1e6) / 1e6).toFixed(6)`, with negative zero written as `0.000000`.
    public static func fixed6(_ value: Double) -> String {
        var rounded = (value * 1e6 + 0.5).rounded(.down) / 1e6
        if rounded == 0 { rounded = 0 }
        return String(format: "%.6f", rounded)
    }

    private static func reach(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.1f", value) : "\(value)"
    }
}
