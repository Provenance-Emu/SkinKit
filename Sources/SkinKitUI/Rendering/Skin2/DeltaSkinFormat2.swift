#if canImport(UIKit)
import SkinKit2Core
import SkinKit2Render
import SkinKitCore
import SwiftUI

/// The format 2.0 switch for `DeltaSkinView` (section 1): a bundle whose `info.json` has a `format2` entry whose
/// `requires` this build draws renders its `skin.json`; every other skin, and any 2.0 skin that fails to load,
/// renders the baked classic part.
enum DeltaSkinFormat2 {
    private final class Box {
        let document: Skin2Document?
        init(_ document: Skin2Document?) { self.document = document }
    }

    private static let cache: NSCache<NSString, Box> = {
        let c = NSCache<NSString, Box>()
        c.countLimit = 32
        return c
    }()

    /// The skin's 2.0 document, or nil to draw it as a classic skin. Cached per bundle file, modification date and theme.
    static func document(for skin: any DeltaSkinProtocol) -> Skin2Document? {
        let modified = (try? skin.fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let key = "\(skin.fileURL.path)|\(modified?.timeIntervalSinceReferenceDate ?? 0)|\(skin.selectedThemeId ?? "")" as NSString
        if let hit = cache.object(forKey: key) { return hit.document }
        let document = load(skin)
        cache.setObject(Box(document), forKey: key)
        return document
    }

    private static func load(_ skin: any DeltaSkinProtocol) -> Skin2Document? {
        guard let info = Skin2SourceInfo(infoJSON: skin.jsonRepresentation), info.isRenderable,
              let data = try? skin.loadAssetData(info.source) else { return nil }
        // Decoding only checks shape. Duplicate control ids, overlapping hit frames or content beyond `requires`
        // make a 2.0 source unsafe to drive input from, and the baked classic part is still a working skin.
        let report = Skin2Validator.validate(data: data)
        guard report.isValid else {
            WLOG("DeltaSkinFormat2: \(skin.identifier) skin.json has \(report.errors.count) validation error(s); drawing the classic skin. First: \(report.errors.first.map { "\($0.pointer) \($0.message)" } ?? "")")
            return nil
        }
        // A classic theme id the 2.0 source doesn't define is not an error; draw the default.
        let loaded = (skin.selectedThemeId.flatMap { try? Skin2Document.load(data: data, theme: $0) })
            ?? (try? Skin2Document.load(data: data))
        guard let document = loaded, Skin2SourceInfo.accepts(formatVersion: document.formatVersion),
              SkinKit2Render.supports(document.requires) else { return nil }
        return document
    }

    static func device(_ d: DeltaSkinDevice) -> Skin2Device {
        switch d {
        case .iphone: return .iphone
        case .ipad: return .ipad
        case .tv: return .tv
        }
    }

    static func displayType(_ d: DeltaSkinDisplayType) -> Skin2DisplayType {
        switch d {
        case .edgeToEdge: return .edgeToEdge
        case .splitView: return .splitView
        case .standard, .stageManager, .externalDisplay: return .standard
        }
    }

    /// App flags for a trait set: `altToggled` while the skin shows its alternate layout.
    static func flags(_ traits: DeltaSkinTraits) -> Set<String> {
        traits.usesAltRepresentations ? ["altToggled"] : []
    }

    /// The main screen's frame: the first `role: main` screen, else the first screen.
    static func viewportFrame(in resolution: Skin2Resolution) -> CGRect? {
        let screens = resolution.screens
        guard let s = screens.first(where: { $0.node.screenRole == .main }) ?? screens.first else { return nil }
        return CGRect(x: s.frame.x, y: s.frame.y, width: s.frame.width, height: s.frame.height)
    }
}

/// Sends a 2.0 skin's control events to the app's input handler.
final class DeltaSkinFormat2Sink: Skin2InputSink {
    private let handler: any DeltaSkinInputHandling
    init(_ handler: any DeltaSkinInputHandling) { self.handler = handler }

    func press(_ input: String) { handler.buttonPressed(input) }
    func release(_ input: String) { handler.buttonReleased(input) }

    /// The handler's sticks are y-up; the skin's are y-down.
    func stick(_ input: String, x: Double, y: Double) {
        handler.analogStickMoved(input, x: Float(x), y: Float(-y))
    }

    func surface(_ input: String, point: Skin2SurfacePoint?) {
        // TODO: `pointer`, `lightGun` and `trackpad` have no DeltaSkinInputHandling call yet.
        guard input == "touchScreen" else { return }
        if let point { handler.ndsBottomScreenTouched(at: CGPoint(x: point.x, y: point.y)) } else { handler.ndsBottomScreenTouchReleased() }
    }

    func action(_ name: String) {
        if name == DeltaSkinAltRepresentationsToggle.input {
            handler.toggleAltRepresentations()
        } else {
            handler.buttonPressed(name)
            handler.buttonReleased(name)
        }
    }
}

/// `DeltaSkinView`'s 2.0 path: `Skin2SkinView` with the handler as its sink and the main screen's frame as the viewport.
struct DeltaSkinFormat2View: View {
    let skin: any DeltaSkinRenderable
    let document: Skin2Document
    let traits: DeltaSkinTraits
    let isInEmulator: Bool
    let inputHandler: any DeltaSkinInputHandling
    let onViewportFrameChange: ((CGRect) -> Void)?

    @State private var bridge = Skin2InputBridge()
    @State private var lastViewport: CGRect?

    var body: some View {
        let sink = DeltaSkinFormat2Sink(inputHandler)
        Skin2SkinView(
            document: document,
            device: DeltaSkinFormat2.device(traits.device),
            displayType: DeltaSkinFormat2.displayType(traits.displayType),
            flags: DeltaSkinFormat2.flags(traits),
            screenPlaceholders: !isInEmulator,
            asset: assetLoader,
            onInput: { bridge.handle($0, sink: sink) },
            onLayout: { resolution in
                guard isInEmulator, let frame = DeltaSkinFormat2.viewportFrame(in: resolution), frame != lastViewport else { return }
                lastViewport = frame
                onViewportFrameChange?(frame)
            },
            onReleaseAll: { bridge.releaseAll(sink: sink) }
        )
        .onDisappear { bridge.releaseAll(sink: sink) }
    }

    private var assetLoader: @Sendable (String) -> Data? {
        let skin = self.skin
        return { path in try? skin.loadAssetData("assets/" + path) }
    }
}
#endif
