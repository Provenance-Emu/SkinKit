//
//  TVBezelLayout.swift
//  SkinKitBezels
//
//  Where a TV's artwork and the game picture go when the TV is shown as a plain image.
//

import CoreGraphics
import Foundation

/// A TV laid out in a container without a shader: the artwork as one image and the game
/// picture in its screen. All rects are in the container's coordinates, in its unit.
///
/// This is how an app with no slang runtime shows a TV, and how any app shows an image bezel.
/// A built-in TV's artwork goes behind the picture (its tube is painted black); an image
/// bezel goes above it (its screen is see-through).
public struct TVBezelLayout: Equatable, Sendable {

    @frozen public enum Placement: Equatable, Sendable {
        case behindPicture
        case abovePicture
    }

    /// The whole artwork, fitted into the container.
    public let artworkFrame: CGRect
    /// The TV's screen: a built-in TV's tube, or an image bezel's see-through area.
    public let screenFrame: CGRect
    /// The game picture inside the screen.
    public let pictureFrame: CGRect
    public let placement: Placement
    /// The canvas a built-in TV's artwork is drawn on for this layout: pass it to
    /// `TVBezelPlainArtwork.image(for:maxPixel:canvas:)` or `TVBezelArtworkView`. `nil` for an
    /// image bezel, which is its own picture.
    public let canvas: CGSize?

    /// The picture's shape the artwork was laid out for: pass it to
    /// `TVBezelPlainArtwork.image(for:maxPixel:canvas:shape:)` or `TVBezelArtworkView` with
    /// `canvas`. `standard` for an image bezel.
    public let shape: TVBezelPictureShape

    /// What covers the top of a portrait canvas (a notch, a Dynamic Island), in `canvas`
    /// points: pass it to `TVBezelPlainArtwork.image(for:maxPixel:canvas:shape:topInset:)` or
    /// `TVBezelArtworkView` with `canvas`. The artwork still covers the whole container; the
    /// set is drawn below the inset. Zero in landscape and for an image bezel.
    public let canvasTopInset: CGFloat

    /// Where a small second screen the app owns (a Dreamcast VMU) goes: the screen of the
    /// TV's shelf, in the container's coordinates. `nil` unless the layout was made with
    /// `shelf: true` and the TV has a shelf here (a built-in TV's portrait room). When it is
    /// set the artwork must be drawn with its shelf (`TVBezelArtworkView(bezel:layout:)`).
    public let shelfFrame: CGRect?

    /// How far down a portrait container the top of a TV that has no portrait form goes, as
    /// a fraction of the container's height: under the status bar, clear of the controls.
    static let portraitTopFraction: CGFloat = 0.08

    /// The gap kept under the top safe-area inset by artwork that is placed near the top of
    /// a portrait container, in the container's unit.
    static let portraitSafeAreaGap: CGFloat = 4

    /// `nil` for a TV with no artwork of its own (a shader-only preset), an empty container
    /// or artwork that cannot be read.
    ///
    /// - Parameters:
    ///   - pictureAspect: the picture's shape (only the ratio matters). A built-in TV with a
    ///     widescreen form is drawn with a wide tube for a wide picture.
    ///   - seat: where the player sits. With a seat, a built-in TV's room is drawn for the
    ///     container's shape (`TVBezelCanvas`), so the artwork is the whole container on
    ///     anything from 4:3 to 2.4:1, and on a portrait container for a TV with a portrait
    ///     form. Without one the room is the fixed 16:9 scene, fitted inside the container.
    ///     An image bezel ignores it.
    ///   - safeAreaTop: how much of the container's top is covered (a notch, a Dynamic
    ///     Island, the status bar), in the container's unit. In a portrait container the TV
    ///     and its picture are placed below it. Pass the window's inset: a view that ignores
    ///     the safe area reports zero for its own.
    ///   - shelf: the app has a small second screen to show. Where the TV has a shelf for it,
    ///     `shelfFrame` says where it goes; elsewhere the app places it as it always did.
    public init?(bezel: TVBezel, container: CGSize, pictureAspect: CGSize, seat: TVBezelSeat? = nil,
                 safeAreaTop: CGFloat = 0, shelf: Bool = false) {
        guard container.width > 0, container.height > 0 else { return nil }
        let bounds = CGRect(origin: .zero, size: container)
        if let art = bezel.image {
            guard art.size.width > 0, art.size.height > 0 else { return nil }
            let frame = Self.placed(aspect: art.size, in: bounds, safeAreaTop: safeAreaTop)
            let scale = frame.width / art.size.width
            canvasTopInset = 0
            shelfFrame = nil
            artworkFrame = frame
            screenFrame = CGRect(x: frame.minX + art.screen.minX * scale, y: frame.minY + art.screen.minY * scale,
                                 width: art.screen.width * scale, height: art.screen.height * scale)
            pictureFrame = BezelPictureFit.rect(aspect: pictureAspect, in: screenFrame)
            placement = .abovePicture
            canvas = nil
            shape = .standard
            return
        }
        let portraitCanvas = bezel.drawsPortrait ? seat.flatMap { TVBezelCanvas.portraitSize(display: container, seat: $0) } : nil
        let artworkCanvas = portraitCanvas ?? seat.map { TVBezelCanvas.size(display: container, seat: $0) } ?? TVBezelArtwork.canvas
        let pictureShape = TVBezelPictureShape(aspect: pictureAspect).fitting(bezel: bezel, canvas: artworkCanvas)
        // Only a portrait room moves its set for the inset: it is the one form that hangs
        // the TV from the top of the screen.
        let topInset = portraitCanvas.map { max(0, safeAreaTop) * $0.width / container.width } ?? 0
        guard bezel.presetID == nil,
              let tube = TVBezelPlainArtwork.tubeRect(of: bezel, canvas: artworkCanvas, shape: pictureShape,
                                                      topInset: topInset) else { return nil }
        // A canvas made for this container has its proportions, so the fit is the container.
        let fills = portraitCanvas != nil || (seat != nil && TVBezelCanvas.fitsDisplay(container))
        let frame = fills ? bounds : Self.placed(aspect: artworkCanvas, in: bounds, safeAreaTop: safeAreaTop)
        canvasTopInset = topInset
        let scale = frame.width / artworkCanvas.width
        canvas = artworkCanvas
        shape = pictureShape
        artworkFrame = frame
        screenFrame = CGRect(x: frame.minX + tube.minX * scale, y: frame.minY + tube.minY * scale,
                             width: tube.width * scale, height: tube.height * scale)
        pictureFrame = Self.aspectFit(aspect: pictureAspect, in: screenFrame)
        placement = .behindPicture
        let shelfRect = shelf ? TVBezelPlainArtwork.shelfRect(of: bezel, canvas: artworkCanvas, shape: pictureShape,
                                                              topInset: topInset) : nil
        shelfFrame = shelfRect.map {
            CGRect(x: frame.minX + $0.minX * scale, y: frame.minY + $0.minY * scale,
                   width: $0.width * scale, height: $0.height * scale)
        }
    }

    /// `aspectFit`, except in a portrait container, where artwork that leaves room above and
    /// below goes near the top: the lower part of a portrait screen belongs to the controls.
    /// It never goes under `safeAreaTop`, unless centring it puts it lower still.
    static func placed(aspect: CGSize, in bounds: CGRect, safeAreaTop: CGFloat = 0) -> CGRect {
        let fitted = aspectFit(aspect: aspect, in: bounds)
        guard bounds.height > bounds.width else { return fitted }
        let clear = safeAreaTop > 0 ? safeAreaTop + portraitSafeAreaGap : 0
        let top = min(fitted.minY, bounds.minY + max(bounds.height * portraitTopFraction, clear))
        return CGRect(x: fitted.minX, y: top, width: fitted.width, height: fitted.height)
    }

    /// Largest rect with `aspect`'s proportions that fits in `bounds`, centred.
    static func aspectFit(aspect: CGSize, in bounds: CGRect) -> CGRect {
        guard aspect.width > 0, aspect.height > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
        let scale = min(bounds.width / aspect.width, bounds.height / aspect.height)
        let size = CGSize(width: aspect.width * scale, height: aspect.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }
}

extension TVBezelPictureShape {

    /// How much of the canvas, in points, must stay on each side of a wide tube: the edge of
    /// its frame.
    static let wideTubeMargin: CGFloat = 8

    /// The shape `bezel` is drawn for on `canvas` when the picture has this shape. `wide` only
    /// when the TV has a widescreen form and its wide tube is whole on the canvas: a closer
    /// seat on a 4:3 display draws a canvas narrower than the wide tube, and there the TV
    /// keeps its 4:3 tube with the picture fitted inside it, as before the forms existed.
    public func fitting(bezel: TVBezel, canvas: CGSize) -> TVBezelPictureShape {
        guard self == .wide, let tube = TVBezelPlainArtwork.tubeRect(of: bezel, canvas: canvas, shape: .wide) else {
            return .standard
        }
        let isWideTube = TVBezelPictureShape(aspect: tube.size) == .wide
        let fits = tube.minX >= Self.wideTubeMargin && tube.maxX <= canvas.width - Self.wideTubeMargin
            && tube.minY >= 0 && tube.maxY <= canvas.height
        return isWideTube && fits ? .wide : .standard
    }
}

/// A TV as one plain image, for apps that draw it without a shader.
@frozen public enum TVBezelPlainArtwork {

    /// The tube's corner radius as a fraction of its width, when drawn plainly.
    static let tubeCornerFraction: CGFloat = 0.012

    private static let lock = NSLock()
    nonisolated(unsafe) private static var tubes: [String: CGRect] = [:]

    /// A built-in TV's tube in `canvas` points. Lays the TV's skin document out the first
    /// time for each canvas; `nil` for a TV without one.
    public static func tubeRect(of bezel: TVBezel, canvas: CGSize = TVBezelArtwork.canvas,
                                shape: TVBezelPictureShape = .standard, topInset: CGFloat = 0) -> CGRect? {
        guard bezel.image == nil, bezel.presetID == nil else { return nil }
        let key = "\(bezel.id)|\(canvas.width)x\(canvas.height)|\(shape.rawValue)|\(topInset)"
        if let known = lock.withLock({ tubes[key] }) { return known }
        guard let tube = try? TVBezelArtwork(bezel: bezel, canvas: canvas, shape: shape, topInset: topInset).tubeRect else {
            return nil
        }
        lock.withLock {
            // A window being resized asks for a new canvas every frame: do not keep them all.
            if tubes.count >= tubeCacheLimit { tubes.removeAll(keepingCapacity: true) }
            tubes[key] = tube
        }
        return tube
    }

    /// A built-in TV's shelf screen in `canvas` points (`TVBezelArtwork.shelfRect`); `nil` for
    /// a TV or canvas without one.
    public static func shelfRect(of bezel: TVBezel, canvas: CGSize, shape: TVBezelPictureShape = .standard,
                                 topInset: CGFloat = 0) -> CGRect? {
        guard bezel.image == nil, bezel.presetID == nil else { return nil }
        return try? TVBezelArtwork(bezel: bezel, canvas: canvas, shape: shape, topInset: topInset, shelf: true).shelfRect
    }

    /// How many laid-out tubes are remembered before the cache starts over.
    private static let tubeCacheLimit = 64

    /// The TV's artwork no larger than `maxPixel` on its longer side: an image bezel as it is,
    /// a built-in TV's cabinet and room with the tube painted black. Slow: call it off the
    /// main thread. `nil` for a shader-only TV or artwork that cannot be read.
    ///
    /// - Parameters:
    ///   - canvas: the canvas a built-in TV is laid out on (`TVBezelLayout.canvas`).
    ///   - shape: the picture's shape it is laid out for (`TVBezelLayout.shape`).
    ///   - topInset: what covers the top of the canvas (`TVBezelLayout.canvasTopInset`).
    ///   - shelf: draw the TV's shelf (`TVBezelLayout.shelfFrame != nil`).
    ///   - cutsOutTube: leave a built-in TV's tube see-through, for an app that lays the
    ///     artwork over its picture as it does an image bezel. Otherwise the tube is black
    ///     and the artwork goes behind the picture.
    public static func image(for bezel: TVBezel, maxPixel: CGFloat, canvas: CGSize = TVBezelArtwork.canvas,
                             shape: TVBezelPictureShape = .standard, topInset: CGFloat = 0, shelf: Bool = false,
                             cutsOutTube: Bool = false) -> CGImage? {
        guard maxPixel >= 1 else { return nil }
        if let art = bezel.image {
            return TVBezelImage.displayImage(art.fileURL, maxPixel: maxPixel)
        }
        // `maxPixel` is the longer side; the renderer wants the width.
        let pixelWidth = canvas.height > canvas.width ? maxPixel * canvas.width / canvas.height : maxPixel
        guard bezel.presetID == nil, let artwork = try? TVBezelArtwork(bezel: bezel, canvas: canvas, shape: shape, topInset: topInset, shelf: shelf),
              let cabinet = artwork.image(pixelWidth: pixelWidth) else { return nil }
        let (width, height) = (cabinet.width, cabinet.height)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return cabinet }
        context.draw(cabinet, in: CGRect(x: 0, y: 0, width: width, height: height))
        // The context's origin is at the bottom left; the canvas's is at the top left.
        let scale = CGFloat(width) / artwork.canvasSize.width
        let tube = artwork.tubeRect
        let rect = CGRect(x: tube.minX * scale, y: CGFloat(height) - tube.maxY * scale,
                          width: tube.width * scale, height: tube.height * scale)
        let radius = rect.width * tubeCornerFraction
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        if cutsOutTube { context.setBlendMode(.clear) }
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
        return context.makeImage() ?? cabinet
    }
}
