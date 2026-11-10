#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit
@testable import SkinKitUI

extension UIKitSerial {
    /// Screens on the themed backdrop must keep `.primary` text readable when the app is in light mode.
    @Suite("Backdrop colour scheme", .serialized)
    @MainActor
    struct BackdropColorSchemeTests {
        /// Brightness of `.primary` drawn under the backdrop modifier, inside a light-mode environment.
        private func primaryBrightness(scheme: ColorScheme?) throws -> CGFloat {
            let saved = SkinKitTheme.current
            defer { SkinKitTheme.current = saved }
            var theme = saved
            theme.backgroundColorScheme = scheme
            SkinKitTheme.current = theme

            let view = Rectangle()
                .fill(Color.primary)
                .frame(width: 8, height: 8)
                .skinKitBackdropColorScheme()
                .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let image = try #require(renderer.uiImage?.cgImage)

            var pixel = [UInt8](repeating: 0, count: 4)
            let context = try #require(CGContext(
                data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: -4, y: -4, width: image.width, height: image.height))
            return (CGFloat(pixel[0]) + CGFloat(pixel[1]) + CGFloat(pixel[2])) / (3 * 255)
        }

        @Test("The default backdrop is dark, so primary text is light even in light mode")
        func defaultIsDark() throws {
            #expect(SkinKitTheme().backgroundColorScheme == .dark)
            #expect(try primaryBrightness(scheme: .dark) > 0.8)
        }

        @Test("A host that clears the scheme keeps the inherited one")
        func nilInherits() throws {
            #expect(try primaryBrightness(scheme: nil) < 0.2)
        }
    }
}
#endif
