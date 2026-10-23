#if canImport(UIKit)
import Foundation
import SkinKitCore
import SkinKitManager
import Testing
import UIKit
@testable import SkinKitUI

/// The rendering side of `DeltaSkinExporter` (the exporter's own tests live in SkinKitManagerTests):
/// an exported skin must still draw its artwork, and the skin type the exporter takes can be a renderable one.
extension UIKitSerial {
    @Suite("Exporter rendering", .serialized)
    struct ExporterRenderingTests {

        init() {
            TestSupport.disableDefaultSkinFallback()
            TestSupport.clearDiskRasterCache()
        }

        private let item: [String: Any] = [
            "inputs": ["a"],
            "frame": ["x": 10, "y": 20, "width": 30, "height": 30],
        ]

        @Test("An exported directory skin renders the same artwork")
        func exportedDirectorySkinRenders() async throws {
            let scratch = try TestSupport.makeScratch()
            defer { try? FileManager.default.removeItem(at: scratch) }
            let skin = try DeltaSkin(fileURL: TestSupport.writeSkin(
                info: TestSupport.gbaInfo(identifier: "com.test.export.render", asset: "art.pdf", extraItems: [item]),
                files: ["art.pdf": TestSupport.makePDFData()],
                in: scratch))

            let exportedURL = try await DeltaSkinExporter.export(
                skin: skin, traits: TestSupport.portrait, modifiedFrames: [0: CGRect(x: 1, y: 2, width: 3, height: 4)])
            defer { try? FileManager.default.removeItem(at: exportedURL) }

            let exported = try DeltaSkin(fileURL: exportedURL)
            let original = try await skin.image(for: TestSupport.portrait)
            let image = try await exported.image(for: TestSupport.portrait)
            #expect(image.hasVisibleContent)
            #expect(image.size == original.size)
            #expect(exported.buttons(for: TestSupport.portrait)?.first?.frame == CGRect(x: 1, y: 2, width: 3, height: 4))
        }

        @Test("An exported copy of a bundled skin still renders")
        func exportedFixtureRenders() async throws {
            let skin = try TestSupport.loadFixture("PocketTaco-GBA.deltaskin")
            let traits = try #require(TestSupport.declaredTraits(of: skin).first)
            let exportedURL = try await DeltaSkinExporter.export(skin: skin, traits: traits, modifiedFrames: [:])
            defer { try? FileManager.default.removeItem(at: exportedURL) }

            let exported = try DeltaSkin(fileURL: exportedURL)
            let image = try await exported.image(for: traits)
            #expect(image.hasVisibleContent)
        }

        @Test("The mock skin is renderable and the exporter accepts it")
        func mockSkinIsRenderable() async throws {
            let mock = MockDeltaSkin()
            let renderable: any DeltaSkinRenderable = mock
            let image = try await renderable.image(for: TestSupport.portrait)
            #expect(image.size.width >= 0)
            let thumbnail = try await renderable.thumbnail(for: TestSupport.portrait, maxDimension: 50)
            #expect(thumbnail.size.width >= 0)
            #expect(mock.screenGroups(for: TestSupport.portrait)?.count == 1)
        }
    }
}

#endif
