// SkinKit2Spike: THROWAWAY code for the format 2.0 spike (SkinKit#24). Not shipped.
// SwiftUI `Canvas` host: the same Core Graphics renderer through `GraphicsContext.withCGContext`.

#if canImport(SwiftUI)
import SwiftUI

public struct Skin2CanvasView: View {
    public let document: Skin2Document
    public var safeArea: Skin2Insets
    public var flags: Set<String>
    public var showHitFrames: Bool

    public init(document: Skin2Document, safeArea: Skin2Insets = .init(), flags: Set<String> = [], showHitFrames: Bool = false) {
        self.document = document
        self.safeArea = safeArea
        self.flags = flags
        self.showHitFrames = showHitFrames
    }

    public var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let canvas = Skin2Canvas(size: size, safeArea: safeArea, flags: flags)
            let tree = Skin2Layouter.resolve(document, canvas: canvas)
            var options = Skin2RenderOptions()
            options.showHitFrames = showHitFrames
            context.withCGContext { cg in Skin2Renderer.draw(tree, in: cg, options: options) }
        }
        .background(Color(red: 0.16, green: 0.14, blue: 0.22))
    }
}

#if DEBUG
private let previewSkin = try? Skin2Document.loadBundledGameCube()

#Preview("iPhone portrait") {
    if let previewSkin {
        Skin2CanvasView(document: previewSkin, safeArea: Skin2Insets(top: 59, bottom: 34), showHitFrames: true)
            .frame(width: 393, height: 852)
    }
}

#Preview("iPhone landscape") {
    if let previewSkin {
        Skin2CanvasView(document: previewSkin, safeArea: Skin2Insets(left: 59, bottom: 21, right: 59), showHitFrames: true)
            .frame(width: 852, height: 393)
    }
}
#endif
#endif
