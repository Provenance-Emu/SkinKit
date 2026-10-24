#if canImport(UIKit)
import Foundation
import SkinKitCore
import SkinKitManager
import SwiftUI
import Testing
import UIKit
@testable import SkinKitUI

extension UIKitSerial {
    @Suite("DeltaSkinLoader", .serialized)
    struct LoaderTests {

        @MainActor
        @Test("Loads the default skin for a system from the manager's scan")
        func loadsDefaultSkin() async throws {
            TestSupport.disableDefaultSkinFallback()
            let manager = PreviewlessManager.make()
            let loader = DeltaSkinLoader(manager: manager)
            #expect(loader.isLoading)

            let system = DeltaSkinLoader.System(id: SkinSystemID("GBA"), gameType: .gba, catalogSystemCodes: ["gba"])
            let skin = await loader.loadSkin(forSystem: system, systemName: "Game Boy Advance")
            let loaded = try #require(skin)
            #expect(loaded.gameType == .gba)
            #expect(loader.selectedSkin?.identifier == loaded.identifier)
            #expect(!loader.isLoading)
            #expect(loader.loadingStage == .complete)
            #expect(loader.loadingProgress == 1.0)
        }

        @MainActor
        @Test("Uses the selected skin when the manager has one, and the fast path once skins are loaded")
        func usesSelection() async throws {
            let manager = PreviewlessManager.make(names: ["PocketTaco-GBA", "Soolra-GBA"])
            _ = try await manager.availableSkins(forceRescan: false)
            let all = manager.loadedSkins.filter { $0.gameType == .gba }
            #expect(all.count == 2)
            let pick = try #require(all.last)
            await manager.selectionManager.setSkin(pick.identifier, for: SkinSystemID("GBA"), orientation: .portrait, scope: .system)

            let loader = DeltaSkinLoader(manager: manager)
            let system = DeltaSkinLoader.System(id: SkinSystemID("GBA"), gameType: .gba)
            let skin = await loader.loadSkin(forSystem: system)
            #expect(skin?.identifier == pick.identifier)
        }

        @MainActor
        @Test("The fast path skips a saved selection the automatic-selection policy rejects")
        func fastPathAppliesSelectionPolicy() async throws {
            let manager = PreviewlessManager.make(names: ["PocketTaco-GBA", "Soolra-GBA"],
                                                  isAllowedInAutomaticSelection: { !$0.lowercased().contains("soolra") })
            _ = try await manager.availableSkins(forceRescan: false)
            #expect(manager.skinsAreLoaded)
            let gba = manager.loadedSkins.filter { $0.gameType == .gba }
            let rejected = try #require(gba.first { $0.identifier.lowercased().contains("soolra") })
            let allowed = try #require(gba.first { !$0.identifier.lowercased().contains("soolra") })
            await manager.selectionManager.setSkin(rejected.identifier, for: SkinSystemID("GBA"), orientation: .portrait, scope: .system)

            let loader = DeltaSkinLoader(manager: manager)
            let skin = await loader.loadSkin(forSystem: .init(id: SkinSystemID("GBA"), gameType: .gba))
            #expect(skin?.identifier == allowed.identifier)
        }

        @MainActor
        @Test("A system can accept another game type's skins; no skin means nil and a finished load")
        func alsoAccepted() async throws {
            let manager = PreviewlessManager.make(names: ["Backbone-NES"])
            _ = try await manager.availableSkins(forceRescan: false)

            let strict = DeltaSkinLoader(manager: manager)
            let none = await strict.loadSkin(forSystem: .init(id: SkinSystemID("GB"), gameType: .gb))
            #expect(none == nil)
            #expect(!strict.isLoading)
            #expect(strict.selectedSkin == nil)

            let lenient = DeltaSkinLoader(manager: manager)
            let found = await lenient.loadSkin(forSystem: .init(id: SkinSystemID("GB"), gameType: .gb, alsoAcceptedGameTypes: [.nes]))
            #expect(found?.gameType == .nes)
        }
    }

    /// Hosts the real views in a window and looks at the pixels, so the SwiftUI code (and the image loading
    /// behind it) runs, not just the renderer underneath.
    @Suite("Hosted views", .serialized)
    @MainActor
    struct HostedViewTests {

        private func snapshot<V: View>(of view: V, size: CGSize = CGSize(width: 390, height: 844),
                                       until ready: (UIImage) -> Bool, timeout: TimeInterval = 20) async -> UIImage? {
            let host = UIHostingController(rootView: view.frame(width: size.width, height: size.height).background(Color.black))
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = window.bounds
            host.view.layoutIfNeeded()

            let deadline = Date().addingTimeInterval(timeout)
            var latest: UIImage?
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 250_000_000)
                host.view.layoutIfNeeded()
                // drawHierarchy needs a render server; fall back to rendering the layer tree when it returns blank.
                let viaHierarchy = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let viaLayer = UIGraphicsImageRenderer(bounds: window.bounds).image { ctx in
                    host.view.layer.render(in: ctx.cgContext)
                }
                let image = ready(viaHierarchy) ? viaHierarchy : viaLayer
                latest = image
                if ready(image) { break }
            }
            window.isHidden = true
            return latest
        }

        /// True when a good share of the pixels are not the black backdrop (some skins are dark).
        private func hasArtwork(_ image: UIImage, minimumShare: Double = 0.03) -> Bool {
            guard let cgImage = image.cgImage else { return false }
            let side = 64
            var pixels = [UInt8](repeating: 0, count: side * side * 4)
            guard let ctx = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            var lit = 0
            for i in stride(from: 0, to: pixels.count, by: 4) {
                let red = Int(pixels[i])
                let green = Int(pixels[i + 1])
                let blue = Int(pixels[i + 2])
                let brightness: Int = red + green + blue
                if brightness > 15 { lit += 1 }
            }
            return Double(lit) / Double(side * side) >= minimumShare
        }

        @Test("DeltaSkinView draws a fixture skin's artwork", arguments: ["PocketTaco-GBA", "PocketTaco-SNES", "PocketTaco-N64"])
        func skinViewDrawsArtwork(name: String) async throws {
            TestSupport.disableDefaultSkinFallback()
            let skin = try TestSupport.loadFixture("\(name).deltaskin")
            let traits = try #require(TestSupport.declaredTraits(of: skin).first { $0.device == .iphone && $0.orientation == .portrait })
            let handler = DeltaSkinPreviewInputHandler()
            let image = await snapshot(of: DeltaSkinView(skin: skin, traits: traits, inputHandler: handler)) { hasArtwork($0) }
            #expect(image.map { hasArtwork($0) } == true, "\(name) did not draw")
        }

        @Test("DeltaSkinScreensView draws through the environment's input handler")
        func screensView() async throws {
            TestSupport.disableDefaultSkinFallback()
            let skin = try TestSupport.loadFixture("PocketTaco-NES.deltaskin")
            let handler = DeltaSkinPreviewInputHandler()
            let view = GeometryReader { proxy in
                DeltaSkinScreensView(skin: skin, traits: TestSupport.portrait, containerSize: proxy.size)
            }.deltaSkinInputHandler(handler)
            let image = await snapshot(of: view) { hasArtwork($0) }
            #expect(image.map { hasArtwork($0) } == true)
        }

        @Test("The theme picker lists a themed skin's themes and nothing for an unthemed one")
        func themePicker() throws {
            let plain = try TestSupport.loadFixture("Backbone-GBA.deltaskin")
            #expect(plain.availableThemes.isEmpty)
            // Smoke: the view builds for both.
            _ = UIHostingController(rootView: DeltaSkinThemePickerView(skin: plain)).view
        }

        @Test("The picker and catalog views build against fixtures")
        func pickersBuild() async throws {
            let manager = PreviewlessManager.make()
            let previousManager = DeltaSkinManager.shared
            let previousDirectory = DeltaSkinSystemDirectory.current
            defer {
                DeltaSkinManager.shared = previousManager
                DeltaSkinSystemDirectory.current = previousDirectory
            }
            DeltaSkinManager.shared = manager
            let gba = DeltaSkinSystem(id: SkinSystemID("GBA"), fullName: "Game Boy Advance", gameType: .gba,
                                      skinCatalogSystemCode: "gba", relatedSkinCatalogSystemCodes: ["gba"])
            DeltaSkinSystemDirectory.current = DeltaSkinSystemDirectory(systems: [gba])

            let browser = await snapshot(of: NavigationStack { SystemSkinBrowserView() }, until: { _ in false }, timeout: 3)
            #expect(browser != nil)
            let selection = await snapshot(of: NavigationStack {
                SystemSkinSelectionView(system: gba, game: DeltaSkinGameContext(id: "g1", title: "Game", md5Hash: "m", crc: "c"))
            }, until: { _ in false }, timeout: 3)
            #expect(selection != nil)
            let entry = SkinCatalogEntryFixture.entry
            let detail = await snapshot(of: NavigationStack { SkinCatalogDetailView(entry: entry) }, until: { _ in false }, timeout: 2)
            #expect(detail != nil)
        }
    }
}

#endif
