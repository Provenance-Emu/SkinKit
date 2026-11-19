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
    /// Called on the main actor when the artwork is on screen, or could not be read.
    var onLoad: ((Bool) -> Void)?

    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?

    public init(bezel: TVBezel, onLoad: ((Bool) -> Void)? = nil) {
        self.bezel = bezel
        self.onLoad = onLoad
    }

    public var body: some View {
        GeometryReader { geometry in
            let maxPixel = (max(geometry.size.width, geometry.size.height) * displayScale).rounded()
            let key = "\(bezel.id)|\(Int(maxPixel))"
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
                let loaded = await Task.detached(priority: .userInitiated) {
                    TVBezelPlainArtwork.image(for: bezel, maxPixel: maxPixel)
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
    let picture: (CGRect?) -> Picture

    /// - Parameters:
    ///   - pictureAspect: the game picture's shape (only the ratio matters).
    ///   - picture: the game picture, sized by the caller to the frame it is given. The stage
    ///     positions it; with `nil` it is centred in the whole space.
    public init(bezel: TVBezel?, pictureAspect: CGSize, @ViewBuilder picture: @escaping (CGRect?) -> Picture) {
        self.bezel = bezel
        self.pictureAspect = pictureAspect
        self.picture = picture
    }

    public var body: some View {
        GeometryReader { geometry in
            let layout = bezel.flatMap { TVBezelLayout(bezel: $0, container: geometry.size, pictureAspect: pictureAspect) }
            ZStack {
                Color.black
                if let bezel, let layout {
                    if layout.placement == .behindPicture { TVBezelArtworkView(bezel: bezel) }
                    picture(layout.pictureFrame)
                        .position(x: layout.pictureFrame.midX, y: layout.pictureFrame.midY)
                    if layout.placement == .abovePicture { TVBezelArtworkView(bezel: bezel) }
                } else {
                    picture(nil)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}
#endif
