//
//  TVBezelShader.swift
//  SkinKitBezels
//
//  The library presets that draw a TV around the picture, and the parameter values that
//  place a tube inside them.
//

import CoreGraphics
import Foundation

/// The `bezel/uborder` presets as a TV: a scene the size of the display, with the picture
/// inside a tube whose frame reflects it.
///
/// The presets take the whole scene as their output and are told where the tube is through
/// parameters, so the picture handed to them is already the tube's shape.
///
/// A preset is named by an id of the form `slang:<path in the libretro slang library, without
/// extension>`. That is also the id a shader-only TV is stored under, so it never changes.
public enum TVBezelShader {
    /// What every preset id starts with.
    public static let slangPrefix = "slang:"

    /// The id of the library preset at `path`.
    public static func presetID(libraryPath path: String) -> String { slangPrefix + path }

    /// The library path an id names, or `nil` when it is not a slang preset's id.
    public static func libraryPath(ofPresetID id: String) -> String? {
        id.hasPrefix(slangPrefix) ? String(id.dropFirst(slangPrefix.count)) : nil
    }

    /// Frame, glass and reflections in one pass, with no tube look of its own.
    public static let bezelOnlyID = presetID(libraryPath: "bezel/uborder/preset_tools/append-uborder-bezel-reflections")
    /// The same, plus passes that spill the picture's light onto the room. Its last pass has
    /// the crt-nobody tube look built in, which `neutralTubeValues` turns down.
    public static let ambientID = presetID(libraryPath: "bezel/uborder/uborder-koko-ambi")
    /// The preset texture that holds the room and the cabinet.
    public static let borderTextureName = "BORDER"
    /// The default scene's proportions, and a standalone preset's.
    public static let sceneAspect = CGSize(width: 16, height: 9)

    public static func presetID(lightsRoom: Bool) -> String {
        lightsRoom ? ambientID : bezelOnlyID
    }

    /// The denominator the tube's aspect is expressed over (`fr_aspect_x / fr_aspect_y`).
    static let aspectDenominator: Float = 8

    /// Parameters that centre a tube of `tubeAspect` (width over height) taking
    /// `tubeHeightFraction` of the scene's height.
    ///
    /// The presets size the tube by `fr_zoom`: its height as a percentage of the scene's
    /// width (measured: 40.5 gives a 774 px tube on a 1920 px wide scene).
    public static func geometryValues(tubeAspect: CGFloat, tubeHeightFraction: CGFloat) -> [String: Float] {
        geometryValues(tubeAspect: tubeAspect,
                       tubeHeightOverSceneWidth: tubeHeightFraction * sceneAspect.height / sceneAspect.width)
    }

    /// Parameters that centre a tube of `tubeAspect` (width over height) whose height is
    /// `tubeHeightOverSceneWidth` of the scene's width, on a scene of any shape.
    ///
    /// `fr_zoom` is that fraction as a percentage whatever the output's proportions
    /// (measured at 16:9, 4:3, 2.37:1 and 1:1).
    public static func geometryValues(tubeAspect: CGFloat, tubeHeightOverSceneWidth: CGFloat) -> [String: Float] {
        [
            "fr_aspect_x": aspectDenominator * Float(tubeAspect),
            "fr_aspect_y": aspectDenominator,
            "fr_zoom": Float(tubeHeightOverSceneWidth * 100),
            "fr_center_x": 0,
            "fr_center_y": 0,
            "bz_center_x": 0,
            "bz_center_y": 0
        ]
    }

    /// Turns `ambientID`'s built-in tube look down to a plain copy, so the screen filter that
    /// ran before it is the only look inside the glass.
    public static let neutralTubeValues: [String: Float] = [
        "CN_InputGamma": 2.2,
        "CN_OutputGamma": 2.2,
        "CN_VIG_TOGGLE": 0,
        "CN_BEAM_MIN_WIDTH": 1,
        "CN_BEAM_MAX_WIDTH": 1,
        "CN_SCAN_SIZE": 1,
        "CN_MASK_STRENGTH": 0,
        "CN_PHOSPHOR_LAYOUT": 0
    ]

    /// Every value a TV's preset runs with.
    ///
    /// - Parameter frame: the TV's own look for the frame and glass (colour, widths, curvature).
    ///   Geometry wins over it: a TV cannot move or resize its tube through these.
    public static func values(frame: [String: Float],
                              tubeAspect: CGFloat,
                              tubeHeightFraction: CGFloat,
                              lightsRoom: Bool) -> [String: Float] {
        values(frame: frame, tubeAspect: tubeAspect,
               tubeHeightOverSceneWidth: tubeHeightFraction * sceneAspect.height / sceneAspect.width, lightsRoom: lightsRoom)
    }

    /// The same for a scene of any shape (see `geometryValues(tubeAspect:tubeHeightOverSceneWidth:)`).
    public static func values(frame: [String: Float],
                              tubeAspect: CGFloat,
                              tubeHeightOverSceneWidth: CGFloat,
                              lightsRoom: Bool) -> [String: Float] {
        var values = lightsRoom ? neutralTubeValues : [:]
        values.merge(frame) { _, tv in tv }
        values.merge(geometryValues(tubeAspect: tubeAspect, tubeHeightOverSceneWidth: tubeHeightOverSceneWidth)) { _, geometry in geometry }
        return values
    }

    /// The parameter that switches the glass's own curvature.
    public static let glassCurvatureName = "h_curvature"
}
