import SkinKit2Core
import SkinKitCore

/// The classic item fields derived from a resolved control, before any artwork is written.
struct ClassicItem: Encodable {
    struct Frame: Encodable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        init(_ rect: Skin2Rect) {
            x = rect.x
            y = rect.y
            width = rect.width
            height = rect.height
        }
    }

    let inputs: DeltaSkin.InputType
    let frame: Frame
    let extendedEdges: Skin2Insets?
    let haptic: Haptic?
    let kind: String?
    let thumbstick: DeltaSkin.ThumbstickConfig?

    struct Haptic: Encodable {
        let style: String?
        let intensity: Double?
    }

    init?(_ control: Skin2ResolvedNode, knob: DeltaSkin.ThumbstickConfig? = nil) {
        guard let kind = control.node.kind else { return nil }
        let names = control.node.inputNames
        switch (kind, control.node.input) {
        case (.dpad, .directions(let directions)):
            inputs = .directional([
                "up": directions.up, "down": directions.down,
                "left": directions.left, "right": directions.right,
            ])
        case (.dpad, _):
            return nil
        case (.thumbstick, _):
            guard case .name(let name) = control.node.input else { return nil }
            let prefix = name.lowercased() == "cstick" ? "rightThumbstick" : name
            inputs = .directional(["up": prefix + "Up", "down": prefix + "Down",
                                   "left": prefix + "Left", "right": prefix + "Right"])
        case (.action, _):
            let supported = names.filter { Self.classicActions.contains($0) }
            guard !supported.isEmpty else { return nil }
            inputs = .single(supported)
        default:
            guard !names.isEmpty else { return nil }
            inputs = .single(names)
        }
        let bounds = control.frame
        frame = Frame(bounds)
        extendedEdges = control.hitFrame.map {
            Skin2Insets(top: bounds.minY - $0.minY, left: bounds.minX - $0.minX,
                        bottom: $0.maxY - bounds.maxY, right: $0.maxX - bounds.maxX)
        }
        haptic = control.node.haptic.map { Haptic(style: $0.style, intensity: $0.intensity) }
        self.kind = kind == .touchSurface ? kind.rawValue : nil
        thumbstick = kind == .thumbstick ? knob : nil
    }

    private static let classicActions: Set<String> = [
        "menu", "quickSave", "quickLoad", "fastForward", "toggleAltRepresentations",
    ]
}
