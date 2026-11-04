import Foundation
import SkinKitCore

/// The parts of a skin's `info.json` the RetroArch converter reads, taken from the raw JSON.
///
/// This reads the dictionary, not `DeltaSkin.Info`, on purpose: the decoded model fills in per-side
/// `extendedEdges` defaults, drops the original `gameTypeIdentifier` text (which picks the input-map row) and
/// rejects types it does not know. The converter needs each of those as the file wrote them, so the cfg comes out
/// the same as the website's, which reads the same JSON.
public struct RetroArchSkinInfo {

    /// A rectangle in mapping points.
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

    /// Per-side extended touch edges; a nil side is "not specified".
    struct Edges {
        var top: Double?
        var bottom: Double?
        var left: Double?
        var right: Double?
    }

    /// What an item's `inputs` said.
    enum Inputs {
        /// `["a", "b"]`: buttons pressed together.
        case list([String])
        /// `{"up": "up", "down": "down", ...}`: a four-way pad or a stick.
        case directions([String: String])
        /// Missing or not a list or dictionary.
        case none
    }

    struct Thumbstick {
        var name: String?
        var width: Double?
        var height: Double?
    }

    struct Item {
        /// Nil when the item has no usable frame; such items are skipped.
        var frame: Rect?
        var edges: Edges
        var inputs: Inputs
        var thumbstick: Thumbstick?
    }

    struct Assets {
        var resizable: String?
        var large: String?
        var medium: String?
        var small: String?

        /// The artwork file for a layout: a resizable PDF/SVG first, else the largest raster.
        var preferred: String? { [resizable, large, medium, small].compactMap { $0 }.first { !$0.isEmpty } }
    }

    /// One (device, display type, orientation) layout with artwork.
    struct Layout {
        var device: String
        var displayType: String
        var orientation: String
        var assets: Assets
        var mappingWidth: Double
        var mappingHeight: Double
        var edges: Edges?
        var translucent: Bool
        var items: [Item]
        var screenFrames: [Rect]
    }

    public let name: String?
    public let identifier: String?
    public let gameTypeIdentifier: String?
    /// Whether `gameOverrides` is present. The converter does not read them; it notes that it did not.
    public let hasGameOverrides: Bool

    let layouts: [Layout]
    let altLayouts: [Layout]

    // MARK: Parsing

    /// Reads an `info.json` body the way the website does: BOM, `//` and `/* */` comments and trailing commas are
    /// tolerated, since skins in the wild have them.
    public init(infoJSON data: Data) throws {
        var text = String(decoding: data, as: UTF8.self)
        if text.unicodeScalars.first == "\u{FEFF}" { text.unicodeScalars.removeFirst() }
        let cleaned = Self.stripComments(text)
        guard let object = try JSONSerialization.jsonObject(with: Data(cleaned.utf8)) as? [String: Any] else {
            throw DeltaSkinError.invalidInfoFile
        }
        self.init(json: object)
    }

    /// From a skin's raw `info.json` dictionary (`DeltaSkinProtocol.jsonRepresentation`).
    public init(json: [String: Any]) {
        name = json["name"] as? String
        identifier = json["identifier"] as? String
        gameTypeIdentifier = json["gameTypeIdentifier"] as? String
        hasGameOverrides = Self.isTruthy(json["gameOverrides"])
        layouts = Self.listLayouts(json["representations"])
        altLayouts = Self.listLayouts(json["altRepresentations"])
    }

    /// From a loaded skin, through its raw `info.json`.
    public init(skin: some DeltaSkinProtocol) {
        self.init(json: skin.jsonRepresentation)
    }

    // MARK: JSON helpers

    /// Strips line and block comments and trailing commas that sit outside strings, like SkinKitCore's
    /// `sanitizeJSON`. Strings are copied through untouched.
    static func stripComments(_ text: String) -> String {
        let c = Array(text.unicodeScalars)
        var out = String.UnicodeScalarView()
        var inString = false, escaped = false, lineComment = false, blockComment = false
        var i = 0
        while i < c.count {
            let ch = c[i]
            let next: Unicode.Scalar? = i + 1 < c.count ? c[i + 1] : nil
            if lineComment {
                if ch == "\n" || ch == "\r" { lineComment = false; out.append(ch) }
                i += 1
                continue
            }
            if blockComment {
                if ch == "*" && next == "/" { blockComment = false; i += 1 }
                i += 1
                continue
            }
            if inString {
                out.append(ch)
                if escaped { escaped = false } else if ch == "\\" { escaped = true } else if ch == "\"" { inString = false }
                i += 1
                continue
            }
            if ch == "\"" {
                inString = true
                out.append(ch)
            } else if ch == "/" && next == "/" {
                lineComment = true
                i += 1
            } else if ch == "/" && next == "*" {
                blockComment = true
                i += 1
            } else if ch == "," {
                // A comma followed only by whitespace/comments and then } or ] is dropped.
                var j = i + 1
                scan: while j < c.count {
                    let cj = c[j]
                    if cj.properties.isWhitespace {
                        j += 1
                    } else if cj == "/" && j + 1 < c.count && c[j + 1] == "/" {
                        while j < c.count && c[j] != "\n" { j += 1 }
                    } else if cj == "/" && j + 1 < c.count && c[j + 1] == "*" {
                        var k = j + 2
                        while k + 1 < c.count && !(c[k] == "*" && c[k + 1] == "/") { k += 1 }
                        j = k + 1 < c.count ? k + 2 : c.count
                    } else {
                        break scan
                    }
                }
                if j < c.count && (c[j] == "}" || c[j] == "]") {
                    // dropped
                } else {
                    out.append(ch)
                }
            } else {
                out.append(ch)
            }
            i += 1
        }
        return String(out)
    }

    /// JavaScript truthiness for a JSON value.
    static func isTruthy(_ value: Any?) -> Bool {
        switch value {
        case nil, is NSNull: return false
        case let s as String: return !s.isEmpty
        case let n as NSNumber: return n.doubleValue != 0 && !n.doubleValue.isNaN
        default: return true
        }
    }

    /// A JSON number (not a boolean).
    static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
    }

    private static func string(_ value: Any?) -> String? { value as? String }

    private static func rect(_ value: Any?) -> Rect? {
        guard let d = value as? [String: Any] else { return nil }
        return Rect(x: number(d["x"]) ?? 0, y: number(d["y"]) ?? 0, width: number(d["width"]) ?? 0, height: number(d["height"]) ?? 0)
    }

    private static func edges(_ value: Any?) -> Edges? {
        guard let d = value as? [String: Any] else { return nil }
        return Edges(top: number(d["top"]), bottom: number(d["bottom"]), left: number(d["left"]), right: number(d["right"]))
    }

    private static func item(_ value: Any) -> Item {
        guard let d = value as? [String: Any] else {
            return Item(frame: nil, edges: Edges(), inputs: .none, thumbstick: nil)
        }
        let inputs: Inputs
        if let list = d["inputs"] as? [Any] {
            inputs = .list(list.map { ($0 as? String) ?? "\($0)" })
        } else if let dict = d["inputs"] as? [String: Any] {
            var out: [String: String] = [:]
            for (key, raw) in dict where !(raw is NSNull) { out[key] = (raw as? String) ?? "\(raw)" }
            inputs = .directions(out)
        } else {
            inputs = .none
        }
        var thumb: Thumbstick?
        if let t = d["thumbstick"] as? [String: Any] {
            thumb = Thumbstick(name: string(t["name"]), width: number(t["width"]), height: number(t["height"]))
        }
        return Item(frame: rect(d["frame"]), edges: edges(d["extendedEdges"]) ?? Edges(), inputs: inputs, thumbstick: thumb)
    }

    /// Every (device, displayType, orientation) with artwork in a representations tree.
    ///
    /// JSON object order is not kept by `JSONSerialization`, so devices come out iphone, ipad, tv, then the rest by
    /// name; the converter only depends on that order when a skin lacks the requested device.
    private static func listLayouts(_ tree: Any?) -> [Layout] {
        guard let devices = tree as? [String: Any] else { return [] }
        let rank = ["iphone": 0, "ipad": 1, "tv": 2]
        var out: [Layout] = []
        for device in devices.keys.sorted(by: { (rank[$0] ?? 3, $0) < (rank[$1] ?? 3, $1) }) {
            guard let displayTypes = devices[device] as? [String: Any] else { continue }
            for displayType in displayTypes.keys.sorted() {
                guard let orientations = displayTypes[displayType] as? [String: Any] else { continue }
                for orientation in orientations.keys.sorted() {
                    guard let rep = orientations[orientation] as? [String: Any],
                          let assets = rep["assets"] as? [String: Any],
                          let mapping = rep["mappingSize"] as? [String: Any],
                          let width = number(mapping["width"]), let height = number(mapping["height"]),
                          width > 0, height > 0 else { continue }
                    var frames: [Rect] = []
                    for case let screen as [String: Any] in (rep["screens"] as? [Any]) ?? [] {
                        if let frame = rect(screen["outputFrame"]) { frames.append(frame) }
                    }
                    if frames.isEmpty, let frame = rect(rep["gameScreenFrame"]) { frames.append(frame) }
                    out.append(Layout(
                        device: device, displayType: displayType, orientation: orientation,
                        assets: Assets(resizable: string(assets["resizable"]), large: string(assets["large"]),
                                       medium: string(assets["medium"]), small: string(assets["small"])),
                        mappingWidth: width, mappingHeight: height,
                        edges: edges(rep["extendedEdges"]),
                        translucent: (rep["translucent"] as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue } ?? false,
                        items: ((rep["items"] as? [Any]) ?? []).map(item),
                        screenFrames: frames))
                }
            }
        }
        return out
    }
}
