import Foundation

/// Feature names (section 1): the unit of detection. A skin lists what it uses in `requires`; a reader that lacks
/// one renders the baked classic skin instead. The validator checks `requires` against the skin's content.
public enum Skin2Features {
    public static let all: [String] = [
        "layout.anchors", "layout.stack", "layout.grid", "layout.repeat",
        "shapes.parametric", "shapes.path",
        "paint.gradients", "paint.image",
        "effects.shadow", "effects.blur", "effects.blend", "effects.ci",
        "materials", "text",
        "parts", "tokens", "themes", "variants", "states",
        "controls.dpad", "controls.thumbstick", "controls.touchSurface",
        "parts.std@2.0",
    ]

    /// The features `source` uses. `documents` are its decoded forms (the base and each variant), whose content
    /// may differ; the source supplies tokens, themes, parts and variants, which decoding removes.
    public static func used(source: Skin2JSON, documents: [Skin2Document]) -> Set<String> {
        var used: Set<String> = []
        if let t = source["tokens"]?.objectValue, !t.isEmpty { used.insert("tokens") }
        if let t = source["themes"]?.objectValue, !t.isEmpty { used.insert("themes") }
        if let v = source["variants"]?.objectValue, !v.isEmpty { used.insert("variants") }
        scanUses(source, into: &used)
        for doc in documents { doc.root.preorder { node in Self.scan(node, into: &used) } }
        return used
    }

    private static func scanUses(_ v: Skin2JSON, into used: inout Set<String>) {
        switch v {
        case .object(let o):
            if let name = o["use"]?.stringValue {
                used.insert("parts")
                if name.hasPrefix("std.") { used.insert("parts.std@2.0") }
            }
            for value in o.values { scanUses(value, into: &used) }
        case .array(let a):
            for value in a { scanUses(value, into: &used) }
        default:
            break
        }
    }

    private static func scanLayout(_ l: Skin2Layout?, into used: inout Set<String>) {
        if l?.anchor != nil || l?.offset != nil { used.insert("layout.anchors") }
    }

    private static func scanPaints(_ paints: [Skin2Paint], into used: inout Set<String>) {
        for p in paints {
            switch p.type {
            case .linear, .radial, .angular: used.insert("paint.gradients")
            case .image: used.insert("paint.image")
            case .solid: break
            }
        }
    }

    private static func scanPatch(_ p: Skin2Patch, into used: inout Set<String>) {
        scanLayout(p.layout, into: &used)
        scanPaints(p.fills ?? [], into: &used)
    }

    static func scan(_ n: Skin2Node, into used: inout Set<String>) {
        scanLayout(n.layout, into: &used)
        for w in n.when { scanPatch(w.patch, into: &used) }
        if n.stack != nil { used.insert("layout.stack") }
        if n.grid != nil { used.insert("layout.grid") }
        if n.repeat != nil { used.insert("layout.repeat") }
        if let s = n.shape { used.insert(s.kind == .path ? "shapes.path" : "shapes.parametric") }
        scanPaints(n.fills, into: &used)
        for e in n.effects {
            switch e.type {
            case .shadow: used.insert("effects.shadow")
            case .blur: used.insert("effects.blur")
            case .blend: used.insert("effects.blend")
            case .ci: used.insert("effects.ci")
            }
        }
        if n.material != nil { used.insert("materials") }
        if n.type == .text { used.insert("text") }
        if !n.states.isEmpty {
            used.insert("states")
            for s in n.states.values { for p in s.patch { scanPatch(p, into: &used) } }
        }
        switch n.kind {
        case .dpad?: used.insert("controls.dpad")
        case .thumbstick?: used.insert("controls.thumbstick")
        case .touchSurface?: used.insert("controls.touchSurface")
        default: break
        }
    }
}

/// Which classic input names each game type takes (6.1), for the validator's "inputs vs game type" check.
///
/// This is SkinKit's first such table: the catalog's health check had none. It is data, kept short, and lists
/// the names the three apps' generated pads and classic Delta/Manic skins use. A game type the table doesn't know
/// is reported as a warning and not checked.
public enum Skin2Inputs {
    /// Inputs every game type accepts: directions, start/select, and app actions (which classic skins also put on
    /// buttons).
    public static let common: Set<String> = ["up", "down", "left", "right", "start", "select"]

    /// `action` control inputs (the Provenance `OverlayAction` list that Delta understands, plus Provenance's own).
    public static let actions: Set<String> = [
        "menu", "quickSave", "quickLoad", "fastForward", "toggleFastForward", "toggleAltRepresentations",
        "toggleKeyboard", "screenshot", "rewind", "pause", "reset", "restart",
    ]

    /// `touchSurface` inputs.
    public static let touchSurface: Set<String> = ["touchScreen", "pointer", "lightGun", "trackpad"]

    /// Game type (normalised: the last dotted component, lowercased, no `-`/`_`/spaces) → its system's inputs.
    public static let systems: [String: Set<String>] = {
        let digits: Set<String> = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
        let table: [([String], Set<String>)] = [
            (["nes", "fds", "famicom"], ["a", "b"]),
            (["snes", "sfc"], ["a", "b", "x", "y", "l", "r"]),
            (["gb", "gbc"], ["a", "b"]),
            (["gba"], ["a", "b", "l", "r"]),
            (["n64"], ["a", "b", "l", "r", "z", "cUp", "cDown", "cLeft", "cRight", "leftThumbstick", "analogStick"]),
            (["ds", "nds"], ["a", "b", "x", "y", "l", "r", "touchScreen"]),
            (["3ds"], ["a", "b", "x", "y", "l", "r", "zl", "zr", "home", "leftThumbstick", "rightThumbstick", "cStick", "touchScreen"]),
            (["genesis", "md", "megadrive", "segacd", "mcd", "megacd", "32x", "sega32x"], ["a", "b", "c", "x", "y", "z", "mode"]),
            (["ms", "mastersystem", "gg", "gamegear", "sg1000"], ["a", "b"]),
            (["saturn", "ss"], ["a", "b", "c", "x", "y", "z", "l", "r"]),
            (["psx", "ps1"], ["cross", "circle", "square", "triangle", "l1", "l2", "r1", "r2", "l3", "r3", "leftThumbstick", "rightThumbstick", "analog"]),
            (["psp"], ["cross", "circle", "square", "triangle", "l", "r", "leftThumbstick"]),
            (["dc", "dreamcast"], ["a", "b", "x", "y", "l", "r", "leftThumbstick"]),
            (["gamecube", "gc", "ngc", "gcn"], ["a", "b", "x", "y", "z", "l", "r", "leftThumbstick", "rightThumbstick", "cStick", "mic"]),
            (["wii"], ["a", "b", "one", "two", "plus", "minus", "home", "c", "z", "nunchukStick", "pointer",
                       "x", "y", "l", "r", "zl", "zr", "leftThumbstick", "rightThumbstick"]),
            (["intellivision"], digits.union(["clear", "enter", "topAction", "bottomLeftAction", "bottomRightAction"])),
            (["colecovision", "coleco"], digits.union(["*", "#", "leftAction", "rightAction"])),
        ]
        var out: [String: Set<String>] = [:]
        for (names, inputs) in table { for n in names { out[n] = inputs } }
        return out
    }()

    /// `com.rileytestut.delta.game.snes` → `snes`.
    public static func normalize(_ gameType: String) -> String {
        let last = gameType.lowercased().split(separator: ".").last.map(String.init) ?? gameType.lowercased()
        return last.filter { $0 != "-" && $0 != "_" && $0 != " " }
    }

    /// The inputs a game type accepts besides `common` and `actions`, or nil when the table doesn't know it.
    public static func inputs(forGameType gameType: String) -> Set<String>? {
        systems[normalize(gameType)]
    }
}
