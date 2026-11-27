//
//  TVBezelArtworkView.swift
//  SkinKitBezelsUI
//
//  A TV shown as a plain image around the game picture, with no shader.
//

#if os(iOS) || os(tvOS)
import SkinKitBezels
import SwiftUI

/// A TV's artwork fitted into the space it is given: a built-in TV's cabinet and room with a
/// black tube, or an image bezel. It draws nothing until the artwork has loaded, off the main
/// thread, and nothing for a shader-only TV.
///
/// Where it goes relative to the game picture is `TVBezelLayout.placement`: a built-in TV
/// behind the picture, an image bezel above it. `TVBezelStage` does both.
public struct TVBezelArtworkView: View {
    let bezel: TVBezel
    /// The canvas a built-in TV is laid out on (`TVBezelLayout.canvas`); `nil` is the fixed 16:9 one.
    var canvas: CGSize?
    /// The picture's shape a built-in TV is laid out for (`TVBezelLayout.shape`).
    var shape: TVBezelPictureShape
    /// What covers the top of a portrait canvas (`TVBezelLayout.canvasTopInset`).
    var topInset: CGFloat
    /// Called on the main actor when the artwork is on screen, or could not be read.
    var onLoad: (@MainActor (Bool) -> Void)?

    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?

    public init(bezel: TVBezel, canvas: CGSize? = nil, shape: TVBezelPictureShape = .standard,
                topInset: CGFloat = 0, onLoad: (@MainActor (Bool) -> Void)? = nil) {
        self.bezel = bezel
        self.canvas = canvas
        self.shape = shape
        self.topInset = topInset
        self.onLoad = onLoad
    }

    public var body: some View {
        GeometryReader { geometry in
            let maxPixel = (max(geometry.size.width, geometry.size.height) * displayScale).rounded()
            let canvas = canvas ?? TVBezelArtwork.canvas
            let key = "\(bezel.id)|\(Int(maxPixel))|\(canvas.width)x\(canvas.height)|\(shape.rawValue)|\(topInset)"
            ZStack {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .task(id: key) {
                guard maxPixel >= 1 else { return }
                let bezel = bezel
                let shape = shape
                let topInset = topInset
                let loaded = await Task.detached(priority: .userInitiated) {
                    TVBezelPlainArtwork.image(for: bezel, maxPixel: maxPixel, canvas: canvas, shape: shape, topInset: topInset)
                }.value
                guard !Task.isCancelled else { return }
                image = loaded
                onLoad?(loaded != nil)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The game picture inside a TV, drawn without a shader: the artwork fills the space and the
/// picture is handed the frame of the TV's screen.
///
/// With no TV, or one that cannot be laid out, `picture` gets `nil` and the app lays the
/// picture out as it always does.
///
///     TVBezelStage(bezel: bezel, pictureAspect: CGSize(width: 4, height: 3)) { frame in
///         GameSurface().frame(width: frame?.width, height: frame?.height)
///     }
public struct TVBezelStage<Picture: View>: View {
    let bezel: TVBezel?
    let pictureAspect: CGSize
    let seat: TVBezelSeat?
    let safeAreaTop: CGFloat
    let picture: (CGRect?) -> Picture

    /// - Parameters:
    ///   - pictureAspect: the game picture's shape (only the ratio matters).
    ///   - seat: where the player sits; with one, a built-in TV's room is drawn for this
    ///     space's shape and fills it (see `TVBezelLayout`).
    ///   - safeAreaTop: how much of the top of this space is covered (a notch, a Dynamic
    ///     Island) when the stage ignores the safe area; see `TVBezelLayout`.
    ///   - picture: the game picture, sized by the caller to the frame it is given. The stage
    ///     positions it; with `nil` it is centred in the whole space.
    public init(bezel: TVBezel?, pictureAspect: CGSize, seat: TVBezelSeat? = nil, safeAreaTop: CGFloat = 0,
                @ViewBuilder picture: @escaping (CGRect?) -> Picture) {
        self.bezel = bezel
        self.pictureAspect = pictureAspect
        self.seat = seat
        self.safeAreaTop = safeAreaTop
        self.picture = picture
    }

    public var body: some View {
        GeometryReader { geometry in
            let layout = bezel.flatMap { TVBezelLayout(bezel: $0, container: geometry.size, pictureAspect: pictureAspect, seat: seat,
                                                         safeAreaTop: safeAreaTop) }
            ZStack {
                Color.black
                if let bezel, let layout {
                    // The artwork goes where the layout put it: in a portrait space that is
                    // near the top, not the centre an aspect-fit of the whole space gives.
                    if layout.placement == .behindPicture { artwork(bezel, layout: layout) }
                    picture(layout.pictureFrame)
                        .position(x: layout.pictureFrame.midX, y: layout.pictureFrame.midY)
                    if layout.placement == .abovePicture { artwork(bezel, layout: layout) }
                } else {
                    picture(nil)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func artwork(_ bezel: TVBezel, layout: TVBezelLayout) -> some View {
        TVBezelArtworkView(bezel: bezel, canvas: layout.canvas, shape: layout.shape, topInset: layout.canvasTopInset)
            .frame(width: layout.artworkFrame.width, height: layout.artworkFrame.height)
            .position(x: layout.artworkFrame.midX, y: layout.artworkFrame.midY)
    }
}
#endif
