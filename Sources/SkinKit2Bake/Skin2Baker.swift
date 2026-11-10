import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import SkinKit2Core
import SkinKit2Render
import SkinKitCore
import UniformTypeIdentifiers

public enum Skin2BakeError: Error {
    case invalidSource([String])
    case unknownGameType(String)
    case artwork(String)
    case duplicateGameOverride(String)
}

public struct Skin2BakedBundle {
    public let files: [String: Data]
    public let variantLabel: String?
    public let warnings: [String]
}

/// Builds classic representations while preserving the original format 2 source.
public enum Skin2Baker {
    public static func bake(
        source: Data, assets: [String: Data] = [:]
    ) throws -> [Skin2BakedBundle] {
        let report = Skin2Validator.validate(data: source, assets: { assets["assets/" + $0] })
        guard report.isValid else { throw Skin2BakeError.invalidSource(report.errors.map(\.description)) }
        let document = try Skin2Document.load(data: source)
        let selectable = document.variants.keys.sorted().filter { document.variants[$0]?.isPlayerSelectable == true }
        let traits = Skin2TraitSet.sets(for: document)
        let splitThemes = try document.themeNames.sorted().filter { theme in
            for variant in [nil] + document.variants.keys.sorted().map(Optional.some) {
                let base = try Skin2Document.load(data: source, variant: variant)
                let themed = try Skin2Document.load(data: source, theme: theme, variant: variant)
                for trait in traits {
                    let original = Skin2Resolver.resolve(base, in: trait.environment)
                    let candidate = Skin2Resolver.resolve(themed, in: trait.environment)
                    if layoutSignature(original) != layoutSignature(candidate) { return true }
                }
            }
            return false
        }
        let inlineThemes = document.themeNames.sorted().filter { !splitThemes.contains($0) }
        return try document.gameTypes.enumerated().flatMap { index, gameType in
            try ([nil] + selectable.map(Optional.some)).flatMap { variant in
                try ([nil] + splitThemes.map(Optional.some)).map { theme in
                    var builder = Builder(source: source, assets: assets)
                    return try builder.build(document, gameType: gameType, gameIndex: index, variant: variant,
                                             theme: theme, inlineThemes: theme == nil ? inlineThemes : [])
                }
            }
        }
    }

    private struct LayoutNode: Equatable {
        let id: String?
        let frame: Skin2Rect
        let hitFrame: Skin2Rect?
        let placement: Skin2ScreenPlacement?
        let kind: Skin2ControlKind?
        let input: Skin2Input?
        let inputs: [String]
        let screenRole: Skin2ScreenRole?
        let filters: [Skin2ScreenFilter]
    }

    private static func layoutSignature(_ resolution: Skin2Resolution) -> [LayoutNode] {
        resolution.nodes.filter { $0.node.type == .control || $0.node.type == .screen || $0.node.role == .knob }
            .map { resolved in
                let node = resolved.node
                return LayoutNode(id: node.id, frame: resolved.frame, hitFrame: resolved.hitFrame,
                                  placement: node.placement, kind: node.kind, input: node.input, inputs: node.inputs ?? [],
                                  screenRole: node.screenRole, filters: node.filters)
            }
    }
}

private struct Builder {
    typealias JSON = [String: Any]
    typealias Representations = [String: [String: [String: JSON]]]

    let source: Data
    let assets: [String: Data]
    var files: [String: Data] = [:]
    var warnings: [String] = []

    mutating func build(_ base: Skin2Document, gameType: String, gameIndex: Int, variant: String?,
                        theme: String?, inlineThemes: [String]) throws -> Skin2BakedBundle {
        guard let game = DeltaSkinGameType.fromAnyString(gameType) else { throw Skin2BakeError.unknownGameType(gameType) }
        let native = DeltaSkinNativeResolution.size(for: game)
        let stacksScreens = game == .nds
        let labels = [variant.map { base.variants[$0]?.label ?? $0 }, theme].compactMap { $0 }
        let label = labels.isEmpty ? nil : labels.joined(separator: " — ")
        let traits = Skin2TraitSet.sets(for: base)
        let doc = try Skin2Document.load(data: source, theme: theme, variant: variant)
        let baseRepresentations = try representations(doc, traits: traits, native: native, stacksScreens: stacksScreens, prefix: "base")
        var identifier = base.identifier
        if gameIndex > 0 { identifier += ".game\(gameIndex)" }
        if let variant { identifier += ".\(variant)" }
        if let theme { identifier += ".theme.\(theme)" }
        let name = label.map { base.name + " — " + $0 } ?? base.name
        var format2: JSON = [
            "source": "skin.json",
            "formatVersion": base.formatVersion,
            "requires": base.requires,
        ]
        format2["variant"] = variant
        format2["theme"] = theme
        var info: JSON = [
            "name": name,
            "identifier": identifier,
            "gameTypeIdentifier": gameType,
            "debug": false,
            "representations": baseRepresentations,
            "format2": format2,
        ]
        if variant == nil {
            var overrides: [String: Representations] = [:]
            for (index, key) in base.variants.keys.sorted().enumerated() {
                guard let variant = base.variants[key], !variant.isPlayerSelectable else { continue }
                let doc = try Skin2Document.load(data: source, theme: theme, variant: key)
                let reps = try representations(doc, traits: traits, native: native, stacksScreens: stacksScreens, prefix: "variant-\(index)")
                if variant.toggle == true { info["altRepresentations"] = reps }
                if let match = variant.match {
                    for key in (match.md5 ?? []) + (match.crc ?? []) + (match.filename ?? []) + (match.title ?? []) {
                        guard overrides[key] == nil else { throw Skin2BakeError.duplicateGameOverride(key) }
                        overrides[key] = reps
                    }
                }
            }
            if !overrides.isEmpty { info["gameOverrides"] = overrides }
        }
        if !inlineThemes.isEmpty {
            info["themes"] = try inlineThemes.enumerated().map { index, name -> JSON in
                let themed = try Skin2Document.load(data: source, theme: name, variant: variant)
                let reps = try representations(themed, traits: traits, native: native, stacksScreens: stacksScreens, prefix: "theme-\(index)")
                let artwork = reps.mapValues { $0.mapValues { $0.mapValues { $0["assets"]! } } }
                return ["id": name, "name": name, "assets": artwork]
            }
        }
        files["info.json"] = Data(try canonicalJSON(info).utf8)
        files["skin.json"] = source
        for (name, data) in assets where name.hasPrefix("assets/") {
            let components = name.split(separator: "/", omittingEmptySubsequences: false)
            guard !name.contains("\\"), !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { continue }
            files[name] = data
        }
        if let preview = traits.first(where: { $0.name == "iphone-edgeToEdge-portrait" }) {
            let resolution = Skin2Resolver.resolve(doc, in: preview.environment)
            guard let image = Skin2Renderer.image(resolution, options: renderOptions(vector: false)) else { throw Skin2BakeError.artwork("preview.png") }
            let data = NSMutableData()
            guard let encoder = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
                throw Skin2BakeError.artwork("preview.png")
            }
            CGImageDestinationAddImage(encoder, image, nil)
            guard CGImageDestinationFinalize(encoder) else { throw Skin2BakeError.artwork("preview.png") }
            files["preview.png"] = data as Data
        }
        return Skin2BakedBundle(files: files, variantLabel: label, warnings: warnings)
    }

    func renderOptions(vector: Bool) -> Skin2RenderOptions {
        let assets = self.assets
        var options = Skin2RenderOptions(asset: { assets[$0] ?? assets["assets/" + $0] })
        if vector { options.effectScale = 3 }
        return options
    }

    mutating func representations(
        _ document: Skin2Document, traits: [Skin2TraitSet], native: CGSize?, stacksScreens: Bool, prefix: String
    ) throws -> Representations {
        var result: Representations = [:]
        for trait in traits {
            let resolution = Skin2Resolver.resolve(document, in: trait.environment)
            let path = "bake/\(prefix)-\(trait.name)"
            var background = resolution
            background.root = withoutKnobs(resolution.root)
            files[path + ".pdf"] = try pdf(background, frame: Skin2Rect(size: trait.size))
            var items: [JSON] = []
            var itemAssets: [String: JSON] = [:]
            for (index, control) in resolution.controls.enumerated() {
                var knobConfig: DeltaSkin.ThumbstickConfig?
                if control.node.kind == .thumbstick, let knob = control.preorder.first(where: { $0.node.role == .knob }),
                   knob.frame.width > 0, knob.frame.height > 0 {
                    let name = path + "-knob-\(index).pdf"
                    var knobResolution = resolution
                    knobResolution.root = knob
                    files[name] = try pdf(knobResolution, frame: knob.frame)
                    knobConfig = .init(name: name, width: knob.frame.width, height: knob.frame.height)
                    itemAssets[String(items.count)] = ["resizable": name]
                }
                if let item = ClassicItem(control, knob: knobConfig) {
                    let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item))
                    if let json = json as? JSON { items.append(json) }
                } else {
                    warnings.append("\(trait.name): skipped \(control.pointer)")
                }
            }
            var artwork: JSON = ["resizable": path + ".pdf"]
            if !itemAssets.isEmpty { artwork["items"] = itemAssets }
            let screens = resolution.screens.enumerated().sorted {
                (screenRank($0.element), $0.offset) < (screenRank($1.element), $1.offset)
            }.map { screen -> JSON in
                let node = screen.element
                var entry: JSON = [
                    "outputFrame": rect(node.frame),
                    "maintainAspectRatio": true,
                    "placement": node.node.placement?.rawValue ?? "app",
                ]
                if let native {
                    entry["inputFrame"] = [
                        "x": 0, "y": stacksScreens && screenRank(node) == 1 ? native.height : 0,
                        "width": native.width, "height": native.height,
                    ]
                }
                if !node.node.filters.isEmpty {
                    entry["filters"] = node.node.filters.map { filter -> JSON in
                        var result: JSON = ["name": filter.name]
                        if let params = filter.params, let data = try? Skin2JSON.object(params).data() {
                            result["parameters"] = try? JSONSerialization.jsonObject(with: data)
                        }
                        return result
                    }
                }
                return entry
            }
            result[trait.device.rawValue, default: [:]][trait.displayType.rawValue, default: [:]][trait.orientation.rawValue] = [
                "mappingSize": ["width": trait.size.width, "height": trait.size.height],
                "assets": artwork, "items": items, "screens": screens, "translucent": false,
                "extendedEdges": ["top": 0, "left": 0, "bottom": 0, "right": 0],
            ]
        }
        return result
    }

    func pdf(_ resolution: Skin2Resolution, frame: Skin2Rect) throws -> Data {
        let data = NSMutableData()
        var bounds = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else {
            throw Skin2BakeError.artwork("PDF context")
        }
        context.beginPDFPage(nil)
        context.translateBy(x: -frame.x, y: frame.height + frame.y)
        context.scaleBy(x: 1, y: -1)
        Skin2Renderer.draw(resolution, in: context, options: renderOptions(vector: true))
        context.endPDFPage()
        context.closePDF()
        return stablePDF(data as Data)
    }

    func withoutKnobs(_ node: Skin2ResolvedNode) -> Skin2ResolvedNode {
        var node = node
        node.children = node.children.filter { $0.node.role != .knob }.map(withoutKnobs)
        return node
    }

    func screenRank(_ node: Skin2ResolvedNode) -> Int {
        switch node.node.screenRole {
        case .bottom, .touch: return 1
        default: return 0
        }
    }

    func rect(_ frame: Skin2Rect) -> [String: Double] {
        ["x": frame.x, "y": frame.y, "width": frame.width, "height": frame.height]
    }
}

/// Match the TypeScript writer's UTF-16 key order, independent of locale.
private func canonicalJSON(_ value: Any) throws -> String {
    if let object = value as? [String: Any] {
        let keys = object.keys.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
        return "{" + (try keys.map { try canonicalJSON($0) + ":" + canonicalJSON(object[$0]!) }).joined(separator: ",") + "}"
    }
    if let array = value as? [Any] {
        return "[" + (try array.map(canonicalJSON)).joined(separator: ",") + "]"
    }
    let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])
    return String(decoding: data, as: UTF8.self)
}

/// Quartz inserts a timestamp and random trailer ID. Replacing equal-length fields preserves xref offsets.
private func stablePDF(_ input: Data) -> Data {
    var data = input
    for key in ["/CreationDate", "/ModDate"] {
        guard let field = data.range(of: Data(key.utf8), options: .backwards),
              let marker = data.range(of: Data("(D:".utf8), in: field.upperBound..<min(field.upperBound + 12, data.endIndex))
        else { continue }
        let end = marker.upperBound + 14
        guard end <= data.endIndex, data[marker.upperBound..<end].allSatisfy({ (48...57).contains($0) }) else { continue }
        data.replaceSubrange(marker.upperBound..<end, with: "20000101000000".utf8)
    }

    guard let trailer = data.range(of: Data("trailer".utf8), options: .backwards),
          let id = data.range(of: Data("/ID [".utf8), in: trailer.upperBound..<data.endIndex) else { return data }
    var cursor = id.upperBound
    var fields: [Range<Data.Index>] = []
    for _ in 0..<2 {
        guard let start = data[cursor...].firstIndex(of: 60),
              let end = data[(start + 1)...].firstIndex(of: 62), end - start == 33 else { return data }
        let range = (start + 1)..<end
        fields.append(range)
        data.replaceSubrange(range, with: repeatElement(UInt8(48), count: range.count))
        cursor = end + 1
    }
    let digest = SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined()
    for field in fields { data.replaceSubrange(field, with: digest.utf8) }
    return data
}
