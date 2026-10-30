#if canImport(UIKit)
import Foundation
import SkinKitCore
import SwiftUI
import Testing
@testable import SkinKitUI

extension UIKitSerial {
    @Suite("Per-control artwork representation", .serialized)
    @MainActor
    struct RawSkinItemLookupTests {
        private func makeSkin(_ layouts: [DeltaSkinDisplayType: [DeltaSkinOrientation: String]]) throws -> (DeltaSkin, URL) {
            let scratch = try TestSupport.makeScratch("RawSkinItems")
            var displays: [String: Any] = [:]
            for (display, orientations) in layouts {
                var variants: [String: Any] = [:]
                for (orientation, name) in orientations {
                    variants[orientation.rawValue] = [
                        "assets": ["resizable": "background.pdf"],
                        "mappingSize": ["width": 200, "height": 400],
                        "items": [
                            ["inputs": ["a"], "frame": ["x": 20, "y": 250, "width": 60, "height": 60],
                             "asset": ["normal": "\(name).pdf", "pressed": "\(name)-pressed.pdf"]],
                            ["inputs": ["up": "leftThumbstickUp", "down": "leftThumbstickDown",
                                        "left": "leftThumbstickLeft", "right": "leftThumbstickRight"],
                             "frame": ["x": 100, "y": 300, "width": 60, "height": 60],
                             "thumbstick": ["name": "\(name)-stick.pdf", "width": 32, "height": 32]],
                        ],
                    ]
                }
                displays[display.rawValue] = variants
            }
            let info: [String: Any] = [
                "name": "Raw Items", "identifier": "test.raw-items.\(UUID().uuidString)",
                "gameTypeIdentifier": "public.aoshuang.game.dc",
                "representations": ["iphone": displays],
            ]
            let url = try TestSupport.writeSkin(info: info, files: [:], in: scratch)
            return (try DeltaSkin(fileURL: url), scratch)
        }

        private func expectAssets(_ name: String, skin: DeltaSkin, display: DeltaSkinDisplayType) throws {
            let traits = DeltaSkinTraits(device: .iphone, displayType: display, orientation: .portrait)
            let buttons = try #require(skin.buttons(for: traits))
            #expect(buttons.count == 2)
            let view = DeltaSkinView(skin: skin, traits: traits, isInEmulator: true, inputHandler: DeltaSkinPreviewInputHandler())
            let face = try #require(view.rawItem(matching: buttons[0])?["asset"] as? [String: String])
            #expect(face["normal"] == "\(name).pdf")
            #expect(face["pressed"] == "\(name)-pressed.pdf")
            let stick = try #require(view.rawItem(matching: buttons[1])?["thumbstick"] as? [String: Any])
            #expect(stick["name"] as? String == "\(name)-stick.pdf")
        }

        @Test("Standard traits use edge-to-edge button and thumbstick art when that is the available layout")
        func standardFallsBackToEdgeToEdge() throws {
            let (skin, scratch) = try makeSkin([.edgeToEdge: [.portrait: "edge"]])
            defer { try? FileManager.default.removeItem(at: scratch) }
            try expectAssets("edge", skin: skin, display: .standard)
        }

        @Test("Edge-to-edge traits use standard control art when that is the available layout")
        func edgeToEdgeFallsBackToStandard() throws {
            let (skin, scratch) = try makeSkin([.standard: [.portrait: "standard"]])
            defer { try? FileManager.default.removeItem(at: scratch) }
            try expectAssets("standard", skin: skin, display: .edgeToEdge)
        }

        @Test("The exact layout wins when both buckets contain the requested orientation")
        func exactLayoutWins() throws {
            let (skin, scratch) = try makeSkin([.standard: [.portrait: "standard"], .edgeToEdge: [.portrait: "edge"]])
            defer { try? FileManager.default.removeItem(at: scratch) }
            try expectAssets("standard", skin: skin, display: .standard)
            try expectAssets("edge", skin: skin, display: .edgeToEdge)
        }

        @Test("A missing orientation follows the same fallback as the decoded buttons")
        func orientationFallbackMatchesButtons() throws {
            let (skin, scratch) = try makeSkin([.standard: [.landscape: "wide"], .edgeToEdge: [.portrait: "edge"]])
            defer { try? FileManager.default.removeItem(at: scratch) }
            try expectAssets("edge", skin: skin, display: .standard)
        }

        @Test("No raw controls are returned for an unsupported orientation")
        func missingOrientationReturnsNil() throws {
            let (skin, scratch) = try makeSkin([.standard: [.landscape: "wide"], .edgeToEdge: [.landscape: "edge-wide"]])
            defer { try? FileManager.default.removeItem(at: scratch) }
            let traits = DeltaSkinTraits(device: .iphone, displayType: .standard, orientation: .portrait)
            #expect(DeltaSkinView(skin: skin, traits: traits, inputHandler: DeltaSkinPreviewInputHandler()).rawButtonItems() == nil)
        }

        @Test("Special display modes do not borrow fullscreen control art")
        func specialDisplaysDoNotFallBack() throws {
            let (skin, scratch) = try makeSkin([.edgeToEdge: [.portrait: "edge"]])
            defer { try? FileManager.default.removeItem(at: scratch) }
            let traits = DeltaSkinTraits(device: .iphone, displayType: .splitView, orientation: .portrait)
            #expect(DeltaSkinView(skin: skin, traits: traits, inputHandler: DeltaSkinPreviewInputHandler()).rawButtonItems() == nil)
        }
    }
}
#endif
