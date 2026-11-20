//
//  TVBezelShaderTests.swift
//  SkinKitBezels
//
//  The parameter values that place a tube inside the bezel presets.
//

import CoreGraphics
import Foundation
import Testing
@testable import SkinKitBezels

@Suite("TVBezelShader")
struct TVBezelShaderTests {

    @Test("A 4:3 tube 72 % of the scene's height")
    func geometry() throws {
        let values = TVBezelShader.geometryValues(tubeAspect: 4.0 / 3.0, tubeHeightFraction: 0.72)
        // Tube height as a percentage of the scene's width: 0.72 * 9 / 16.
        #expect(abs(try #require(values["fr_zoom"]) - 40.5) < 0.001)
        let aspect = try #require(values["fr_aspect_x"]) / (try #require(values["fr_aspect_y"]))
        #expect(abs(aspect - 4.0 / 3.0) < 0.0001)
        #expect(values["fr_center_x"] == 0)
        #expect(values["bz_center_y"] == 0)
    }

    @Test("The tube's aspect is the TV's, whatever was asked of the frame")
    func geometryWinsOverFrame() {
        let values = TVBezelShader.values(frame: ["fr_zoom": 99, "fr_aspect_x": 16, "bz_red": 40],
                                          tubeAspect: 4.0 / 3.0, tubeHeightFraction: 0.72, lightsRoom: false)
        #expect(abs((values["fr_zoom"] ?? 0) - 40.5) < 0.001)
        #expect(abs((values["fr_aspect_x"] ?? 0) - 8 * 4.0 / 3.0) < 0.0001)
        #expect(values["bz_red"] == 40)
    }

    @Test("Room light uses the ambient preset with its built-in tube look turned down")
    func roomLight() {
        let lit = TVBezelShader.values(frame: [:], tubeAspect: 4.0 / 3.0, tubeHeightFraction: 0.7, lightsRoom: true)
        #expect(lit["CN_MASK_STRENGTH"] == 0)
        #expect(lit["CN_InputGamma"] == lit["CN_OutputGamma"])
        #expect(TVBezelShader.presetID(lightsRoom: true) == TVBezelShader.ambientID)

        let unlit = TVBezelShader.values(frame: [:], tubeAspect: 4.0 / 3.0, tubeHeightFraction: 0.7, lightsRoom: false)
        #expect(unlit["CN_MASK_STRENGTH"] == nil)
        #expect(TVBezelShader.presetID(lightsRoom: false) == TVBezelShader.bezelOnlyID)
    }

    @Test("A TV may override the neutral tube values on purpose")
    func frameOverridesNeutral() {
        let values = TVBezelShader.values(frame: ["CN_VIG_TOGGLE": 1], tubeAspect: 1, tubeHeightFraction: 0.5, lightsRoom: true)
        #expect(values["CN_VIG_TOGGLE"] == 1)
    }

    @Test("A preset id is the library path behind a prefix")
    func presetIDs() {
        #expect(TVBezelShader.ambientID == "slang:bezel/uborder/uborder-koko-ambi")
        #expect(TVBezelShader.libraryPath(ofPresetID: TVBezelShader.bezelOnlyID) == "bezel/uborder/preset_tools/append-uborder-bezel-reflections")
        #expect(TVBezelShader.libraryPath(ofPresetID: "native:crt") == nil)
    }
}
