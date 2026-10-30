#if canImport(UIKit)
import Foundation
import SkinKitCore
import Testing
import UIKit
@testable import SkinKitUI

/// Renders every SkinKitCore fixture skin for every trait it declares and checks that real pixels
/// come out. The default-skin fallback is switched off and the disk raster cache cleared first, so
/// a broken render cannot pass through a substitute skin or a PNG left by an earlier run.
extension UIKitSerial {
    @Suite("Skin rendering")
    struct RenderingTests {

        init() {
            TestSupport.disableDefaultSkinFallback()
            TestSupport.clearDiskRasterCache()
        }

        @Test("The fixture set is complete")
        func fixturesPresent() {
            #expect(TestSupport.defaultSkinNames.count == 23)
            #expect(TestSupport.layoutOnlyNames.count == 5)
        }

        @Test("Every declared trait of every default skin renders visible artwork", arguments: TestSupport.defaultSkinNames)
        func rendersEveryTrait(name: String) async throws {
            let skin = try TestSupport.loadFixture(name)
            let traitsList = TestSupport.declaredTraits(of: skin)
            #expect(!traitsList.isEmpty, "\(name) declares no representations")
            for traits in traitsList {
                let image = try await skin.image(for: traits)
                #expect(image.size.width > 0 && image.size.height > 0, "\(name) \(traits.description)")
                #expect(image.hasVisibleContent, "\(name) \(traits.description) rendered blank")
            }
        }

        @Test("The layout-only test skins have no artwork, so rendering them throws instead of drawing a blank", arguments: TestSupport.layoutOnlyNames)
        func layoutOnlySkinsThrow(name: String) async throws {
            // DS-Test's info.json has `//` comments, which the loader rejects (known, moved as-is in SkinKitCore).
            guard let skin = try? TestSupport.loadFixture(name) else { return }
            let traits = try #require(TestSupport.declaredTraits(of: skin).first)
            await #expect(throws: DeltaSkinError.self) { _ = try await skin.image(for: traits) }
        }

        @Test("Thumbnails of every default skin are bounded and visible", arguments: TestSupport.defaultSkinNames)
        func rendersThumbnails(name: String) async throws {
            let skin = try TestSupport.loadFixture(name)
            let traits = try #require(TestSupport.declaredTraits(of: skin).first)
            let thumbnail = try await skin.thumbnail(for: traits, maxDimension: 120)
            #expect(max(thumbnail.size.width, thumbnail.size.height) <= 121)
            #expect(thumbnail.hasVisibleContent, "\(name) thumbnail rendered blank")
        }

        @MainActor
        @Test("Fresh and disk-cached thumbnails preserve point bounds and two-pixel density", arguments: ["pdf", "png", "svg"])
        func thumbnailPointSizeAndDiskCache(assetType: String) async throws {
            let scratch = try TestSupport.makeScratch()
            defer { try? FileManager.default.removeItem(at: scratch) }
            let name = "art.\(assetType)"
            let data: Data
            switch assetType {
            case "pdf": data = TestSupport.makePDFData(size: CGSize(width: 100, height: 200))
            case "png": data = TestSupport.makeOpaquePNG(size: CGSize(width: 100, height: 200))
            default:
                data = Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"200\" viewBox=\"0 0 100 200\"><rect width=\"100\" height=\"200\" fill=\"red\"/></svg>".utf8)
            }
            let url = try TestSupport.writeSkin(
                info: TestSupport.gbaInfo(identifier: "com.test.thumbnail-\(assetType)-\(UUID())", asset: name),
                files: [name: data], in: scratch
            )
            let skin = try DeltaSkin(fileURL: url)
            let fresh = try await skin.thumbnail(for: TestSupport.portrait, maxDimension: 120)
            #expect(fresh.size == CGSize(width: 60, height: 120))
            #expect(fresh.scale == 2)
            #expect(fresh.cgImage?.width == 120)
            #expect(fresh.cgImage?.height == 240)
            #expect(fresh.hasVisibleContent)

            // Corrupt the existing asset without replacing its directory. A successful
            // second load must use the persisted raster, not render the source again.
            try Data("invalid artwork".utf8).write(to: url.appendingPathComponent(name))
            let reopened = try DeltaSkin(fileURL: url)
            let cached = try await reopened.thumbnail(for: TestSupport.portrait, maxDimension: 120)
            #expect(cached.size == CGSize(width: 60, height: 120))
            #expect(cached.scale == 2)
            #expect(cached.cgImage?.width == 120)
            #expect(cached.cgImage?.height == 240)
            #expect(cached.hasVisibleContent)
        }

        @Test("A second render of the same traits is served from the cache")
        func secondRenderIsCached() async throws {
            // A small synthetic skin: a real 750x1334pt skin is ~36 MB at 3x, over the 32 MB budget of the
            // in-memory cache, so NSCache would drop it at once (unchanged from Provenance).
            let scratch = try TestSupport.makeScratch()
            defer { try? FileManager.default.removeItem(at: scratch) }
            let skin = try DeltaSkin(fileURL: TestSupport.writeSkin(
                info: TestSupport.gbaInfo(identifier: "com.test.memory-cache", asset: "art.pdf"),
                files: ["art.pdf": TestSupport.makePDFData()], in: scratch))
            let first = try await skin.image(for: TestSupport.portrait)
            let second = try await skin.image(for: TestSupport.portrait)
            #expect(first === second)
        }

        @Test("Unsupported traits throw instead of rendering")
        func unsupportedTraitsThrow() async throws {
            let skin = try TestSupport.loadFixture("PocketTaco-GBA.deltaskin")
            let traits = DeltaSkinTraits(device: .tv, displayType: .externalDisplay, orientation: .landscape)
            if skin.supports(traits) { return }
            await #expect(throws: DeltaSkinError.self) { _ = try await skin.image(for: traits) }
        }

        @Test("A raster is written to the disk cache for vector artwork")
        func vectorArtworkIsCachedOnDisk() async throws {
            let scratch = try TestSupport.makeScratch()
            defer { try? FileManager.default.removeItem(at: scratch) }
            let url = try TestSupport.writeSkin(
                info: TestSupport.gbaInfo(identifier: "com.test.disk-cache", asset: "art.pdf"),
                files: ["art.pdf": TestSupport.makePDFData()],
                in: scratch)
            let skin = try DeltaSkin(fileURL: url)
            _ = try await skin.image(for: TestSupport.portrait)

            let caches = try #require(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
            let dir = caches.appendingPathComponent("DeltaSkinImageCache", isDirectory: true)
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            #expect(files.contains { $0.hasSuffix(".png") })
        }

        @Test("Missing artwork throws; the default-skin fallback supplies a substitute when set")
        func defaultSkinFallback() async throws {
            let scratch = try TestSupport.makeScratch()
            defer { try? FileManager.default.removeItem(at: scratch) }
            let broken = try DeltaSkin(fileURL: TestSupport.writeSkin(
                info: TestSupport.gbaInfo(identifier: "com.test.broken", asset: "missing.pdf"), files: [:], in: scratch))
            await #expect(throws: (any Error).self) { _ = try await broken.image(for: TestSupport.portrait) }

            let substitute = try TestSupport.loadFixture("PocketTaco-GBA.deltaskin")
            let previous = DeltaSkinRendering.defaultSkinProvider
            DeltaSkinRendering.defaultSkinProvider = { _ in substitute }
            defer { DeltaSkinRendering.defaultSkinProvider = previous }
            #expect(substitute.supports(TestSupport.portrait))
            let image = try await broken.image(for: TestSupport.portrait)
            #expect(image.hasVisibleContent)
        }
    }
}

#endif
