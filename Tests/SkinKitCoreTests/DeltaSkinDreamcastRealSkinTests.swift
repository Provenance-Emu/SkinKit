//
//  DeltaSkinDreamcastRealSkinTests.swift
//  SkinKitCoreTests
//
//  Ported from Provenance's PVUIBaseTests. Items are trimmed from three real Dreamcast skins:
//  Dreamsicle (Manic id, l1/r1), BelmonT Taco DC Dark (Delta id `com.rileytestut.delta.game.dc`)
//  and GameCube Pocket (Manic id, l2/r2, an extra r1, two thumbsticks). Only the skin-side half
//  lives here: the skin loads as a Dreamcast skin and yields the tokens its items name. The
//  half that feeds those tokens to the input handler and touch classifier stays in Provenance.
//

import Foundation
import Testing
import CoreGraphics
@testable import SkinKitCore

@Suite("Real Dreamcast skins")
struct DeltaSkinDreamcastRealSkinTests {


    struct Fixture: CustomStringConvertible, Sendable {
        let name: String
        let gameTypeIdentifier: String
        let mappingSize: CGSize
        /// `items` array of the iPhone edge-to-edge portrait representation, as JSON.
        let itemsJSON: String
        /// The single-input tokens the items declare, in item order.
        let singleTokens: [String]
        var description: String { name }
    }


    static let fixtures: [Fixture] = [
        Fixture(
            name: "Dreamsicle (Manic)",
            gameTypeIdentifier: "public.aoshuang.game.dc",
            mappingSize: CGSize(width: 375, height: 812),
            itemsJSON: #"""
            [
              { "inputs": { "up": "leftThumbstickUp", "down": "leftThumbstickDown", "left": "leftThumbstickLeft", "right": "leftThumbstickRight" },
                "frame": { "x": 38, "y": 516, "width": 85, "height": 85 }, "thumbstick": { "name": "thumbstick.pdf", "width": 128, "height": 128 } },
              { "inputs": { "up": "up", "down": "down", "left": "left", "right": "right" }, "frame": { "x": 50, "y": 644, "width": 104, "height": 104 } },
              { "inputs": ["a"], "frame": { "x": 248, "y": 605, "width": 71, "height": 71 } },
              { "inputs": ["b"], "frame": { "x": 302, "y": 550, "width": 71, "height": 71 } },
              { "inputs": ["x"], "frame": { "x": 188, "y": 550, "width": 71, "height": 71 } },
              { "inputs": ["y"], "frame": { "x": 248, "y": 499, "width": 71, "height": 71 } },
              { "inputs": ["l1"], "frame": { "x": 6, "y": 441, "width": 115, "height": 53 } },
              { "inputs": ["r1"], "frame": { "x": 254, "y": 441, "width": 115, "height": 52 } },
              { "inputs": ["start"], "frame": { "x": 166, "y": 728, "width": 41, "height": 37 } },
              { "inputs": ["quickSave"], "frame": { "x": 52, "y": 382, "width": 60, "height": 30 } },
              { "inputs": ["quickLoad"], "frame": { "x": 260, "y": 382, "width": 60, "height": 30 } },
              { "inputs": ["menu"], "frame": { "x": 17, "y": 760, "width": 31, "height": 31 } }
            ]
            """#,
            singleTokens: ["a", "b", "x", "y", "l1", "r1", "start", "quickSave", "quickLoad", "menu"]
        ),
        Fixture(
            name: "BelmonT Taco DC Dark (Delta id)",
            gameTypeIdentifier: "com.rileytestut.delta.game.dc",
            mappingSize: CGSize(width: 430, height: 932),
            itemsJSON: #"""
            [
              { "inputs": { "up": "leftThumbstickUp", "down": "leftThumbstickDown", "left": "leftThumbstickLeft", "right": "leftThumbstickRight" },
                "frame": { "x": 51, "y": 659, "width": 92, "height": 92 }, "thumbstick": { "name": "stick.png", "width": 92, "height": 92 } },
              { "inputs": ["a"], "frame": { "x": 344, "y": 695, "width": 69, "height": 62 } },
              { "inputs": ["b"], "frame": { "x": 292, "y": 746, "width": 65, "height": 66 } },
              { "inputs": ["x"], "frame": { "x": 294, "y": 644, "width": 58, "height": 57 } },
              { "inputs": ["y"], "frame": { "x": 244, "y": 698, "width": 56, "height": 53 } },
              { "inputs": ["start"], "frame": { "x": 187, "y": 826, "width": 51, "height": 27 } },
              { "inputs": { "up": "up", "down": "down", "left": "left", "right": "right" }, "frame": { "x": 47, "y": 787, "width": 101, "height": 102 } },
              { "inputs": ["l1"], "frame": { "x": 0, "y": 586, "width": 96, "height": 36 } },
              { "inputs": ["r1"], "frame": { "x": 333, "y": 585, "width": 99, "height": 37 } },
              { "inputs": ["menu"], "frame": { "x": 383, "y": 461, "width": 47, "height": 64 } },
              { "inputs": ["toggleFastForward"], "frame": { "x": 282, "y": 460, "width": 54, "height": 67 } },
              { "inputs": ["quickSave"], "frame": { "x": 2, "y": 462, "width": 48, "height": 71 } },
              { "inputs": ["quickLoad"], "frame": { "x": 102, "y": 461, "width": 43, "height": 68 } }
            ]
            """#,
            singleTokens: ["a", "b", "x", "y", "start", "l1", "r1", "menu", "toggleFastForward", "quickSave", "quickLoad"]
        ),
        Fixture(
            name: "GameCube Pocket (Manic, l2/r2)",
            gameTypeIdentifier: "public.aoshuang.game.dc",
            mappingSize: CGSize(width: 375, height: 812),
            itemsJSON: #"""
            [
              { "inputs": { "down": "leftThumbstickDown", "left": "leftThumbstickLeft", "right": "leftThumbstickRight", "up": "leftThumbstickUp" },
                "frame": { "x": 36, "y": 515, "width": 100, "height": 100 }, "thumbstick": { "name": "stick.png", "width": 100, "height": 100 } },
              { "inputs": { "down": "rightThumbstickDown", "left": "rightThumbstickLeft", "right": "rightThumbstickRight", "up": "rightThumbstickUp" },
                "frame": { "x": 224, "y": 669, "width": 70, "height": 70 }, "thumbstick": { "name": "cstick.png", "width": 70, "height": 70 } },
              { "inputs": { "down": "down", "left": "left", "right": "right", "up": "up" }, "frame": { "x": 79, "y": 664, "width": 79, "height": 79 } },
              { "inputs": ["a"], "frame": { "x": 253, "y": 526, "width": 75, "height": 75 } },
              { "inputs": ["b"], "frame": { "x": 198, "y": 574, "width": 47, "height": 47 } },
              { "inputs": ["x"], "frame": { "x": 333, "y": 501, "width": 48, "height": 69 } },
              { "inputs": ["y"], "frame": { "x": 247, "y": 471, "width": 70, "height": 40 } },
              { "inputs": ["r1"], "frame": { "x": 202, "y": 510, "width": 34, "height": 34 } },
              { "inputs": ["l2"], "frame": { "x": 15, "y": 422, "width": 106, "height": 44 } },
              { "inputs": ["r2"], "frame": { "x": 254, "y": 422, "width": 106, "height": 44 } },
              { "inputs": ["quickSave"], "frame": { "x": 75, "y": 372, "width": 50, "height": 16 } },
              { "inputs": ["quickLoad"], "frame": { "x": 247, "y": 372, "width": 50, "height": 16 } },
              { "inputs": ["start"], "frame": { "x": 174, "y": 761, "width": 26, "height": 26 } },
              { "inputs": ["menu"], "frame": { "x": 20, "y": 767, "width": 26, "height": 26 } }
            ]
            """#,
            singleTokens: ["a", "b", "x", "y", "r1", "l2", "r2", "quickSave", "quickLoad", "start", "menu"]
        )
    ]

    private static func load(_ fixture: Fixture) throws -> DeltaSkin {
        let json = """
        {
          "name": "\(fixture.name)",
          "identifier": "test.dreamcast.\(UUID().uuidString)",
          "gameTypeIdentifier": "\(fixture.gameTypeIdentifier)",
          "debug": false,
          "representations": { "iphone": { "edgeToEdge": { "portrait": {
            "assets": { "small": "portrait.png", "medium": "portrait.png", "large": "portrait.png" },
            "mappingSize": { "width": \(Int(fixture.mappingSize.width)), "height": \(Int(fixture.mappingSize.height)) },
            "translucent": false,
            "screens": [ { "outputFrame": { "x": 8, "y": 88, "width": 359, "height": 269 } } ],
            "items": \(fixture.itemsJSON)
          } } } }
        }
        """
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RealDreamcast-\(UUID().uuidString).manicskin", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: dir.appendingPathComponent("info.json"))
        return try DeltaSkin(fileURL: dir)
    }

    private static let portrait = DeltaSkinTraits(device: .iphone, displayType: .edgeToEdge, orientation: .portrait)

    @Test("The skin loads as a Dreamcast skin and yields the tokens its items name", arguments: fixtures)
    func tokens(fixture: Fixture) throws {
        let skin = try Self.load(fixture)
        #expect(skin.gameType == .dreamcast)
        let buttons = try #require(skin.buttons(for: Self.portrait))
        let single: [String] = buttons.compactMap {
            if case .single(let token) = $0.input { return token }
            return nil
        }
        #expect(single == fixture.singleTokens)
    }
}
