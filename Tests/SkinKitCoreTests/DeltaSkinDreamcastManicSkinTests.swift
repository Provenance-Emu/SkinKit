//
//  DeltaSkinDreamcastManicSkinTests.swift
//  SkinKitCoreTests
//
//  Ported from Provenance's DeltaSkinDreamcastTokenTests. Only the skin-side tests live here
//  (item parsing and the representation cache). The tests that map skin tokens to
//  `PVDreamcastButton` through `DeltaSkinInputHandler` stay in Provenance.
//

import Foundation
import Testing
import CoreGraphics
@testable import SkinKitCore

@Suite("Manic Dreamcast skin model")
struct DeltaSkinDreamcastManicSkinTests {

    // MARK: - Manic Dreamcast skin fixture

    /// Trimmed from the Manic EMU "Dreamsicle (White)" Dreamcast skin (deltastyles #568, catalog id
    /// 3957312ad9e7c59e): the iPhone edge-to-edge portrait items, including the per-item `asset`
    /// dictionaries and the all-zero `extendedEdges` Manic's editor writes.
    private static let manicDreamcastInfoJSON = #"""
    {
      "name": "Dreamsicle (White) by starvingartist",
      "identifier": "com.starvingartist.dc.dreamsicle-white",
      "gameTypeIdentifier": "public.aoshuang.game.dc",
      "debug": false,
      "representations": {
        "iphone": {
          "edgeToEdge": {
            "portrait": {
              "assets": { "small": "portrait.png", "medium": "portrait.png", "large": "portrait.png" },
              "mappingSize": { "width": 375, "height": 812 },
              "translucent": false,
              "screens": [ { "outputFrame": { "x": 8, "y": 88, "width": 359, "height": 269 } } ],
              "items": [
                { "inputs": { "up": "leftThumbstickUp", "down": "leftThumbstickDown", "left": "leftThumbstickLeft", "right": "leftThumbstickRight" },
                  "frame": { "x": 38, "y": 516, "width": 85, "height": 85 },
                  "thumbstick": { "name": "thumbstick.pdf", "width": 128, "height": 128 },
                  "extendedEdges": { "top": 0, "bottom": 0, "left": 0, "right": 0 } },
                { "inputs": { "up": "up", "down": "down", "left": "left", "right": "right" },
                  "frame": { "x": 50, "y": 644, "width": 104, "height": 104 },
                  "asset": { "normal": "dpad.pdf" },
                  "extendedEdges": { "top": 10, "bottom": 10, "left": 10, "right": 10 } },
                { "inputs": ["a"], "frame": { "x": 248, "y": 605, "width": 71, "height": 71 },
                  "asset": { "normal": "btn-a.pdf" }, "extendedEdges": { "top": 0, "bottom": 0, "left": 0, "right": 0 } },
                { "inputs": ["b"], "frame": { "x": 302, "y": 550, "width": 71, "height": 71 },
                  "asset": { "normal": "btn-b.pdf" }, "extendedEdges": { "top": 0, "bottom": 0, "left": 0, "right": 0 } },
                { "inputs": ["x"], "frame": { "x": 188, "y": 550, "width": 71, "height": 71 },
                  "asset": { "normal": "btn-x.pdf" }, "extendedEdges": { "top": 0, "bottom": 0, "left": 0, "right": 0 } },
                { "inputs": ["y"], "frame": { "x": 248, "y": 499, "width": 71, "height": 71 },
                  "asset": { "normal": "btn-y.pdf" }, "extendedEdges": { "top": 0, "bottom": 0, "left": 0, "right": 0 } },
                { "inputs": ["l1"], "frame": { "x": 6, "y": 441, "width": 115, "height": 53 },
                  "asset": { "normal": "btn-l.pdf" }, "extendedEdges": { "top": 0, "bottom": 0, "left": 7, "right": 0 } },
                { "inputs": ["r1"], "frame": { "x": 254, "y": 441, "width": 115, "height": 52 },
                  "asset": { "normal": "btn-r.pdf" }, "extendedEdges": { "top": 0, "bottom": 0, "left": 0, "right": 7 } },
                { "inputs": ["start"], "frame": { "x": 166, "y": 728, "width": 41, "height": 37 },
                  "asset": { "normal": "btn-start.pdf" }, "extendedEdges": { "top": 0, "bottom": 0, "left": 0, "right": 0 } },
                { "inputs": ["quickSave"], "frame": { "x": 52, "y": 382, "width": 60, "height": 30 } },
                { "inputs": ["menu"], "frame": { "x": 17, "y": 760, "width": 31, "height": 31 },
                  "asset": { "normal": "btn-menu.pdf" }, "extendedEdges": { "top": 0, "bottom": 21, "left": 17, "right": 0 } }
              ]
            }
          }
        }
      }
    }
    """#

    private static func loadSkin(infoJSON: String) throws -> DeltaSkin {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkinFixture-\(UUID().uuidString).manicskin", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(infoJSON.utf8).write(to: dir.appendingPathComponent("info.json"))
        return try DeltaSkin(fileURL: dir)
    }

    private static func loadManicDreamcastSkin() throws -> DeltaSkin {
        try loadSkin(infoJSON: manicDreamcastInfoJSON)
    }

    /// A second Dreamcast skin with the same traits but a different layout: one `start` item.
    private static let otherDreamcastInfoJSON = #"""
    {
      "name": "Other Dreamcast",
      "identifier": "com.example.dc.other",
      "gameTypeIdentifier": "com.rileytestut.delta.game.dc",
      "representations": {
        "iphone": {
          "edgeToEdge": {
            "portrait": {
              "assets": { "large": "other.png" },
              "mappingSize": { "width": 430, "height": 932 },
              "items": [
                { "inputs": ["start"], "frame": { "x": 187, "y": 826, "width": 51, "height": 27 } }
              ]
            }
          }
        }
      }
    }
    """#


    @Test("A skin's buttons never come from another skin's cached representation")
    func representationCacheIsPerSkin() throws {
        let manic = try Self.loadManicDreamcastSkin()
        let other = try Self.loadSkin(infoJSON: Self.otherDreamcastInfoJSON)
        // The emulator's skin view and the view controller both pass the game title.
        let traits = DeltaSkinTraits(device: .iphone, displayType: .edgeToEdge, orientation: .portrait,
                                     gameIdentifier: "Crazy Taxi")

        _ = other.buttons(for: traits)
        let manicButtons = try #require(manic.buttons(for: traits))
        #expect(manicButtons.count == 11)
        #expect(manic.mappingSize(for: traits) == CGSize(width: 375, height: 812))

        let otherButtons = try #require(other.buttons(for: traits))
        #expect(otherButtons.count == 1)
        #expect(other.mappingSize(for: traits) == CGSize(width: 430, height: 932))
    }

    @Test("Each Manic Dreamcast item yields the token it names")
    func manicSkinItemsYieldTheirTokens() throws {
        let skin = try Self.loadManicDreamcastSkin()
        let traits = DeltaSkinTraits(device: .iphone, displayType: .edgeToEdge, orientation: .portrait)
        let buttons = try #require(skin.buttons(for: traits))

        let singleTokens: [String] = buttons.compactMap {
            if case .single(let token) = $0.input { return token }
            return nil
        }
        #expect(singleTokens == ["a", "b", "x", "y", "l1", "r1", "start", "quickSave", "menu"])

        let directional = buttons.filter { if case .directional = $0.input { return true }; return false }
        #expect(directional.count == 2, "thumbstick + d-pad")
    }
}
