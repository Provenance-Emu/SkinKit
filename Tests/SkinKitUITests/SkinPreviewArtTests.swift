#if canImport(UIKit)
import Foundation
import SkinKitCore
import Testing
import UIKit
@testable import SkinKitUI

/// A skin's preview has to show the art the game view draws over the background: buttons with
/// images of their own and thumbstick caps. Previews used to draw the background alone.
extension UIKitSerial {
    @Suite("Skin preview control art", .serialized)
    struct SkinPreviewArtTests {
        private static let buttonFrame = CGRect(x: 60, y: 120, width: 30, height: 30)
        private static let stickFrame = CGRect(x: 10, y: 120, width: 40, height: 40)
        private static let mapping = CGSize(width: 100, height: 200)

        init() {
            TestSupport.disableDefaultSkinFallback()
            TestSupport.clearDiskRasterCache()
        }

        /// Red background, a green button image and a blue thumbstick cap.
        private func skin(in scratch: URL, identifier: String, withArt: Bool = true) throws -> DeltaSkin {
            func frame(_ rect: CGRect) -> [String: Any] {
                ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
            }
            let items: [[String: Any]] = withArt ? [
                ["inputs": ["a"], "frame": frame(Self.buttonFrame), "asset": ["normal": "button.png"]],
                ["inputs": ["up": "analogStickUp", "down": "analogStickDown", "left": "analogStickLeft", "right": "analogStickRight"],
                 "frame": frame(Self.stickFrame),
                 "thumbstick": ["name": "stick.png", "width": 20, "height": 20]],
            ] : [["inputs": ["a"], "frame": frame(Self.buttonFrame)]]
            let url = try TestSupport.writeSkin(
                info: TestSupport.gbaInfo(identifier: identifier, asset: "base.pdf", extraItems: items),
                files: [
                    "base.pdf": TestSupport.makePDFData(size: Self.mapping, color: .red),
                    "button.png": TestSupport.makeOpaquePNG(color: .green),
                    "stick.png": TestSupport.makeOpaquePNG(color: .blue),
                ],
                in: scratch
            )
            return try DeltaSkin(fileURL: url)
        }

        /// The dominant colour of the part of `image` that covers `rect` (in mapping units), inset so
        /// neighbouring pixels do not bleed in.
        private func channel(of image: UIImage, in rect: CGRect) throws -> Channel {
            let cgImage = try #require(image.cgImage)
            let scaleX = CGFloat(cgImage.width) / Self.mapping.width
            let scaleY = CGFloat(cgImage.height) / Self.mapping.height
            let inner = rect.insetBy(dx: rect.width / 4, dy: rect.height / 4)
            let crop = CGRect(x: inner.minX * scaleX, y: inner.minY * scaleY,
                              width: inner.width * scaleX, height: inner.height * scaleY).integral
            return dominantChannel(of: UIImage(cgImage: try #require(cgImage.cropping(to: crop))))
        }

        @Test("The game view's art list has the button image and the thumbstick cap")
        func artIsResolved() async throws {
            let scratch = try TestSupport.makeScratch()
            defer { try? FileManager.default.removeItem(at: scratch) }
            let skin = try skin(in: scratch, identifier: "com.test.preview.art")

            let buttons = await skin.buttonArt(for: TestSupport.portrait)
            #expect(buttons.map(\.frame) == [Self.buttonFrame])
            #expect(buttons.allSatisfy { !$0.isThumbstick })

            let sticks = await skin.thumbstickArt(for: TestSupport.portrait)
            #expect(sticks.map(\.frame) == [Self.stickFrame])
            #expect(sticks.first?.thumbstickSize == CGSize(width: 20, height: 20))
        }

        @Test("The preview draws button art and thumbstick caps where the game view does")
        func previewShowsControlArt() async throws {
            let scratch = try TestSupport.makeScratch()
            defer { try? FileManager.default.removeItem(at: scratch) }
            let skin = try skin(in: scratch, identifier: "com.test.preview.composite")

            let background = try await skin.thumbnail(for: TestSupport.portrait, maxDimension: 256)
            #expect(try channel(of: background, in: Self.buttonFrame) == .red)
            #expect(try channel(of: background, in: Self.stickFrame) == .red)

            let preview = try await skin.previewImage(for: TestSupport.portrait, maxDimension: 256)
            #expect(preview.size == background.size)
            #expect(try channel(of: preview, in: Self.buttonFrame) == .green)
            #expect(try channel(of: preview, in: Self.stickFrame) == .blue)
            #expect(try channel(of: preview, in: CGRect(x: 0, y: 0, width: 100, height: 60)) == .red)
        }

        @Test("A skin with no control art gets its thumbnail as the preview")
        func previewWithoutArtIsTheThumbnail() async throws {
            let scratch = try TestSupport.makeScratch()
            defer { try? FileManager.default.removeItem(at: scratch) }
            let skin = try skin(in: scratch, identifier: "com.test.preview.plain", withArt: false)
            #expect(await skin.buttonArt(for: TestSupport.portrait).isEmpty)
            let preview = try await skin.previewImage(for: TestSupport.portrait, maxDimension: 256)
            #expect(try channel(of: preview, in: Self.buttonFrame) == .red)
        }
    }
}
#endif
