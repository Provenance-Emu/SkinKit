#if canImport(UIKit)
import Foundation
import SkinKitCore
import Testing
import UIKit
@testable import SkinKitUI

/// Theme artwork overrides and thumbstick image loading, on synthetic skins (no fixture ships either).
extension UIKitSerial {
    @Suite("Theme overrides and thumbsticks", .serialized)
    struct ThemeAndThumbstickTests {

        init() {
            TestSupport.disableDefaultSkinFallback()
            TestSupport.clearDiskRasterCache()
        }

        private func themedSkin(in dir: URL, identifier: String) throws -> DeltaSkin {
            let themes: [[String: Any]] = [[
                "id": "neon",
                "name": "Neon",
                "assets": ["iphone": ["standard": ["portrait": ["resizable": "neon.pdf"]]]],
            ]]
            let url = try TestSupport.writeSkin(
                info: TestSupport.gbaInfo(identifier: identifier, asset: "base.pdf", themes: themes),
                files: ["base.pdf": TestSupport.makePDFData(color: .red), "neon.pdf": TestSupport.makePDFData(color: .green)],
                in: dir)
            return try DeltaSkin(fileURL: url)
        }

        @Test("Without a selected theme the candidates are the skin's own artwork")
        func baseCandidates() throws {
            let scratch = try TestSupport.makeScratch()
            defer { try? FileManager.default.removeItem(at: scratch) }
            var skin = try themedSkin(in: scratch, identifier: "com.test.theme.base")
            skin.selectedThemeId = nil
            let rep = try #require(skin.representation(for: TestSupport.portrait))
            #expect(skin.availableThemes.map(\.id) == ["neon"])
            #expect(skin.assetCandidates(for: rep, traits: TestSupport.portrait) == rep.assets.candidates())
        }

        @Test("A selected theme's artwork is tried first, then the base artwork")
        func themeCandidatesComeFirst() throws {
            let scratch = try TestSupport.makeScratch()
            defer { try? FileManager.default.removeItem(at: scratch) }
            var skin = try themedSkin(in: scratch, identifier: "com.test.theme.override")
            skin.selectedThemeId = "neon"
            defer { skin.selectedThemeId = nil }
            let rep = try #require(skin.representation(for: TestSupport.portrait))
            let candidates = skin.assetCandidates(for: rep, traits: TestSupport.portrait)
            let base = rep.assets.candidates()
            #expect(candidates.count == base.count + 1)
            #expect(candidates.first?.contains("neon") == true)
            #expect(Array(candidates.dropFirst()) == base)
        }

        @Test("A selected theme that does not cover the traits falls back to the base artwork")
        func themeWithoutMatchingTraits() throws {
            let scratch = try TestSupport.makeScratch()
            defer { try? FileManager.default.removeItem(at: scratch) }
            var skin = try themedSkin(in: scratch, identifier: "com.test.theme.other-traits")
            skin.selectedThemeId = "neon"
            defer { skin.selectedThemeId = nil }
            let rep = try #require(skin.representation(for: TestSupport.portrait))
            let landscape = DeltaSkinTraits(device: .iphone, displayType: .standard, orientation: .landscape)
            #expect(skin.assetCandidates(for: rep, traits: landscape) == rep.assets.candidates())
        }

        @Test("The theme's artwork is what image(for:) draws")
        func themeArtworkIsRendered() async throws {
            let scratch = try TestSupport.makeScratch()
            defer { try? FileManager.default.removeItem(at: scratch) }
            var skin = try themedSkin(in: scratch, identifier: "com.test.theme.render")
            skin.selectedThemeId = nil
            let base = try await skin.image(for: TestSupport.portrait)
            skin.selectedThemeId = "neon"
            defer { skin.selectedThemeId = nil }
            let themed = try await skin.image(for: TestSupport.portrait)
            #expect(base.hasVisibleContent && themed.hasVisibleContent)
            #expect(dominantChannel(of: base) == .red)
            #expect(dominantChannel(of: themed) == .green)
        }

        // MARK: Per-item theme artwork

        /// `Themes/Themed-Buttons-GBA.deltaskin`: background and item 0's own art are red; "neon" re-skins the
        /// background and items 0 and 1 in green, "ocean" the background and item 0 in blue; item 1 has no art of
        /// its own and no other item changes.
        private func buttonsSkin() throws -> DeltaSkin {
            var skin = try DeltaSkin(fileURL: TestSupport.fixtureURL("Themes/Themed-Buttons-GBA.deltaskin"))
            skin.selectedThemeId = nil
            return skin
        }

        @Test("Switching theme changes the background candidates and the item art together")
        func themeSwitchChangesBackgroundAndItemArt() async throws {
            var skin = try buttonsSkin()
            defer { skin.selectedThemeId = nil }
            let rep = try #require(skin.representation(for: TestSupport.portrait))

            skin.selectedThemeId = nil
            #expect(skin.assetCandidates(for: rep, traits: TestSupport.portrait) == rep.assets.candidates())
            #expect(await skin.themedItemImage(forItemAt: 0, traits: TestSupport.portrait) == nil)

            skin.selectedThemeId = "neon"
            #expect(skin.assetCandidates(for: rep, traits: TestSupport.portrait).first == "neon.png")
            let neonA = try #require(await skin.themedItemImage(forItemAt: 0, traits: TestSupport.portrait))
            let neonB = try #require(await skin.themedItemImage(forItemAt: 1, traits: TestSupport.portrait))
            #expect(dominantChannel(of: neonA) == .green)
            #expect(dominantChannel(of: neonB) == .green)
            #expect(await skin.themedItemImage(forItemAt: 2, traits: TestSupport.portrait) == nil)

            skin.selectedThemeId = "ocean"
            #expect(skin.assetCandidates(for: rep, traits: TestSupport.portrait).first == "ocean.png")
            let oceanA = try #require(await skin.themedItemImage(forItemAt: 0, traits: TestSupport.portrait))
            #expect(dominantChannel(of: oceanA) == .blue)
            #expect(await skin.themedItemImage(forItemAt: 1, traits: TestSupport.portrait) == nil)
        }

        @Test("The background is redrawn in the new theme's colour, the item art with it")
        func themeSwitchRedrawsBackgroundAndButtons() async throws {
            var skin = try buttonsSkin()
            defer { skin.selectedThemeId = nil }
            var backgrounds: [Channel] = []
            var buttons: [Channel?] = []
            for theme in [nil, "neon", "ocean"] as [String?] {
                skin.selectedThemeId = theme
                backgrounds.append(dominantChannel(of: try await skin.image(for: TestSupport.portrait)))
                if let art = await skin.themedItemImage(forItemAt: 0, traits: TestSupport.portrait) {
                    buttons.append(dominantChannel(of: art))
                } else {
                    // No theme art: the item's own art, `btn-a.png`, is drawn.
                    buttons.append(dominantChannel(of: try await skin.loadThumbstickImage(named: "btn-a.png")))
                }
            }
            #expect(backgrounds == [.red, .green, .blue])
            #expect(buttons == [.red, .green, .blue])
        }

        @Test("A background-only theme leaves every item on its own art")
        func backgroundOnlyThemeKeepsItemArt() async throws {
            var skin = try buttonsSkin()
            defer { skin.selectedThemeId = nil }
            skin.selectedThemeId = "plain"
            let rep = try #require(skin.representation(for: TestSupport.portrait))
            #expect(skin.assetCandidates(for: rep, traits: TestSupport.portrait).first == "neon.png")
            for index in 0..<3 {
                #expect(await skin.themedItemImage(forItemAt: index, traits: TestSupport.portrait) == nil)
            }
        }

        @Test("Theme item art whose files are missing falls back to the item's own art")
        func missingThemeItemFilesFallBack() async throws {
            let scratch = try TestSupport.makeScratch()
            defer { try? FileManager.default.removeItem(at: scratch) }
            let themes: [[String: Any]] = [[
                "id": "broken", "name": "Broken",
                "assets": ["iphone": ["standard": ["portrait": [
                    "resizable": "base.pdf", "items": ["0": ["resizable": "not-in-the-archive.png"]],
                ]]]],
            ]]
            var skin = try DeltaSkin(fileURL: TestSupport.writeSkin(
                info: TestSupport.gbaInfo(identifier: "com.test.theme.item-missing", asset: "base.pdf", themes: themes),
                files: ["base.pdf": TestSupport.makePDFData()],
                in: scratch))
            skin.selectedThemeId = "broken"
            defer { skin.selectedThemeId = nil }
            #expect(await skin.themedItemImage(forItemAt: 0, traits: TestSupport.portrait) == nil)
        }

        // MARK: Thumbsticks

        @Test("A PDF thumbstick loads with its alpha channel, and the second load is the cached image")
        func pdfThumbstick() async throws {
            let scratch = try TestSupport.makeScratch()
            defer { try? FileManager.default.removeItem(at: scratch) }
            let skin = try DeltaSkin(fileURL: TestSupport.writeSkin(
                info: TestSupport.gbaInfo(identifier: "com.test.thumbstick.pdf", asset: "base.pdf"),
                files: ["base.pdf": TestSupport.makePDFData(), "stick.pdf": TestSupport.makePDFData(size: CGSize(width: 40, height: 40))],
                in: scratch))
            let first = try await skin.loadThumbstickImage(named: "stick.pdf")
            #expect(first.hasVisibleContent)
            #expect(first.hasAlpha)
            let second = try await skin.loadThumbstickImage(named: "stick.pdf")
            #expect(first === second)
        }

        @Test("An opaque PNG thumbstick is converted to an image with alpha")
        func pngThumbstickGainsAlpha() async throws {
            let scratch = try TestSupport.makeScratch()
            defer { try? FileManager.default.removeItem(at: scratch) }
            let png = TestSupport.makeOpaquePNG()
            #expect(UIImage(data: png)?.hasAlpha == false)
            let skin = try DeltaSkin(fileURL: TestSupport.writeSkin(
                info: TestSupport.gbaInfo(identifier: "com.test.thumbstick.png", asset: "base.pdf"),
                files: ["base.pdf": TestSupport.makePDFData(), "stick.png": png],
                in: scratch))
            let image = try await skin.loadThumbstickImage(named: "stick.png")
            #expect(image.hasAlpha)
        }

        @Test("Missing thumbstick art and undecodable art throw")
        func thumbstickErrors() async throws {
            let scratch = try TestSupport.makeScratch()
            defer { try? FileManager.default.removeItem(at: scratch) }
            let skin = try DeltaSkin(fileURL: TestSupport.writeSkin(
                info: TestSupport.gbaInfo(identifier: "com.test.thumbstick.errors", asset: "base.pdf"),
                files: ["base.pdf": TestSupport.makePDFData(), "bad.pdf": Data("nope".utf8), "bad.png": Data("nope".utf8)],
                in: scratch))
            await #expect(throws: DeltaSkinError.self) { _ = try await skin.loadThumbstickImage(named: "missing.pdf") }
            await #expect(throws: DeltaSkinError.self) { _ = try await skin.loadThumbstickImage(named: "bad.pdf") }
            await #expect(throws: DeltaSkinError.self) { _ = try await skin.loadThumbstickImage(named: "bad.png") }
        }

        @Test("Calls through the refining protocol reach DeltaSkin's cached thumbstick loader")
        func thumbstickThroughProtocol() async throws {
            let scratch = try TestSupport.makeScratch()
            defer { try? FileManager.default.removeItem(at: scratch) }
            let skin = try DeltaSkin(fileURL: TestSupport.writeSkin(
                info: TestSupport.gbaInfo(identifier: "com.test.thumbstick.protocol", asset: "base.pdf"),
                files: ["base.pdf": TestSupport.makePDFData(), "stick.pdf": TestSupport.makePDFData(size: CGSize(width: 40, height: 40))],
                in: scratch))
            let existential: any DeltaSkinRenderable = skin
            let viaProtocol = try await existential.loadThumbstickImage(named: "stick.pdf")
            let direct = try await skin.loadThumbstickImage(named: "stick.pdf")
            #expect(viaProtocol === direct)
        }
    }
}

enum Channel { case red, green, blue, none }

/// Which colour channel dominates the visible pixels of an image.
func dominantChannel(of image: UIImage) -> Channel {
    guard let cgImage = image.cgImage else { return .none }
    let side = 16
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    guard let ctx = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .none }
    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
    var r = 0, g = 0, b = 0
    for i in stride(from: 0, to: pixels.count, by: 4) {
        r += Int(pixels[i]); g += Int(pixels[i + 1]); b += Int(pixels[i + 2])
    }
    if r > g, r > b { return .red }
    if g > r, g > b { return .green }
    if b > r, b > g { return .blue }
    return .none
}
#endif
