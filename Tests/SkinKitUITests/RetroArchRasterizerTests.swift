#if canImport(UIKit) && !os(tvOS)
import Foundation
import SkinKitCore
import Testing
import UIKit
@testable import SkinKitRetroArch  // RetroArchImageRequest's initializer is internal
@testable import SkinKitUI

/// The rasterizer behind Send to RetroArch: pixel-exact sizes, cleared game screens, and the view's public pieces.
extension UIKitSerial {
    @Suite("Send to RetroArch rasterizer")
    struct RetroArchRasterizerTests {

        /// A solid opaque square as PNG data (the artwork stand-in).
        private static func artwork(color: UIColor = .red, side: CGFloat = 10) -> Data {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            }.pngData()!
        }

        private static func request(
            kind: RetroArchConversion.ImagePlan.Kind = .overlay,
            asset: Data = artwork(), ext: String = "png",
            width: Int = 40, height: Int = 20, ppp: Double = 2,
            clear: [RetroArchSkinInfo.Rect] = [], inner: (Double, Double)? = nil
        ) -> RetroArchImageRequest {
            RetroArchImageRequest(
                file: "x.png", kind: kind, assetName: "art.\(ext)", assetData: asset, fileExtension: ext,
                pixelWidth: width, pixelHeight: height, pixelsPerPoint: ppp,
                mappingWidth: Double(width) / ppp, mappingHeight: Double(height) / ppp, clearRects: clear,
                innerWidth: inner?.0, innerHeight: inner?.1)
        }

        /// RGBA of the pixel at (x, y) in PNG data.
        private static func pixel(_ png: Data, x: Int, y: Int) -> (size: CGSize, rgba: [UInt8]) {
            let image = UIImage(data: png)!.cgImage!
            var bytes = [UInt8](repeating: 0, count: 4)
            let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
            return (CGSize(width: image.width, height: image.height), bytes)
        }

        @Test("The PNG has exactly the requested pixel size, whatever the screen scale")
        func exactSize() throws {
            let png = try RetroArchRasterizer.png(for: Self.request(width: 123, height: 45))
            let (size, rgba) = Self.pixel(png, x: 60, y: 20)
            #expect(size == CGSize(width: 123, height: 45))
            #expect(rgba[3] == 255 && rgba[0] > 200, "artwork fills the overlay")
        }

        @Test("Game screens are transparent, scaled by pixels per point")
        func clearsScreens() throws {
            let screen = RetroArchSkinInfo.Rect(x: 0, y: 0, width: 10, height: 10)
            let png = try RetroArchRasterizer.png(for: Self.request(clear: [screen]))
            #expect(Self.pixel(png, x: 5, y: 5).rgba[3] == 0, "inside the cleared 20x20 pixel area")
            #expect(Self.pixel(png, x: 30, y: 5).rgba[3] == 255, "outside it")
        }

        @Test("A thumbstick cap is centered in its hitbox canvas")
        func thumbstickCap() throws {
            let png = try RetroArchRasterizer.png(for: Self.request(kind: .thumbstick, width: 40, height: 40, inner: (10, 10)))
            #expect(Self.pixel(png, x: 20, y: 20).rgba[3] == 255, "cap at the center")
            #expect(Self.pixel(png, x: 2, y: 2).rgba[3] == 0, "transparent corner")
        }

        @Test("Artwork that cannot be drawn is an error, not a blank PNG")
        func unreadableArtwork() {
            #expect(throws: RetroArchRasterizeError.self) {
                try RetroArchRasterizer.png(for: Self.request(asset: Data("nope".utf8), ext: "png"))
            }
            #expect(throws: RetroArchRasterizeError.self) {
                try RetroArchRasterizer.png(for: Self.request(asset: Data("nope".utf8), ext: "pdf"))
            }
        }

        @Test("RetroArchSendItem is identified by the skin's identifier")
        func itemIdentity() throws {
            let skin = try TestSupport.loadFixture(TestSupport.defaultSkinNames[0])
            #expect(RetroArchSendItem(skin: skin).id == skin.identifier)
        }
    }
}
#endif
