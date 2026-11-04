import Foundation
import SkinKitCore

/// What `RetroArchConverter.convert` made from a skin: the preset, and the report around it.
public struct RetroArchConversion {

    /// A picture the exporter must produce for the preset: an overlay background or a thumbstick cap.
    public struct ImagePlan: Equatable, Sendable {
        public enum Kind: String, Equatable, Sendable {
            case overlay
            case thumbstick
        }

        /// File name inside the preset's folder, e.g. `My_Skin-landscape.png`.
        public var file: String
        public var kind: Kind
        /// The skin's artwork file the picture is drawn from, as `info.json` names it.
        public var asset: String?
        public var orientation: String
        public var overlayName: String
        /// Size in the layout's mapping points (an overlay: the `mappingSize`; a thumbstick: its hitbox).
        public var width: Double
        public var height: Double
        /// Thumbstick only: the cap's own size in mapping points, centered in `width` x `height`.
        public var innerWidth: Double?
        public var innerHeight: Double?
        /// Areas, in mapping points, that must be transparent: the game screens, unless the layout is translucent.
        public var clearRects: [RetroArchSkinInfo.Rect]

        /// Pixel size to render at: `scale` times the mapping size, shrunk so the long side stays within `maxLongSide`.
        public func pixelSize(scale: Double = 2, maxLongSide: Double = 2048) -> (width: Int, height: Int) {
            let factor = pixelsPerPoint(scale: scale, maxLongSide: maxLongSide)
            return (max(1, Int((width * factor).rounded())), max(1, Int((height * factor).rounded())))
        }

        /// The point-to-pixel factor `pixelSize` uses.
        public func pixelsPerPoint(scale: Double = 2, maxLongSide: Double = 2048) -> Double {
            let longSide = max(width, height)
            guard longSide > 0 else { return scale }
            return min(scale, maxLongSide / longSide)
        }
    }

    /// A skin control the converter turned into one or more descriptors.
    public struct DescSummary: Equatable, Sendable {
        public enum Kind: String, Equatable, Sendable {
            case button, toggle, analog, dpad
        }

        public var overlayName: String
        public var kind: Kind
        /// RetroArch inputs: the joined bind for a button, the directions for a pad.
        public var bind: String
    }

    /// An input that did not convert, and why.
    public struct Unconvertible: Equatable, Sendable {
        public var location: String
        public var input: String
        public var reason: String
    }

    /// A layout left out because its artwork is not in the skin archive.
    public struct SkippedLayout: Equatable, Sendable {
        public var overlayName: String
        public var displayType: String
        public var asset: String
        public var reason: String
    }

    /// One emitted overlay, for reports and tests.
    public struct LayoutSummary: Equatable, Sendable {
        public var orientation: String
        public var overlayName: String
        /// `"base"` or `"alt"`.
        public var set: String
        public var displayType: String
        public var mappingWidth: Double
        public var mappingHeight: Double
        public var asset: String?
        public var rect: RetroArchOverlayPreset.Rect?
        public var translucent: Bool
        public var screens: Int
        public var items: Int
        public var descs: Int
    }

    public var preset: RetroArchOverlayPreset
    public var readme: String
    public var images: [ImagePlan]
    public var descs: [DescSummary]
    public var unconvertible: [Unconvertible]
    public var skipped: [SkippedLayout]
    public var notes: [String]
    /// Folder and file base name (`<name>/<name>.cfg`).
    public var name: String
    /// Input-map system key, e.g. `"gba"`.
    public var system: String
    /// The device the layouts came from, nil when the skin had none with artwork.
    public var device: String?
    public var layouts: [LayoutSummary]

    /// The `.cfg` text. Empty when nothing converted.
    public var cfg: String { preset.cfg }
}

/// Converts a Delta/Manic skin's `info.json` into a RetroArch overlay preset.
///
/// Port of the website's converter (skins `docs/js/skin/retroarch-convert.js`); the two are tested against the same
/// fixtures and write the same `.cfg`. Pure logic: it plans the preset and the pictures it needs, and renders
/// nothing. `RetroArchOverlayExporter` writes the folder.
public struct RetroArchConverter {

    public struct Options {
        /// Device whose layouts to convert. If the skin has none, the first device it has is used and a note says so.
        public var device: DeltaSkinDevice = .iphone
        /// Preferred display type; missing orientations fall back through the others, with a note.
        public var displayType: DeltaSkinDisplayType = .edgeToEdge
        /// Portrait width/height of the screen the layouts are for. Default: from device and display type.
        public var screenAspect: Double?
        /// Folder and file base name. Default: the skin's name, slugified.
        public var name: String?
        /// File names in the skin archive. A layout whose artwork is not among them is skipped and reported
        /// instead of emitted. nil: nothing is checked.
        public var entries: [String]?
        /// Who is named as the converter in the cfg header and README.
        public var credit: String = RetroArchConverter.defaultCredit

        public init(device: DeltaSkinDevice = .iphone, displayType: DeltaSkinDisplayType = .edgeToEdge,
                    screenAspect: Double? = nil, name: String? = nil, entries: [String]? = nil,
                    credit: String = RetroArchConverter.defaultCredit) {
            self.device = device
            self.displayType = displayType
            self.screenAspect = screenAspect
            self.name = name
            self.entries = entries
            self.credit = credit
        }
    }

    /// The credit the website writes; the default so the two converters' text matches.
    public static let defaultCredit = "EmuSkins (https://emuskins.com/retroarch.html)"

    public let inputMap: RetroArchInputMap

    public init(inputMap: RetroArchInputMap) {
        self.inputMap = inputMap
    }

    /// A converter over the bundled `retroarch-input-map.json`.
    public static func bundled() throws -> RetroArchConverter {
        RetroArchConverter(inputMap: try RetroArchInputMap.bundled())
    }

    public func convert(skin: some DeltaSkinProtocol, options: Options = Options()) -> RetroArchConversion {
        convert(RetroArchSkinInfo(skin: skin), options: options)
    }

    public func convert(infoJSON: Data, options: Options = Options()) throws -> RetroArchConversion {
        convert(try RetroArchSkinInfo(infoJSON: infoJSON), options: options)
    }

    // MARK: Names

    /// Folder-safe name: NFKD, anything outside ASCII `[A-Za-z0-9_.-]` becomes `_` (runs collapse), trimmed of
    /// `_`, at most 60 characters; `"skin"` for nothing.
    public static func slugify(_ text: String?) -> String {
        let source = (text?.isEmpty == false ? text : nil) ?? "skin"
        var out = String.UnicodeScalarView()
        var inRun = false
        for scalar in source.decomposedStringWithCompatibilityMapping.unicodeScalars {
            let word = (scalar.value < 128) && (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) || scalar == "_" || scalar == "." || scalar == "-")
            if word {
                out.append(scalar)
                inRun = false
            } else if !inRun {
                out.append("_")
                inRun = true
            }
        }
        let trimmed = String(out).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let sliced = String(trimmed.prefix(60))
        return sliced.isEmpty ? "skin" : sliced
    }

    /// Find artwork in a list of archive paths the way the apps do: exact path, then the same file name anywhere
    /// ignoring case, then the same stem as `.pdf`, `.png` or `.svg`.
    public static func resolveAsset(_ entries: [String], _ name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        if entries.contains(name) { return name }
        func last(_ path: String) -> String { path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? "" }
        let base = last(name).lowercased()
        var stem = base
        if let dot = base.lastIndex(of: "."), base.index(after: dot) != base.endIndex { stem = String(base[..<dot]) }
        if let hit = entries.first(where: { last($0).lowercased() == base }) { return hit }
        for ext in [".pdf", ".png", ".svg"] {
            if let hit = entries.first(where: { last($0).lowercased() == stem + ext }) { return hit }
        }
        return nil
    }

    /// Screen ratios (width/height in portrait) the layouts are drawn for.
    public static func screenAspect(device: String, displayType: String) -> Double {
        if device == "ipad" { return 3.0 / 4.0 }
        if device == "tv" || device == "appletv" { return 9.0 / 16.0 }
        return displayType == "standard" ? 9.0 / 16.0 : 9.0 / 19.5
    }

    // MARK: Layout choice

    private typealias Layout = RetroArchSkinInfo.Layout

    private struct Picked {
        var device: String?
        var landscape: Layout?
        var portrait: Layout?
        var notes: [String] = []
    }

    private static let displayPreference = ["edgeToEdge", "standard", "splitView", "stageManager", "externalDisplay"]

    /// The landscape and portrait layouts to convert for a device and display type, each falling back through the
    /// device's other display types. `isBase` is false for the alternate tree, which is picked quietly.
    private func pick(from all: [Layout], device requested: String, displayType: String, isBase: Bool) -> Picked {
        var notes: [String] = []
        var device = requested
        if !all.contains(where: { $0.device == device }) {
            guard let other = all.first?.device else { return Picked(device: nil, landscape: nil, portrait: nil, notes: notes) }
            if isBase { notes.append("No \(device) layouts; using \(other).") }
            device = other
        }
        var order: [String] = []
        for candidate in [displayType] + Self.displayPreference where !candidate.isEmpty && !order.contains(candidate) {
            order.append(candidate)
        }
        func pick(_ orientation: String) -> Layout? {
            for dt in order {
                if let hit = all.first(where: { $0.device == device && $0.displayType == dt && $0.orientation == orientation }) {
                    if dt != displayType && isBase { notes.append("\(orientation): no \(displayType) layout, using \(dt).") }
                    return hit
                }
            }
            return nil
        }
        let landscape = pick("landscape")
        let portrait = pick("portrait")
        return Picked(device: device, landscape: landscape, portrait: portrait, notes: notes)
    }

    // MARK: Geometry

    private func hitbox(_ layout: Layout, _ item: RetroArchSkinInfo.Item, frame f: RetroArchSkinInfo.Rect) -> RetroArchSkinInfo.Rect {
        // The layout's extendedEdges are the default for every item; an item's own edges override per side.
        func pick(_ own: Double?, _ base: Double?) -> Double { own ?? base ?? 0 }
        let top = pick(item.edges.top, layout.edges?.top)
        let bottom = pick(item.edges.bottom, layout.edges?.bottom)
        let left = pick(item.edges.left, layout.edges?.left)
        let right = pick(item.edges.right, layout.edges?.right)
        return .init(x: f.x - left, y: f.y - top,
                     width: max(0, f.width + left + right), height: max(0, f.height + top + bottom))
    }

    /// Center and half extents of a rect in mapping points, as fractions of the mapping.
    private func geometry(_ rect: RetroArchSkinInfo.Rect, mappingWidth: Double, mappingHeight: Double)
        -> (x: Double, y: Double, rx: Double, ry: Double) {
        ((rect.x + rect.width / 2) / mappingWidth,
         (rect.y + rect.height / 2) / mappingHeight,
         rect.width / 2 / mappingWidth,
         rect.height / 2 / mappingHeight)
    }

    private static let leftAnalog = ["up": "l_y_minus", "down": "l_y_plus", "left": "l_x_minus", "right": "l_x_plus"]
    private static let rightAnalog = ["up": "r_y_minus", "down": "r_y_plus", "left": "r_x_minus", "right": "r_x_plus"]

    // MARK: Conversion

    private struct PlanEntry {
        var orientation: String
        var chosen: Layout
        var set: String
        var overlayName: String
    }

    public func convert(_ info: RetroArchSkinInfo, options opts: Options = Options()) -> RetroArchConversion {
        typealias Result = RetroArchConversion
        let system = inputMap.system(forGameTypeIdentifier: info.gameTypeIdentifier)
        var name = Self.slugify(opts.name.flatMap { $0.isEmpty ? nil : $0 } ?? info.name.flatMap { $0.isEmpty ? nil : $0 } ?? info.identifier)

        let base = pick(from: info.layouts, device: opts.device.rawValue, displayType: opts.displayType.rawValue, isBase: true)
        var notes = base.notes
        let device = base.device
        if device == "ipad" && !name.lowercased().hasSuffix("ipad") { name += "-ipad" } // one preset per device class
        if (device == "tv" || device == "appletv") && !name.lowercased().hasSuffix("tv") { name += "-tv" }

        var unconvertible: [Result.Unconvertible] = []
        var skipped: [Result.SkippedLayout] = []
        var descs: [Result.DescSummary] = []
        var images: [Result.ImagePlan] = []
        var layouts: [Result.LayoutSummary] = []
        func empty() -> Result {
            Result(preset: RetroArchOverlayPreset(), readme: "", images: images, descs: descs, unconvertible: unconvertible,
                   skipped: skipped, notes: notes, name: name, system: system, device: device, layouts: layouts)
        }
        guard let device else {
            notes.append("The skin has no layouts with artwork.")
            return empty()
        }
        if device == "tv" || device == "appletv" {
            notes.append("TV layouts are artwork only: RetroArch on Apple TV takes input from a controller, so the buttons in this overlay are decoration.")
        }
        let entries = opts.entries
        func inArchive(_ asset: String?) -> Bool {
            guard let entries else { return true }
            return Self.resolveAsset(entries, asset) != nil
        }

        let alt = pick(from: info.altLayouts, device: device, displayType: opts.displayType.rawValue, isBase: false)
        let hasAlt = alt.landscape != nil || alt.portrait != nil
        if info.hasGameOverrides { notes.append("Per-game overrides (gameOverrides) are not converted; the base layout is used.") }

        // Overlay plan: landscape then portrait, then the alternate pair.
        var plan: [PlanEntry] = []
        for (set, picked) in [("", base), ("-alt", alt)] {
            for orientation in ["landscape", "portrait"] {
                guard let chosen = orientation == "landscape" ? picked.landscape : picked.portrait else { continue }
                let art = chosen.assets.preferred
                if !inArchive(art) {
                    skipped.append(.init(overlayName: orientation + set, displayType: chosen.displayType, asset: art ?? "null",
                                         reason: "The archive has no \"\(art ?? "null")\", so this layout cannot be drawn."))
                    continue
                }
                plan.append(PlanEntry(orientation: orientation, chosen: chosen, set: set, overlayName: orientation + set))
            }
        }
        guard !plan.isEmpty else {
            notes.append("No landscape or portrait layout with artwork for this device.")
            return empty()
        }
        func named(_ n: String) -> PlanEntry? { plan.first { $0.overlayName == n } }
        func rotateTarget(_ p: PlanEntry) -> String? {
            let other = p.orientation == "landscape" ? "portrait" : "landscape"
            return (named(other + p.set) ?? named(other))?.overlayName
        }
        func altTarget(_ p: PlanEntry) -> String? { named(p.orientation + (p.set.isEmpty ? "-alt" : ""))?.overlayName }

        let sysAssumes = inputMap.assumes(system: system)
        let displayName = info.name.flatMap { $0.isEmpty ? nil : $0 } ?? name
        let manic = (info.identifier ?? "undefined").lowercased().contains("manic")
        var header: [String] = []
        header.append("\(displayName) — RetroArch overlay")
        header.append("Converted from a \(manic ? ".manicskin" : ".deltaskin") by \(opts.credit).")
        if let id = info.identifier, !id.isEmpty { header.append("Skin identifier: \(id)") }
        header.append("System: \(system)\(sysAssumes.map { " — buttons follow \($0)" } ?? "").")
        header.append("Layouts: \(device), \(plan.map { "\($0.overlayName) (\($0.chosen.displayType))" }.joined(separator: ", ")).")
        header.append("Auto-Rotate Overlay (on by default on iOS) switches landscape/portrait with the device.")

        var overlays: [RetroArchOverlayPreset.Overlay] = []

        for p in plan {
            let rep = p.chosen
            let orientation = p.orientation
            let overlayName = p.overlayName
            let mw = rep.mappingWidth, mh = rep.mappingHeight
            let screenAspect = opts.screenAspect.flatMap { $0 != 0 ? $0 : nil }
                ?? Self.screenAspect(device: device, displayType: p.chosen.displayType)
            // Delta scales the image to the screen width and keeps its aspect, so a portrait layout shorter than
            // the screen (a 320x240 controller strip) sits at the bottom with the game above it.
            let skinAspect = mw / mh
            let screenRatio = orientation == "portrait" ? screenAspect : 1 / screenAspect
            var rect: RetroArchOverlayPreset.Rect?
            if orientation == "portrait" && skinAspect > screenRatio * 1.02 {
                let h = screenRatio / skinAspect
                rect = .init(x: 0, y: 1 - h, width: 1, height: h)
            }

            let imageFile = "\(name)-\(overlayName).png"
            let asset = rep.assets.preferred
            let translucent = rep.translucent
            images.append(.init(file: imageFile, kind: .overlay, asset: asset, orientation: orientation, overlayName: overlayName,
                                width: mw, height: mh, innerWidth: nil, innerHeight: nil,
                                // The apps draw the game over the skin unless it is translucent; the RetroArch
                                // overlay sits on top of the video, so that area must be clear.
                                clearRects: translucent ? [] : rep.screenFrames))

            var out: [RetroArchOverlayPreset.Desc] = []
            let location: (Int) -> String = { "\(overlayName) item \($0 + 1)" }

            for (idx, item) in rep.items.enumerated() {
                guard let frame = item.frame else { continue }
                let box = hitbox(rep, item, frame: frame)

                switch item.inputs {
                case .list(let tokens):
                    var ok: [String] = []
                    var bad: [String] = []
                    for token in tokens {
                        let bind = inputMap.lookup(token, system: system).bindID
                        if bind == "overlay_next" {
                            // toggleAltRepresentations: jump to this layout's alternate (or back).
                            if altTarget(p) != nil { ok.append("overlay_next") } else { bad.append(token) }
                            continue
                        }
                        if let bind { ok.append(bind) } else { bad.append(token) }
                    }
                    for token in bad {
                        unconvertible.append(.init(location: location(idx), input: token,
                                                   reason: inputMap.reason(forUnconvertible: token, system: system)))
                    }
                    if ok.isEmpty { continue }
                    var unique: [String] = []
                    for bind in ok where !unique.contains(bind) { unique.append(bind) }
                    let bind = unique.joined(separator: "|")
                    let shape: RetroArchOverlayPreset.Shape = (bind == "analog_left" || bind == "analog_right") ? .radial : .rect
                    let g = geometry(box, mappingWidth: mw, mappingHeight: mh)
                    var desc = RetroArchOverlayPreset.Desc(inputs: unique, x: g.x, y: g.y, shape: shape, rangeX: g.rx, rangeY: g.ry)
                    if bind == "overlay_next" { desc.nextTarget = altTarget(p) }
                    out.append(desc)
                    descs.append(.init(overlayName: overlayName, kind: bind == "overlay_next" ? .toggle : .button, bind: bind))

                case .directions(let inputs):
                    var dirs: [String: String] = [:]
                    var bad: [String] = []
                    for dir in ["up", "down", "left", "right"] {
                        guard let token = inputs[dir] else { continue }
                        if let bind = inputMap.lookup(token, system: system).bindID { dirs[dir] = bind } else { bad.append(token) }
                    }
                    for token in bad {
                        unconvertible.append(.init(location: location(idx), input: token,
                                                   reason: inputMap.reason(forUnconvertible: token, system: system)))
                    }
                    if dirs.isEmpty { continue }

                    // A stick is an item with a thumbstick image or stick-named tokens. Four C buttons resolve to
                    // right-stick binds too, but they are buttons: each gets a cell with full deflection, not a
                    // radial stick.
                    let tokens = Array(inputs.values)
                    let thumb = item.thumbstick
                    let stickish = thumb != nil || tokens.contains { token in
                        let t = token.lowercased()
                        return t.contains("analog") || t.contains("thumb") || t.contains("stick")
                    }
                    if stickish {
                        let isRight = ["up", "down", "left", "right"].allSatisfy { dirs[$0] == Self.rightAnalog[$0] }
                            || tokens.contains { $0.lowercased().hasPrefix("right") }
                        let bind = isRight ? "analog_right" : "analog_left"
                        let g = geometry(box, mappingWidth: mw, mappingHeight: mh)
                        var desc = RetroArchOverlayPreset.Desc(inputs: [bind], x: g.x, y: g.y, shape: .radial, rangeX: g.rx, rangeY: g.ry)
                        if let thumb, let thumbName = thumb.name, !thumbName.isEmpty {
                            if !inArchive(thumbName) {
                                notes.append("Thumbstick image \"\(thumbName)\" is not in the archive; the stick has no cap image.")
                            } else {
                                let thumbFile = "\(name)-\(overlayName)-thumb\(out.count).png"
                                desc.image = thumbFile
                                desc.movable = true
                                images.append(.init(
                                    file: thumbFile, kind: .thumbstick, asset: thumbName, orientation: orientation, overlayName: overlayName,
                                    width: box.width, height: box.height,
                                    innerWidth: (thumb.width.flatMap { $0 != 0 ? $0 : nil }) ?? box.width,
                                    innerHeight: (thumb.height.flatMap { $0 != 0 ? $0 : nil }) ?? box.height,
                                    clearRects: []))
                            }
                        }
                        out.append(desc)
                        descs.append(.init(overlayName: overlayName, kind: .analog, bind: bind))
                        continue
                    }

                    // A four-way pad: nine rects on a 3x3 grid of the hitbox, the way Delta reads it and the stock
                    // RetroArch overlays draw it. Corners press two directions; the centre is empty.
                    let cw = box.width / 3, ch = box.height / 3
                    let cells: [(Int, Int, [String])] = [
                        (0, 0, ["up", "left"]), (1, 0, ["up"]), (2, 0, ["up", "right"]),
                        (0, 1, ["left"]), (2, 1, ["right"]),
                        (0, 2, ["down", "left"]), (1, 2, ["down"]), (2, 2, ["down", "right"]),
                    ]
                    for (cx, cy, ds) in cells {
                        let binds = ds.compactMap { dirs[$0] }
                        if binds.count != ds.count { continue } // a missing direction drops its cells
                        let cell = RetroArchSkinInfo.Rect(x: box.x + Double(cx) * cw, y: box.y + Double(cy) * ch, width: cw, height: ch)
                        let g = geometry(cell, mappingWidth: mw, mappingHeight: mh)
                        out.append(.init(inputs: binds, x: g.x, y: g.y, shape: .rect, rangeX: g.rx, rangeY: g.ry))
                    }
                    descs.append(.init(overlayName: overlayName, kind: .dpad,
                                       bind: ["up", "down", "left", "right"].compactMap { dirs[$0] }.joined(separator: "/")))

                case .none:
                    unconvertible.append(.init(location: location(idx), input: "(no inputs)", reason: "Item has no inputs."))
                }
            }

            // A hidden overlay_next tells auto-rotate where the other orientation lives. reach 0 removes its
            // hitbox so it can't be tapped.
            if let rotate = rotateTarget(p) {
                out.append(.init(inputs: ["overlay_next"], x: 0.5, y: 0, shape: .rect, rangeX: 0.001, rangeY: 0.001,
                                 nextTarget: rotate, reachX: 0, reachY: 0))
            }

            overlays.append(.init(name: overlayName, image: imageFile, aspectRatio: screenRatio, rect: rect, descs: out))
            layouts.append(.init(orientation: orientation, overlayName: overlayName, set: p.set.isEmpty ? "base" : "alt",
                                 displayType: rep.displayType, mappingWidth: mw, mappingHeight: mh, asset: asset,
                                 rect: rect, translucent: translucent, screens: rep.screenFrames.count,
                                 items: rep.items.count, descs: out.count))
        }

        if hasAlt { notes.append("The alternate layouts (altRepresentations) are extra overlays; the skin's toggle button switches to them.") }
        var result = Result(preset: RetroArchOverlayPreset(headerComments: header, overlays: overlays), readme: "",
                            images: images, descs: descs, unconvertible: unconvertible, skipped: skipped, notes: notes,
                            name: name, system: system, device: device, layouts: layouts)
        result.readme = readmeText(result, info: info, credit: opts.credit)
        return result
    }

    // MARK: README

    /// `README.txt` for the overlay folder: the menu taps and what did not convert.
    func readmeText(_ result: RetroArchConversion, info: RetroArchSkinInfo, credit: String) -> String {
        var lines: [String] = []
        let title = info.name.flatMap { $0.isEmpty ? nil : $0 } ?? result.name
        lines.append("\(title) — RetroArch overlay")
        lines.append("Converted by \(credit).")
        lines.append("")
        lines.append("Install on iOS")
        lines.append("  1. Move this whole folder (\(result.name)) to Files > On My iPhone > RetroArch > RetroArch > overlays.")
        lines.append("  2. In RetroArch: Settings > On-Screen Display > On-Screen Overlay > Overlay Preset > \(result.name)/\(result.name).cfg.")
        lines.append("  3. Auto-Rotate Overlay (on by default) switches landscape and portrait with the device.")
        lines.append("     Set Overlay Opacity to 1.0 if the artwork looks faded.")
        lines.append("")
        lines.append("Other platforms: put the folder in RetroArch's overlays directory (Settings > Directory > Overlays).")
        lines.append("")
        if let assumes = inputMap.assumes(system: result.system) {
            lines.append("Buttons follow \(assumes). On another core, remap in Quick Menu > Controls.")
            lines.append("")
        }
        if !result.skipped.isEmpty {
            lines.append("Layouts left out:")
            for s in result.skipped { lines.append("  - \(s.overlayName) (\(s.displayType)): \(s.reason)") }
            lines.append("")
        }
        if !result.unconvertible.isEmpty {
            lines.append("Not converted (RetroArch has nothing to bind these to):")
            var seen = Set<String>()
            for u in result.unconvertible {
                guard seen.insert("\(u.input)|\(u.reason)").inserted else { continue }
                lines.append("  - \(u.input): \(u.reason)")
            }
            lines.append("")
        }
        for note in result.notes { lines.append("Note: \(note)") }
        return lines.joined(separator: "\n") + "\n"
    }
}
