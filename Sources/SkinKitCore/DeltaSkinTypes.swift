import CoreGraphics
import Foundation

/// Core types for DeltaSkin functionality
public enum DeltaSkinDevice: String, Codable, Hashable, Equatable, CaseIterable {
    case iphone
    case ipad
    case tv
}

public enum DeltaSkinDisplayType: String, Codable, Hashable, Equatable, CaseIterable {
    case standard
    case edgeToEdge
    case splitView
    case stageManager    // Stage Manager mode
    case externalDisplay // External display mode
}

public enum DeltaSkinOrientation: String, Codable, Hashable, Equatable, CaseIterable {
    case portrait
    case landscape
}

/// Represents specific iPad models for layout customization
public enum DeltaSkinIPadModel: String, Codable, Hashable, Equatable, CaseIterable {
    case mini    // 8.3"
    case air     // 10.9"
    case pro11   // 11"
    case pro13   // 12.9"

    public var screenSize: CGSize {
        switch self {
        case .mini:   return CGSize(width: 1488, height: 2266)
        case .air:    return CGSize(width: 1640, height: 2360)
        case .pro11:  return CGSize(width: 1668, height: 2388)
        case .pro13:  return CGSize(width: 2048, height: 2732)
        }
    }

    public var aspectRatio: CGFloat {
        screenSize.width / screenSize.height
    }
}

/// Represents display configuration for external screens
public enum DeltaSkinExternalDisplay: String, Codable, Hashable, Equatable, CaseIterable {
    case none      // No external display
    case mirror    // Mirror internal display
    case extended  // Extended desktop mode
    case dedicated // Dedicated game display

    public var supportsFilters: Bool {
        switch self {
        case .none, .mirror: return false
        case .extended, .dedicated: return true
        }
    }
}

public struct DeltaSkinTraits: Codable, Hashable, Equatable {
    public let device: DeltaSkinDevice
    public let displayType: DeltaSkinDisplayType
    public let orientation: DeltaSkinOrientation
    public let iPadModel: DeltaSkinIPadModel?
    public let externalDisplay: DeltaSkinExternalDisplay

    /// Optional game identifier used for per-game skin layout overrides.
    /// Can be a game title, ROM filename (without extension), or MD5 hash.
    public var gameIdentifier: String?

    public init(device: DeltaSkinDevice = .iphone,
                displayType: DeltaSkinDisplayType = .standard,
                orientation: DeltaSkinOrientation = .portrait,
                iPadModel: DeltaSkinIPadModel? = nil,
                externalDisplay: DeltaSkinExternalDisplay = .none,
                gameIdentifier: String? = nil) {
        self.device = device
        self.displayType = displayType
        self.orientation = orientation
        self.iPadModel = iPadModel
        self.externalDisplay = externalDisplay
        self.gameIdentifier = gameIdentifier
    }

    public var description: String {
        var desc = "\(device.rawValue)-\(displayType.rawValue)-\(orientation.rawValue)"
        if let model = iPadModel {
            desc += "-\(model.rawValue)"
        }
        if externalDisplay != .none {
            desc += "-\(externalDisplay.rawValue)"
        }
        if let game = gameIdentifier {
            desc += "-game:\(game)"
        }
        return desc
    }
}

extension DeltaSkinDevice {
    /// Standard image sizes for PNG assets
    public struct ImageSizes {
        public struct Standard {
            /// iPhone SE (2016) - 640x1136
            public static let small = CGSize(width: 640, height: 1136)
            /// iPhone 8 - 750x1334
            public static let medium = CGSize(width: 750, height: 1334)
            /// iPhone 8 Plus - 1080x1920
            public static let large = CGSize(width: 1080, height: 1920)
        }

        public struct EdgeToEdge {
            /// iPhone 11 - 828x1792
            public static let small = CGSize(width: 828, height: 1792)
            /// iPhone 11 Pro - 1125x2436
            public static let medium = CGSize(width: 1125, height: 2436)
            /// iPhone 11 Pro Max - 1242x2688
            public static let large = CGSize(width: 1242, height: 2688)
        }
    }

    /// Returns the appropriate asset size for the current device
    public func assetSize(for displayType: DeltaSkinDisplayType) -> CGSize {
        switch self {
        case .iphone:
            switch displayType {
            case .standard:
                #if IPHONE_ZOOMED
                return ImageSizes.Standard.medium
                #else
                return ImageSizes.Standard.large
                #endif
            case .edgeToEdge:
                return ImageSizes.EdgeToEdge.large
            default:
                return ImageSizes.Standard.large
            }
        case .ipad:
            // iPad always uses PDF assets
            return .zero
        case .tv:
            return .zero
        }
    }
}

// MARK: - CGRect aspect-ratio helper

extension CGRect {
    /// Returns a new rect that fits `self` while maintaining the given `aspectRatio` (width/height),
    /// centred within the original rect.  Used by the skin renderer to enforce native pixel AR.
    public func fitting(aspectRatio: CGFloat) -> CGRect {
        guard aspectRatio > 0, !aspectRatio.isNaN else { return self }
        let currentAR = width / height
        if abs(currentAR - aspectRatio) < 0.001 { return self } // already correct

        let fittedWidth: CGFloat
        let fittedHeight: CGFloat

        if currentAR > aspectRatio {
            // Box is wider than desired → constrain by height
            fittedHeight = height
            fittedWidth = height * aspectRatio
        } else {
            // Box is taller than desired → constrain by width
            fittedWidth = width
            fittedHeight = width / aspectRatio
        }

        let xOffset = (width - fittedWidth) / 2
        let yOffset = (height - fittedHeight) / 2
        return CGRect(x: origin.x + xOffset, y: origin.y + yOffset, width: fittedWidth, height: fittedHeight)
    }
}


/// Filter configuration for screen effects
public struct DeltaSkinFilter: Codable, Hashable, Equatable {
    public let name: String
    public let parameters: [String: FilterParameter]

    public init(name: String, parameters: [String: FilterParameter]) {
        self.name = name
        self.parameters = parameters
    }
}

/// Parameter types for CoreImage filters
public enum FilterParameter: Codable, Hashable, Equatable, Sendable {
    case number(Float)
    case vector(x: Float, y: Float)
    case color(r: Float, g: Float, b: Float)
    case rectangle(x: Float, y: Float, width: Float, height: Float)
    case affineTransform(scaleX: Float?, scaleY: Float?, translateX: Float?, translateY: Float?, rotation: Float?)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let number = try? container.decode(Float.self) {
            self = .number(number)
        } else if let dict = try? container.decode([String: NumericValue].self) {
            if dict.keys.contains("x") && dict.keys.contains("y") &&
               dict.keys.contains("width") && dict.keys.contains("height") {
                self = .rectangle(
                    x: dict["x"]!.value,
                    y: dict["y"]!.value,
                    width: dict["width"]!.value,
                    height: dict["height"]!.value
                )
            } else if dict.keys.contains("x") && dict.keys.contains("y") {
                self = .vector(x: dict["x"]!.value, y: dict["y"]!.value)
            } else if dict.keys.contains("r") && dict.keys.contains("g") && dict.keys.contains("b") {
                self = .color(r: dict["r"]!.value, g: dict["g"]!.value, b: dict["b"]!.value)
            } else if dict.keys.contains("scaleX") || dict.keys.contains("scaleY") || dict.keys.contains("translateX") || dict.keys.contains("translateY") || dict.keys.contains("rotation") {
                let sx = dict["scaleX"]?.value
                let sy = dict["scaleY"]?.value
                let tx = dict["translateX"]?.value
                let ty = dict["translateY"]?.value
                let rot = dict["rotation"]?.value
                self = .affineTransform(scaleX: sx, scaleY: sy, translateX: tx, translateY: ty, rotation: rot)
            } else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Invalid filter parameter format"
                    )
                )
            }
        } else {
            throw DecodingError.typeMismatch(
                FilterParameter.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected number or parameter dictionary"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let value):
            try container.encode(value)
        case .vector(let x, let y):
            try container.encode(["x": x, "y": y])
        case .color(let r, let g, let b):
            try container.encode(["r": r, "g": g, "b": b])
        case .rectangle(let x, let y, let width, let height):
            try container.encode([
                "x": x, "y": y,
                "width": width, "height": height
            ])
        case .affineTransform(let sx, let sy, let tx, let ty, let rot):
            var dict: [String: Float] = [:]
            if let sx = sx { dict["scaleX"] = sx }
            if let sy = sy { dict["scaleY"] = sy }
            if let tx = tx { dict["translateX"] = tx }
            if let ty = ty { dict["translateY"] = ty }
            if let rot = rot { dict["rotation"] = rot }
            try container.encode(dict)
        }
    }
}

/// A type that can decode numbers from various formats (string, int, float)
private struct NumericValue: Codable {
    let value: Float

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let floatValue = try? container.decode(Float.self) {
            value = floatValue
        } else if let intValue = try? container.decode(Int.self) {
            value = Float(intValue) / 255.0 // Convert from 0-255 range
        } else if let stringValue = try? container.decode(String.self),
                  let number = Float(stringValue) {
            value = number > 1.0 ? number / 255.0 : number
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected numeric value"
            )
        }
    }
}

// MARK: - Keyboard Overlay

/// Identifies which virtual keyboard layout to display for keyboard-based systems.
/// Maps to the `VirtualKeyboardLayout` cases defined in the keyboard overlay subsystem.
public enum VirtualKeyboardVariant: String, Codable, Hashable, Equatable, CaseIterable {
    /// Full QWERTY layout (e.g. DOS, generic PC)
    case full
    /// Compact layout — fewer rows, suitable for smaller screens (MSX, Atari 8-bit)
    case compact
    /// Top function-row only (F1–F12 + modifier keys)
    case functionRow
    /// Commodore 64 keyboard layout
    case c64
    /// ZX Spectrum keyboard layout (character + shift rows)
    case zxSpectrum
    /// Amstrad CPC keyboard layout
    case amstradCPC
    /// Atari ST keyboard layout (Help, Undo, Clr/Home, F1-F10)
    case atariST
}


/// Position on screen where the keyboard overlay should appear.
public enum KeyboardOverlayPosition: String, Codable, Hashable, Equatable {
    case bottom
    case top
}

/// Configuration for an optional keyboard overlay embedded in a skin.
/// Skins that omit this key behave as before — no keyboard is shown automatically.
public struct KeyboardOverlayConfig: Codable, Hashable, Equatable {
    /// Which virtual keyboard layout to display
    public let variant: VirtualKeyboardVariant

    /// If `true` the keyboard is shown immediately when the game launches,
    /// without requiring the user to trigger it manually.
    public let autoShow: Bool

    /// Where on screen the overlay should anchor
    public let position: KeyboardOverlayPosition

    /// Overlay opacity in the range 0.0–1.0
    public let opacity: Double

    public init(
        variant: VirtualKeyboardVariant,
        autoShow: Bool = false,
        position: KeyboardOverlayPosition = .bottom,
        opacity: Double = 0.85
    ) {
        self.variant = variant
        self.autoShow = autoShow
        self.position = position
        self.opacity = opacity
    }

    private enum CodingKeys: String, CodingKey {
        case variant, autoShow, position, opacity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        variant = try container.decode(VirtualKeyboardVariant.self, forKey: .variant)
        autoShow = try container.decodeIfPresent(Bool.self, forKey: .autoShow) ?? false
        position = try container.decodeIfPresent(KeyboardOverlayPosition.self, forKey: .position) ?? .bottom
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.85
    }
}



/// Game type identifiers
public enum DeltaSkinGameType: Codable, Hashable, Equatable, Comparable {
    case gb
    case gbc
    case gba
    case nes
    case snes
    case n64
    case nds
    case genesis            // Sega Mega Drive / Genesis
    case gamegear
    case masterSystem
    case psx                // PlayStation (PS1/PSX)
    // Extended support for Manic + others
    case segaCD             // Mega CD / Sega CD
    case sega32X            // 32X
    case sg1000
    case saturn
    case virtualBoy
    case psp
    case threeDS            // 3DS
    case pokemonMini
    case dreamcast
    case naomi              // Sega NAOMI arcade
    case naomi2             // Sega NAOMI 2 arcade
    case atomiswave         // Sammy Atomiswave arcade

    // NEC
    case pce
    case pcecd
    case pcfx
    case sgfx

    // Vectrex
    case vectrex

    // Atari
    case atari2600
    case atari5200
    case atari7800
    case jaguar
    case jaguarcd
    case lynx
    case atari8bit
    case atarist

    // SNK
    case neogeo
    case ngp
    case ngpc

    // Bandai
    case wonderswan
    case wonderswancolor

    // Nintendo
    case gamecube
    case wii

    // Other
    case _3do
    case appleII
    case c64
    case cdi
    case colecovision
    case cps1
    case cps2
    case cps3
    case doom
    case dos
    case ep128
    case intellivision
    case macintosh
    case mame
    case megaduck
    case msx
    case msx2
    case music
    case odyssey2
    case palmos
    case quake
    case quake2
    case retroarch
    case supervision
    case tic80
    case pc98
    case wolf3d
    case zxspectrum

    // Implement Comparable
    public static func < (lhs: DeltaSkinGameType, rhs: DeltaSkinGameType) -> Bool {
        // Order by console generation/release date
        let order: [DeltaSkinGameType] = [
            .gb, .gbc, .gba,        // Nintendo handhelds
            .nes, .snes,            // Nintendo consoles
            .n64,                   // Nintendo 3D
            .nds,                   // Nintendo DS
            .dreamcast,             // Sega Dreamcast
            .naomi, .naomi2, .atomiswave, // Sega/Sammy arcade (Dreamcast-derived)
            .genesis, .gamegear, .masterSystem, .segaCD, .sega32X, .sg1000, // Sega
            .psx, .psp,             // Sony
            .saturn,                // Sega Saturn
            .virtualBoy,            // Nintendo Virtual Boy
            .threeDS,               // Nintendo 3DS
            .pokemonMini,           // Pokemon Mini
            .pce, .pcecd, .pcfx, .sgfx, // NEC
            .vectrex,               // Vectrex
            .atari2600, .atari5200, .atari7800, .jaguar, .jaguarcd, .lynx, .atari8bit, .atarist, // Atari
            .neogeo, .ngp, .ngpc,   // SNK
            .wonderswan, .wonderswancolor, // Bandai
            .gamecube, .wii,        // Nintendo
            ._3do, .appleII, .c64, .cdi, .colecovision, .cps1, .cps2, .cps3, .doom, .dos, .ep128, .intellivision, .macintosh, .mame, .megaduck, .msx, .msx2, .music, .odyssey2, .palmos, .pc98, .quake, .quake2, .retroarch, .supervision, .tic80, .wolf3d, .zxspectrum // Other
        ]

        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }

        return lhsIndex < rhsIndex
    }

    // MARK: - String Decoding Helpers

    /// Create from any known representation: full URN, short code, or suffix (e.g., "com.rileytestut.delta.game.gba", "public.aoshuang.game.ps1", "psx", "md", "sega cd").
    public static func fromAnyString(_ string: String) -> DeltaSkinGameType? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        let lower = trimmed.lowercased()

        // Extract last component after last '.' if it looks like a namespaced id
        let suffix: String = {
            if let last = lower.split(separator: ".").last {
                return String(last)
            }
            return lower
        }()

        // Normalize separators/spaces
        let token = suffix
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")

        // Map of aliases -> canonical case
        switch token {
        // Nintendo
        case "gb": return .gbc
        case "gbc": return .gbc
        case "gba": return .gba
        case "nes", "fds": return .nes
        case "snes": return .snes
        case "n64", "64dd", "n64dd": return .n64
        case "ds", "nds": return .nds
        case "vb", "virtualboy": return .virtualBoy
        case "3ds", "three3ds", "threeds": return .threeDS
        // "ngc" is Manic EMU's GameCube slug (`public.aoshuang.game.ngc`);
        // "wii" is `public.aoshuang.game.wii` (both verified against Manic EMU's
        // open-source `NGC.swift` / `Wii.swift` GameType declarations).
        case "gamecube", "gc", "ngc", "gcn", "nintendogamecube": return .gamecube
        case "wii": return .wii

        // Sega
        case "genesis", "md", "megadrive": return .genesis
        case "gg", "gamegear": return .gamegear
        case "ms", "mastersystem": return .masterSystem
        case "mcd", "segacd", "megacd": return .segaCD
        case "32x", "sega32x": return .sega32X
        case "sg1000": return .sg1000
        case "ss", "saturn": return .saturn
        case "dc", "dreamcast": return .dreamcast
        case "naomi": return .naomi
        case "naomi2": return .naomi2
        case "aw", "atomiswave": return .atomiswave

        // Sony
        case "psx", "ps1", "ps2", "ps3": return .psx
        case "psp": return .psp

        // NEC
        case "pce": return .pce
        case "pcecd": return .pcecd
        case "pcfx": return .pcfx
        case "sgfx", "supergrafx": return .sgfx

        // Vectrex
        case "vectrex": return .vectrex

        // Atari
        case "2600", "a2600", "atari2600": return .atari2600
        case "5200", "a5200", "atari5200": return .atari5200
        case "7800", "a7800", "atari7800": return .atari7800
        case "jaguar", "atarijaguar": return .jaguar
        case "jaguarcd", "atarijaguarcd": return .jaguarcd
        case "lynx", "atarilynx": return .lynx
        case "atari8bit", "atari8": return .atari8bit
        case "atarist", "atariST": return .atarist

        // SNK
        case "neogeo", "neo", "ng": return .neogeo
        case "ngp", "neogeopocket": return .ngp
        case "ngpc", "neogeopocketcolor": return .ngpc

        // Bandai
        case "ws", "wonderswan": return .wonderswan
        case "wsc", "wonderswancolor": return .wonderswancolor

        // Other
        case "pm", "pokemonmini": return .pokemonMini
        case "3do": return ._3do
        case "appleii", "apple2": return .appleII
        case "c64", "commodore64": return .c64
        case "cdi", "philipscdi": return .cdi
        case "colecovision", "coleco": return .colecovision
        case "cps1", "capcomcps1": return .cps1
        case "cps2", "capcomcps2": return .cps2
        case "cps3", "capcomcps3": return .cps3
        case "doom": return .doom
        case "dos": return .dos
        case "ep128", "enterprise128": return .ep128
        case "intellivision": return .intellivision
        case "macintosh", "mac": return .macintosh
        case "mame": return .mame
        case "megaduck": return .megaduck
        case "msx": return .msx
        case "msx2": return .msx2
        case "music": return .music
        case "odyssey2", "odyssey": return .odyssey2
        case "palmos", "palm": return .palmos
        case "pc98", "pc9801", "pc9821": return .pc98
        case "quake": return .quake
        case "quake2": return .quake2
        case "retroarch": return .retroarch
        case "supervision": return .supervision
        case "tic80": return .tic80
        case "wolf3d", "wolfenstein3d": return .wolf3d
        case "zxspectrum", "spectrum": return .zxspectrum
        default:
            // Try to parse known Delta full IDs explicitly
            if lower.hasPrefix("com.rileytestut.delta.game.") {
                let deltaSlug = token
                return fromAnyString(deltaSlug)
            }
            // Try to parse known Manic full IDs explicitly
            if lower.hasPrefix("public.aoshuang.game.") {
                let manicSlug = token
                return fromAnyString(manicSlug)
            }
            return nil
        }
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let val = DeltaSkinGameType.fromAnyString(raw) {
            self = val
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported DeltaSkinGameType string: \(raw)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        // Prefer Delta ID when available, otherwise fall back to Manic ID
        if let delta = self.deltaIdentifierString {
            try container.encode(delta)
        } else if let manic = self.manicIdentifierString {
            try container.encode(manic)
        } else {
            // Fallback to simple case name if nothing else
            try container.encode(String(describing: self))
        }
    }

    // MARK: - Identifier Strings

    /// Stable string key used to look up this system in `system-native-resolutions.json`.
    /// Returns the Swift case name (e.g. `"gamegear"`, `"genesis"`), which is also the
    /// key used as the JSON dictionary key.
    public var registryKey: String { String(describing: self) }

    // MARK: - Platform Controller Grouping (Manic skin parity)

    /// Canonical skin-layout group identifier.
    ///
    /// Systems that share the same controller layout should share a group so that a
    /// single skin file can cover all of them.  Currently defined groups:
    ///
    /// | Group               | Members                        |
    /// |---------------------|-------------------------------|
    /// | `"sega-md-family"`  | Genesis, Sega CD, 32X         |
    /// | `"sega-ms-family"`  | Master System, Game Gear, SG-1000 |
    /// | `"gb-family"`       | Game Boy, Game Boy Color      |
    /// | `"pce-family"`      | PC Engine, PC Engine CD       |
    ///
    /// All other systems use their ``registryKey`` as the group (i.e. they stand alone).
    /// - Note: Consumed by the skin-loader when selecting compatible skins across a platform family.
    public var skinLayoutGroup: String {
        switch self {
        // Mega Drive family: Genesis / Mega CD / 32X share the same 3-button/6-button layout
        case .genesis, .segaCD, .sega32X:
            return "sega-md-family"

        // Master System family: MS / Game Gear / SG-1000 share a 2-button layout
        case .masterSystem, .gamegear, .sg1000:
            return "sega-ms-family"

        // Nintendo Game Boy family: GB and GBC are hardware-compatible
        case .gb, .gbc:
            return "gb-family"

        // NEC PC Engine family: PCE and PCECD share the same controller
        case .pce, .pcecd:
            return "pce-family"

        default:
            return registryKey
        }
    }

    /// Returns true when this system belongs to a multi-member layout group
    /// (i.e. a skin designed for one member may apply to all others in the group).
    /// - Note: Consumed by the skin-loader when filtering compatible skins for a given system.
    public var isInSharedLayoutGroup: Bool {
        skinLayoutGroup != registryKey
    }

    /// Delta-style identifier (when known)
    public var deltaIdentifierString: String? {
        switch self {
        case .gb: return "com.rileytestut.delta.game.gbc"
        case .gbc: return "com.rileytestut.delta.game.gbc"
        case .gba: return "com.rileytestut.delta.game.gba"
        case .nes: return "com.rileytestut.delta.game.nes"
        case .snes: return "com.rileytestut.delta.game.snes"
        case .n64: return "com.rileytestut.delta.game.n64"
        case .nds: return "com.rileytestut.delta.game.ds"
        case .genesis: return "com.rileytestut.delta.game.genesis"
        case .gamegear: return "com.rileytestut.delta.game.gg"
        case .masterSystem: return "com.rileytestut.delta.game.ms"
        case .psx: return "com.rileytestut.delta.game.psx"
        // Not present in Delta's identifiers
        case .dreamcast, .naomi, .naomi2, .atomiswave, .segaCD, .sega32X, .sg1000, .saturn, .virtualBoy, .psp, .threeDS, .pokemonMini, .pce, .pcecd, .pcfx, .sgfx, .vectrex, .atari2600, .atari5200, .atari7800, .jaguar, .jaguarcd, .lynx, .atari8bit, .atarist, .neogeo, .ngp, .ngpc, .wonderswan, .wonderswancolor, .gamecube, .wii, ._3do, .appleII, .c64, .cdi, .colecovision, .cps1, .cps2, .cps3, .doom, .dos, .ep128, .intellivision, .macintosh, .mame, .megaduck, .msx, .msx2, .music, .odyssey2, .palmos, .pc98, .quake, .quake2, .retroarch, .supervision, .tic80, .wolf3d, .zxspectrum:
            return nil
        }
    }

    /// Manic-style identifier (when known)
    public var manicIdentifierString: String? {
        let prefix = "public.aoshuang.game."
        switch self {
        case .gb: return prefix + "gbc"
        case .gbc: return prefix + "gbc"
        case .gba: return prefix + "gba"
        case .nes: return prefix + "nes"
        case .snes: return prefix + "snes"
        case .n64: return prefix + "n64"
        case .nds: return prefix + "ds"
        case .genesis: return prefix + "md"         // Mega Drive
        case .gamegear: return prefix + "gg"
        case .masterSystem: return prefix + "ms"
        case .psx: return prefix + "ps1"
        case .segaCD: return prefix + "mcd"
        case .sega32X: return prefix + "32x"
        case .sg1000: return prefix + "sg1000"
        case .saturn: return prefix + "ss"
        case .virtualBoy: return prefix + "vb"
        case .psp: return prefix + "psp"
        case .threeDS: return prefix + "3ds"
        case .pokemonMini: return prefix + "pm"
        case .dreamcast: return prefix + "dc"
        case .naomi: return prefix + "naomi"
        case .naomi2: return prefix + "naomi2"
        case .atomiswave: return prefix + "aw"
        case .gamecube: return prefix + "ngc"
        case .wii: return prefix + "wii"
        // Not present in Manic's identifiers
        case .pce, .pcecd, .pcfx, .sgfx, .vectrex, .atari2600, .atari5200, .atari7800, .jaguar, .jaguarcd, .lynx, .atari8bit, .atarist, .neogeo, .ngp, .ngpc, .wonderswan, .wonderswancolor, ._3do, .appleII, .c64, .cdi, .colecovision, .cps1, .cps2, .cps3, .doom, .dos, .ep128, .intellivision, .macintosh, .mame, .megaduck, .msx, .msx2, .music, .odyssey2, .palmos, .pc98, .quake, .quake2, .retroarch, .supervision, .tic80, .wolf3d, .zxspectrum:
            return nil
        }
    }


    /// Check whether the game type matches a loose identifier token (e.g., "nes", "md", "ps1").
    public func matchesIdentifier(_ token: String) -> Bool {
        let t = token.lowercased()
        // Match against suffix tokens and both identifier styles
        if let delta = deltaIdentifierString?.split(separator: ".").last?.lowercased(), delta == t { return true }
        if let manic = manicIdentifierString?.split(separator: ".").last?.lowercased(), manic == t { return true }
        // Direct alias matching
        switch (self, t) {
        case (.gb, "gbc"),
             (.gbc, "gbc"),
             (.gba, "gba"),
             (.nes, "nes"), (.nes, "fds"),
             (.snes, "snes"),
             (.n64, "n64"),
             (.nds, "nds"), (.nds, "ds"),
             (.virtualBoy, "vb"), (.virtualBoy, "virtualboy"),
             (.threeDS, "3ds"), (.threeDS, "three3ds"), (.threeDS, "threeds"),
             (.genesis, "genesis"), (.genesis, "md"), (.genesis, "megadrive"),
             (.gamegear, "gg"), (.gamegear, "gamegear"),
             (.masterSystem, "ms"), (.masterSystem, "mastersystem"),
             (.segaCD, "mcd"), (.segaCD, "segacd"), (.segaCD, "megacd"),
             (.sega32X, "32x"), (.sega32X, "sega32x"),
             (.sg1000, "sg1000"),
             (.saturn, "ss"), (.saturn, "saturn"),
             (.dreamcast, "dc"), (.dreamcast, "dreamcast"),
             (.naomi, "naomi"),
             (.naomi2, "naomi2"),
             (.atomiswave, "aw"), (.atomiswave, "atomiswave"),
             (.psx, "psx"), (.psx, "ps1"), (.psx, "ps2"), (.psx, "ps3"),
             (.psp, "psp"),
             (.pokemonMini, "pm"), (.pokemonMini, "pokemonmini"),
             (.pce, "pce"),
             (.pcecd, "pcecd"),
             (.pcfx, "pcfx"),
             (.sgfx, "sgfx"), (.sgfx, "supergrafx"),
             (.vectrex, "vectrex"),
             (.atari2600, "2600"), (.atari2600, "a2600"), (.atari2600, "atari2600"),
             (.atari5200, "5200"), (.atari5200, "a5200"), (.atari5200, "atari5200"),
             (.atari7800, "7800"), (.atari7800, "a7800"), (.atari7800, "atari7800"),
             (.jaguar, "jaguar"), (.jaguar, "atarijaguar"),
             (.jaguarcd, "jaguarcd"), (.jaguarcd, "atarijaguarcd"),
             (.lynx, "lynx"), (.lynx, "atarilynx"),
             (.atari8bit, "atari8bit"), (.atari8bit, "atari8"),
             (.atarist, "atarist"),
             (.neogeo, "neogeo"), (.neogeo, "neo"), (.neogeo, "ng"),
             (.ngp, "ngp"), (.ngp, "neogeopocket"),
             (.ngpc, "ngpc"), (.ngpc, "neogeopocketcolor"),
             (.wonderswan, "ws"), (.wonderswan, "wonderswan"),
             (.wonderswancolor, "wsc"), (.wonderswancolor, "wonderswancolor"),
             (.gamecube, "gamecube"), (.gamecube, "gc"), (.gamecube, "ngc"), (.gamecube, "gcn"),
             (.wii, "wii"),
             (._3do, "3do"),
             (.appleII, "appleii"), (.appleII, "apple2"),
             (.c64, "c64"), (.c64, "commodore64"),
             (.cdi, "cdi"), (.cdi, "philipscdi"),
             (.colecovision, "colecovision"), (.colecovision, "coleco"),
             (.cps1, "cps1"), (.cps1, "capcomcps1"),
             (.cps2, "cps2"), (.cps2, "capcomcps2"),
             (.cps3, "cps3"), (.cps3, "capcomcps3"),
             (.doom, "doom"),
             (.dos, "dos"),
             (.ep128, "ep128"), (.ep128, "enterprise128"),
             (.intellivision, "intellivision"),
             (.macintosh, "macintosh"), (.macintosh, "mac"),
             (.mame, "mame"),
             (.megaduck, "megaduck"),
             (.msx, "msx"),
             (.msx2, "msx2"),
             (.music, "music"),
             (.odyssey2, "odyssey2"), (.odyssey2, "odyssey"),
             (.palmos, "palmos"), (.palmos, "palm"),
             (.pc98, "pc98"), (.pc98, "pc9801"), (.pc98, "pc9821"),
             (.quake, "quake"),
             (.quake2, "quake2"),
             (.retroarch, "retroarch"),
             (.supervision, "supervision"),
             (.tic80, "tic80"),
             (.wolf3d, "wolf3d"), (.wolf3d, "wolfenstein3d"),
             (.zxspectrum, "zxspectrum"), (.zxspectrum, "spectrum"):
            return true
        default:
            return false
        }
    }
}
