//
//  TVBezelArtwork.swift
//  SkinKitBezels
//
//  A TV's cabinet and room, drawn from its format 2 skin document.
//

import CoreGraphics
import Foundation
import ImageIO
import SkinKit2Core
import SkinKit2Render
import UniformTypeIdentifiers

/// A TV's skin document resolved on a canvas (`TVBezelCanvas.size(display:seat:)`, or the
/// default 16:9 one).
///
/// The document's one screen node is the tube: its frame is the only statement of where the
/// picture goes and what shape it has. Everything else in the document is artwork.
public struct TVBezelArtwork {

    @frozen public enum ArtworkError: Error, Equatable {
        /// The document must have exactly one screen node (it has this many).
        case screenCount(Int)
        case emptyTube
    }

    /// The default canvas, in points: the format's `tv` layout, and what a 16:9 display gets
    /// from the back seat.
    public static let canvas = CGSize(width: 1920, height: 1080)

    /// The canvas this artwork was resolved on, in points.
    public let canvasSize: CGSize
    /// The tube in `canvasSize` points.
    public let tubeRect: CGRect
    private let resolution: Skin2Resolution

    /// The tube's width over its height.
    public var tubeAspect: CGFloat { tubeRect.width / tubeRect.height }
    /// The tube's height as a fraction of the canvas's.
    public var tubeHeightFraction: CGFloat { tubeRect.height / canvasSize.height }
    /// The tube's height as a fraction of the canvas's width: what the bezel presets size
    /// the tube by (`TVBezelShader.geometryValues(tubeAspect:tubeHeightOverSceneWidth:)`).
    public var tubeHeightOverCanvasWidth: CGFloat { tubeRect.height / canvasSize.width }

    /// - Parameters:
    ///   - data: the skin document (`skin.json` contents).
    ///   - canvas: the canvas to lay the document out on, in points.
    public init(data: Data, canvas: CGSize = TVBezelArtwork.canvas) throws {
        let document = try Skin2Document.load(data: data)
        let environment = Skin2Environment(size: .init(width: canvas.width, height: canvas.height),
                                           orientation: .landscape, device: .tv, displayType: .standard)
        let resolution = Skin2Resolver.resolve(document, in: environment)
        let screens = resolution.screens
        guard screens.count == 1, let frame = screens.first?.frame else {
            throw ArtworkError.screenCount(screens.count)
        }
        guard frame.width > 0, frame.height > 0 else { throw ArtworkError.emptyTube }
        self.resolution = resolution
        canvasSize = canvas
        tubeRect = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
    }

    /// Where the visible node `id` sits on the canvas; `nil` when the document has none or it
    /// is hidden on this canvas.
    func frame(ofNode id: String) -> CGRect? {
        guard let frame = resolution.node(id: id)?.frame else { return nil }
        return CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
    }

    /// The bundled artwork of `bezel`, laid out on `canvas`.
    public init(bezel: TVBezel, canvas: CGSize = TVBezelArtwork.canvas) throws {
        guard let url = TVBezelCatalog.folderURL?.appendingPathComponent(bezel.artwork) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try self.init(data: Data(contentsOf: url), canvas: canvas)
    }

    /// The cabinet and room as an image `pixelWidth` pixels wide (the canvas scaled uniformly).
    public func image(pixelWidth: CGFloat) -> CGImage? {
        guard pixelWidth > 0 else { return nil }
        return Skin2Renderer.image(resolution, scale: pixelWidth / canvasSize.width)
    }

    /// The same as PNG data, the form a preset's texture is loaded from.
    public func pngData(pixelWidth: CGFloat) -> Data? {
        guard let image = image(pixelWidth: pixelWidth) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
