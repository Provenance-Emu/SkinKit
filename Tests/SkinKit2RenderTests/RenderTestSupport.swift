import CoreGraphics
import Foundation
import ImageIO
import SkinKit2Core
@testable import SkinKit2Render
import UniformTypeIdentifiers

/// Paths into the source tree: the fixtures are shared with SkinKit2CoreTests and the TypeScript port, so they
/// are read through `#filePath`, not as resources.
enum RenderPaths {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let fixtures = repo.appendingPathComponent("Tests/Format2Fixtures", isDirectory: true)

    /// `SKIN2_RECORD=1` rewrites the reference images (and fails the run, so it can't pass in CI). The same
    /// switch rewrites the layout files in SkinKit2CoreTests.
    static var recording: Bool { ProcessInfo.processInfo.environment["SKIN2_RECORD"] == "1" }

    static let fixtureNames: [String] = {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: fixtures.path)) ?? []
        return names.filter { FileManager.default.fileExists(atPath: fixtures.appendingPathComponent("\($0)/skin.json").path) }.sorted()
    }()

    static func skinData(_ name: String) throws -> Data {
        try Data(contentsOf: fixtures.appendingPathComponent("\(name)/skin.json"))
    }

    static func expected(_ name: String) -> URL { fixtures.appendingPathComponent("\(name)/expected", isDirectory: true) }

    /// Where failing comparisons leave the actual and diff images (never the repo).
    static let failures = FileManager.default.temporaryDirectory.appendingPathComponent("skin2-render-failures", isDirectory: true)
}

/// One reference image: a fixture rendered on one trait set with one theme, variant or state set.
struct ReferenceImage {
    var file: String
    var trait: Skin2TraitSet
    var theme: String?
    var variant: String?
    var states: [String: Skin2ControlState] = [:]

    /// Reference images are rendered at 2× (section 9.2).
    static let scale: CGFloat = 2

    func render(_ fixture: String) throws -> CGImage {
        let doc = try Skin2Document.load(data: RenderPaths.skinData(fixture), theme: theme, variant: variant)
        let resolution = Skin2Resolver.resolve(doc, in: trait.environment)
        let assets = RenderPaths.fixtures.appendingPathComponent("\(fixture)/assets", isDirectory: true)
        let options = Skin2RenderOptions(states: states, screenPlaceholders: true) { path in
            try? Data(contentsOf: assets.appendingPathComponent(path))
        }
        guard let image = Skin2Renderer.image(resolution, scale: Self.scale, options: options) else {
            throw RenderTestError("could not render \(fixture)/\(file)")
        }
        return image
    }

    /// Every reference image of a fixture, named after its layout files (9.2):
    /// `<trait>@2x.png`, `<trait>.variant-<name>@2x.png`, `<trait>.theme-<name>@2x.png` for every theme (colour-only
    /// themes have no layout file but change pixels), and `<trait>.state-<name>@2x.png` for each state set in the
    /// fixture's `states.json`.
    static func all(_ fixture: String) throws -> [ReferenceImage] {
        let base = try Skin2Document.load(data: RenderPaths.skinData(fixture))
        let stateSets = try StateSets.load(fixture)
        var out: [ReferenceImage] = []
        for trait in Skin2TraitSet.sets(for: base) {
            out.append(ReferenceImage(file: "\(trait.name)@2x.png", trait: trait))
            for variant in base.variants.keys.sorted() {
                out.append(ReferenceImage(file: "\(trait.name).variant-\(variant)@2x.png", trait: trait, variant: variant))
            }
            for theme in base.themeNames {
                out.append(ReferenceImage(file: "\(trait.name).theme-\(theme)@2x.png", trait: trait, theme: theme))
            }
            for (name, states) in stateSets {
                out.append(ReferenceImage(file: "\(trait.name).state-\(name)@2x.png", trait: trait, states: states))
            }
        }
        return out
    }
}

/// `states.json` beside a fixture's `skin.json`: named sets of control states the references render with, so the
/// TypeScript port renders the same input.
///
/// ```json
/// { "pressed": { "a": { "pressed": true }, "dpad": { "directions": ["up", "right"] },
///                "stick": { "stick": [0.6, -0.3] }, "menu": { "selected": true } } }
/// ```
enum StateSets {
    static func load(_ fixture: String) throws -> [(String, [String: Skin2ControlState])] {
        let url = RenderPaths.fixtures.appendingPathComponent("\(fixture)/states.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: [String: [String: Any]]] else {
            throw RenderTestError("\(fixture)/states.json is {set: {controlId: state}}")
        }
        return try root.keys.sorted().map { set in
            var states: [String: Skin2ControlState] = [:]
            for (id, raw) in root[set]! {
                var s = Skin2ControlState()
                s.pressed = raw["pressed"] as? Bool ?? false
                s.selected = raw["selected"] as? Bool ?? false
                for d in raw["directions"] as? [String] ?? [] {
                    guard let dir = Skin2Direction(rawValue: d) else { throw RenderTestError("unknown direction \(d)") }
                    s.directions.insert(dir)
                }
                if let v = raw["stick"] as? [Double], v.count == 2 { s.stick = Skin2StickValue(x: v[0], y: v[1]) }
                states[id] = s
            }
            return (set, states)
        }
    }
}

struct RenderTestError: Error, CustomStringConvertible {
    var description: String
    init(_ d: String) { description = d }
}

/// RGBA8 pixels (premultiplied, sRGB) of an image, for comparing renders independent of how a PNG was encoded.
struct Pixels: Equatable {
    var width: Int
    var height: Int
    var bytes: [UInt8]

    init?(_ image: CGImage) {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let ok = data.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            ctx.setBlendMode(.copy)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        self.width = width; self.height = height
        bytes = data
    }

    subscript(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let i = (y * width + x) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
    }

    /// Section 9.3: a pixel differs when any channel differs by more than 10 % (26 of 255).
    static let channelThreshold = 26

    /// Byte-for-byte equality without a per-element loop (the usual case on one machine; fast in debug builds).
    func identical(_ other: Pixels) -> Bool {
        guard width == other.width, height == other.height else { return false }
        return bytes.withUnsafeBytes { a in other.bytes.withUnsafeBytes { b in memcmp(a.baseAddress!, b.baseAddress!, a.count) == 0 } }
    }

    /// The fraction of pixels that differ, and a diff image (red where they differ) for a failure report.
    func difference(_ other: Pixels) -> (fraction: Double, diff: CGImage?) {
        guard width == other.width, height == other.height else { return (1, nil) }
        if identical(other) { return (0, nil) }
        var count = 0
        var diff = [UInt8](repeating: 0, count: bytes.count)
        for p in 0..<(width * height) {
            let i = p * 4
            var differs = false
            for c in 0..<4 where abs(Int(bytes[i + c]) - Int(other.bytes[i + c])) > Self.channelThreshold { differs = true }
            if differs {
                count += 1
                diff[i] = 255; diff[i + 3] = 255
            } else {
                diff[i + 3] = bytes[i + 3] / 4
            }
        }
        return (Double(count) / Double(max(1, width * height)), Pixels.image(diff, width: width, height: height))
    }

    static func image(_ bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

enum PNG {
    static func data(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    static func read(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
