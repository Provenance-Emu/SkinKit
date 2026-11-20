//
//  TVBezelScene.swift
//  SkinKitBezels
//
//  A TV made ready to draw: its preset, the values it runs with and its artwork.
//

import CoreGraphics
import Foundation

/// Everything a slang filter chain needs to draw one TV on one display.
///
/// The scene is drawn in two stages. The game goes through the tube look into a texture the
/// size of the tube; then the preset named here runs over the whole 16:9 scene with that
/// texture as its picture, `values` as its parameters and `borderPNG` as its `BORDER` texture.
/// The package runs no shader: the app's own chain does.
public struct TVBezelScene: Sendable, Equatable {
    /// Identifies this TV at this size, room light and glass. A chain loaded for another key
    /// must reload: its `BORDER` texture differs.
    public let key: String
    /// The tube in the artwork's canvas points (`TVBezelArtwork.canvas`).
    public let tubeRect: CGRect
    /// The preset to run (`TVBezelShader.presetID(libraryPath:)`).
    public let presetID: String
    /// The preset's parameter values; a parameter not listed keeps its initial value.
    public let values: [String: Float]
    /// The cabinet and room as PNG data, for the preset's `TVBezelShader.borderTextureName`
    /// texture. `nil` for a standalone preset, which brings its own.
    public let borderPNG: Data?

    public init(key: String, tubeRect: CGRect, presetID: String, values: [String: Float], borderPNG: Data?) {
        self.key = key
        self.tubeRect = tubeRect
        self.presetID = presetID
        self.values = values
        self.borderPNG = borderPNG
    }

    /// The tube's width over its height: the shape the picture is fitted into.
    public var tubeAspect: CGSize { tubeRect.size }

    /// The key of `bezel` drawn `scenePixelWidth` pixels wide.
    public static func key(bezel: TVBezel, lightsRoom: Bool, flatGlass: Bool, scenePixelWidth: CGFloat) -> String {
        "\(bezel.id)|\(Int(scenePixelWidth))|\(lightsRoom)|\(flatGlass)"
    }

    /// Loads `bezel`'s artwork and draws it `scenePixelWidth` pixels wide. Slow: call it off
    /// the main thread. `nil` when the preset is not in the app's library or the artwork is bad.
    ///
    /// - Parameters:
    ///   - lightsRoom: use the preset that lights the room, falling back to the plain one
    ///     when the library does not have it.
    ///   - flatGlass: switch the glass's own curvature off.
    ///   - key: identifies this TV at this size (see `key(bezel:lightsRoom:flatGlass:scenePixelWidth:)`).
    ///   - hasPreset: whether the app's shader library has a preset id.
    public static func make(bezel: TVBezel, lightsRoom: Bool, flatGlass: Bool, scenePixelWidth: CGFloat, key: String,
                            hasPreset: (String) -> Bool = BezelEnvironment.current.hasShaderPreset) -> TVBezelScene? {
        if let presetID = bezel.presetID {
            guard hasPreset(presetID) else { return nil }
            // Both standalone presets place a centred 4:3 tube at 37.8% of the scene width.
            let canvas = TVBezelArtwork.canvas
            let height = canvas.width * 0.378
            let width = height * 4 / 3
            let tube = CGRect(x: (canvas.width - width) / 2, y: (canvas.height - height) / 2,
                              width: width, height: height)
            return TVBezelScene(key: key, tubeRect: tube, presetID: presetID, values: [:], borderPNG: nil)
        }
        let lit = lightsRoom && hasPreset(TVBezelShader.ambientID)
        let presetID = TVBezelShader.presetID(lightsRoom: lit)
        guard hasPreset(presetID) else {
            BezelLog.error("TV bezels: the shader library has no \(presetID)")
            return nil
        }
        let artwork: TVBezelArtwork
        do {
            artwork = try TVBezelArtwork(bezel: bezel)
        } catch {
            BezelLog.error("TV bezels: artwork of '\(bezel.id)' is unusable: \(error)")
            return nil
        }
        guard let png = artwork.pngData(pixelWidth: scenePixelWidth) else {
            BezelLog.error("TV bezels: artwork of '\(bezel.id)' did not render at \(Int(scenePixelWidth)) px")
            return nil
        }
        var values = TVBezelShader.values(frame: bezel.frame, tubeAspect: artwork.tubeAspect,
                                          tubeHeightFraction: artwork.tubeHeightFraction, lightsRoom: lit)
        if flatGlass {
            values[TVBezelShader.glassCurvatureName] = 0
        }
        return TVBezelScene(key: key, tubeRect: artwork.tubeRect, presetID: presetID, values: values, borderPNG: png)
    }
}
