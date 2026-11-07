#if canImport(UIKit)
import Foundation
import SkinKitCore
import SkinKitManager
import SwiftUI
import Testing
import UIKit
@testable import SkinKitUI

/// The options sheet and the edit overlay, built from a real `DeltaSkin` and hosted in a window.
extension UIKitSerial {
    @Suite("Options sheet and edit overlay", .serialized)
    @MainActor
    struct DeltaSkinOptionsViewTests {

        init() {
            TestSupport.disableDefaultSkinFallback()
        }

        private let representation: [String: Any] = [
            "assets": ["resizable": "skin.pdf"],
            "mappingSize": ["width": 100, "height": 200],
            "items": [[
                "inputs": ["a"],
                "frame": ["x": 60, "y": 150, "width": 20, "height": 20],
            ]],
        ]

        /// A skin with an alternate layout set and a `gameOverrides` entry for "Metroid" (iPhone only).
        private func skin(in scratch: URL) throws -> DeltaSkin {
            var info = TestSupport.gbaInfo(identifier: "com.test.options.\(UUID().uuidString)", asset: "skin.pdf", extraItems: [
                ["inputs": ["a"], "frame": ["x": 60, "y": 150, "width": 20, "height": 20]],
            ])
            let reps = ["iphone": ["standard": ["portrait": representation]]]
            info["altRepresentations"] = reps
            info["gameOverrides"] = ["Metroid": reps]
            let url = try TestSupport.writeSkin(info: info, files: ["skin.pdf": TestSupport.makePDFData()], in: scratch)
            return try DeltaSkin(fileURL: url)
        }

        private func host<V: View>(_ view: V, size: CGSize = CGSize(width: 390, height: 844)) -> UIWindow {
            let controller = UIHostingController(rootView: view.frame(width: size.width, height: size.height))
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.frame = window.bounds
            controller.view.layoutIfNeeded()
            return window
        }

        @Test("The skin reports its alternate set, and its game override matches by candidate order")
        func skinOverrideMatch() throws {
            let scratch = try TestSupport.makeScratch()
            defer { try? FileManager.default.removeItem(at: scratch) }
            let skin = try skin(in: scratch)
            #expect(skin.hasAltRepresentations)

            let traits = DeltaSkinTraits(device: .iphone, displayType: .standard, orientation: .portrait,
                                         gameIdentifiers: ["0123abcd", "metroid"])
            #expect(DeltaSkinOptionsModel.matchedOverrideKey(skin: skin, traits: traits) == "Metroid")
            let other = DeltaSkinTraits(device: .iphone, displayType: .standard, orientation: .portrait, gameIdentifier: "Zelda")
            #expect(DeltaSkinOptionsModel.matchedOverrideKey(skin: skin, traits: other) == nil)
            let noGame = DeltaSkinTraits(device: .iphone, displayType: .standard, orientation: .portrait)
            #expect(DeltaSkinOptionsModel.matchedOverrideKey(skin: skin, traits: noGame) == nil)
            let ipad = DeltaSkinTraits(device: .ipad, displayType: .standard, orientation: .portrait, gameIdentifier: "Metroid")
            #expect(DeltaSkinOptionsModel.matchedOverrideKey(skin: skin, traits: ipad) == nil)
        }

        @Test("The options sheet builds with every row, and with none")
        func optionsViewRenders() throws {
            let scratch = try TestSupport.makeScratch()
            defer { try? FileManager.default.removeItem(at: scratch) }
            let skin = try skin(in: scratch)
            let store = DeltaSkinLayoutEdits(editsDirectory: scratch.appendingPathComponent("edits"))
            let traits = DeltaSkinTraits(device: .iphone, displayType: .standard, orientation: .portrait, gameIdentifier: "Metroid")

            let full = host(NavigationStack {
                DeltaSkinOptionsView(
                    skin: skin, traits: traits, gameId: "game-1", gameTitle: "Metroid",
                    layoutEdits: store, onEditControls: {}, onExport: {}
                )
            })
            #expect(full.rootViewController?.view.bounds.width == 390)
            full.isHidden = true

            // No game, no closures: only the skin name remains, and building it must not fail.
            let bare = host(NavigationStack {
                DeltaSkinOptionsView(skin: skin, traits: DeltaSkinTraits(), layoutEdits: store)
            })
            #expect(bare.rootViewController?.view.bounds.width == 390)
            bare.isHidden = true
        }

        @Test("The alternate-layout choice is stored per game through the store the sheet is given")
        func altStoreRoundTrip() throws {
            let defaults = UserDefaults(suiteName: "DeltaSkinOptionsViewTests-\(UUID().uuidString)")!
            let preferences = DeltaSkinPreferences(defaults: defaults)
            let keys = DeltaSkinOptionsModel.altGameKeys(gameId: "game-1", traitGameKeys: ["md5-1"])
            preferences.setUsesAltRepresentations(true, skinIdentifier: "s", gameId: keys[0], otherGameKeys: Array(keys.dropFirst()))
            #expect(preferences.usesAltRepresentations(skinIdentifier: "s", gameIds: keys))
            #expect(preferences.usesAltRepresentations(skinIdentifier: "s", gameIds: ["game-1"]))
            preferences.setUsesAltRepresentations(false, skinIdentifier: "s", gameId: keys[0], otherGameKeys: Array(keys.dropFirst()))
            #expect(!preferences.usesAltRepresentations(skinIdentifier: "s", gameIds: keys))
        }

        @Test("Both overlay initializers build and draw")
        func overlayRenders() throws {
            let scratch = try TestSupport.makeScratch()
            defer { try? FileManager.default.removeItem(at: scratch) }
            let skin = try skin(in: scratch)
            let store = DeltaSkinLayoutEdits(editsDirectory: scratch.appendingPathComponent("edits"))
            let traits = DeltaSkinTraits(device: .iphone, displayType: .standard, orientation: .portrait)
            let size = CGSize(width: 200, height: 400)
            var doneCount = 0

            let current = host(
                DeltaSkinEditModeOverlay(
                    skin: skin, traits: traits, mappingSize: CGSize(width: 100, height: 200), containerSize: size,
                    layoutEdits: store, onEditsChanged: {}, onDone: { doneCount += 1 }
                ),
                size: size
            )
            #expect(current.rootViewController?.view.bounds.size == size)
            current.isHidden = true

            let legacy = host(
                DeltaSkinEditModeOverlay(
                    skin: skin, traits: traits, mappingSize: CGSize(width: 100, height: 200), containerSize: size,
                    buttonOffsets: .shared, onOffsetChanged: { _, _ in }
                ),
                size: size
            )
            #expect(legacy.rootViewController?.view.bounds.size == size)
            legacy.isHidden = true
            #expect(doneCount == 0)
        }
    }
}
#endif
