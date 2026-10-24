#if canImport(UIKit)
import UIKit

extension UIImage {
    /// Render a PDF data blob into a UIImage.
    ///
    /// - Parameters:
    ///   - pdfData: Raw PDF file data.
    ///   - preserveTransparency: When `true` the canvas is pre-filled with a transparent background.
    ///     When `false` the canvas is pre-filled with an opaque black background.
    ///   - size: Optional target logical size (points).  When provided the canvas is exactly that size;
    ///     PDF content is aspect-fitted within the canvas (preserving its aspect ratio) and centred.
    ///     When `nil` the native PDF page size is used, capped at 4096 physical pixels to stay within
    ///     safe GPU texture limits.
    convenience init?(pdfData: Data, preserveTransparency: Bool = true, size: CGSize? = nil) {
        guard let provider = CGDataProvider(data: pdfData as CFData),
              let pdf = CGPDFDocument(provider),
              let page = pdf.page(at: 1) else {
            return nil
        }

        let pageRect = page.getBoxRect(.mediaBox)

        let finalSize: CGSize
        let scale: CGFloat

        if let requestedSize = size, requestedSize.width > 0, requestedSize.height > 0 {
            // Caller supplied an explicit target size – render at that size, capped for safety.
            let maxDimension: CGFloat = 4096
            let capScale = min(
                maxDimension / requestedSize.width,
                maxDimension / requestedSize.height,
                1.0
            )
            let cappedSize = CGSize(
                width: requestedSize.width * capScale,
                height: requestedSize.height * capScale
            )
            finalSize = cappedSize
            scale = min(cappedSize.width / pageRect.width,
                        cappedSize.height / pageRect.height)
        } else {
            // No explicit size – use native PDF dimensions, capped at 4096 physical pixels.
            // The cap must be in points (not pixels) since UIGraphicsImageRenderer works in points
            // and will apply the renderer scale when rasterizing.
            let rendererScale = UIScreen.main.scale
            let maxPoints: CGFloat = 4096 / rendererScale
            let capScale = min(
                maxPoints / pageRect.width,
                maxPoints / pageRect.height,
                1.0 // Don't scale up, only down
            )
            scale = capScale
            finalSize = CGSize(
                width: pageRect.width * scale,
                height: pageRect.height * scale
            )
        }

        let renderer = UIGraphicsImageRenderer(
            size: finalSize,
            format: {
                let format = UIGraphicsImageRendererFormat()
                format.scale = UIScreen.main.scale
                format.opaque = !preserveTransparency // Opaque when not preserving transparency
                return format
            }()
        )

        let image = renderer.image { context in
            // Fill background based on preserveTransparency flag
            if preserveTransparency {
                UIColor.clear.setFill()
            } else {
                UIColor.black.setFill()
            }
            context.fill(CGRect(origin: .zero, size: finalSize))

            // Draw PDF with aspect-fit scaling, centred within the canvas.
            // When a requested size is given and its aspect ratio differs from the PDF,
            // centre the scaled PDF so transparent (or opaque) padding is evenly distributed.
            let scaledWidth = pageRect.width * scale
            let scaledHeight = pageRect.height * scale
            let xOffset = (finalSize.width - scaledWidth) / 2
            let yOffset = (finalSize.height - scaledHeight) / 2
            context.cgContext.translateBy(x: xOffset, y: yOffset + scaledHeight)
            context.cgContext.scaleBy(x: scale, y: -scale)
            // Media boxes are not always origin-zero. Without this, the page draws off-canvas
            // and the cached PNG is a blank transparent image.
            context.cgContext.translateBy(x: -pageRect.origin.x, y: -pageRect.origin.y)
            context.cgContext.drawPDFPage(page)
        }

        self.init(cgImage: image.cgImage!, scale: image.scale, orientation: image.imageOrientation)
    }

    /// True when the bitmap is opaque or a coarse downsample finds any non-zero channel.
    ///
    /// Alpha-only checks dropped thin controller art after it was averaged into a 24×24 sample,
    /// and the picker then treated a successful render as a blank placeholder.
    var hasVisibleContent: Bool {
        guard let cgImage, cgImage.width > 0, cgImage.height > 0 else { return false }
        switch cgImage.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return true
        default:
            break
        }
        let sample = 48
        let bytesPerPixel = 4
        var pixels = [UInt8](repeating: 0, count: sample * sample * bytesPerPixel)
        guard let context = CGContext(
            data: &pixels,
            width: sample,
            height: sample,
            bitsPerComponent: 8,
            bytesPerRow: sample * bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return true
        }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sample, height: sample))
        return pixels.contains { $0 > 0 }
    }

    /// Returns an image with an alpha channel (the image itself when it already has one).
    func imageWithAlpha() -> UIImage {
        // If image already has alpha, return as is
        if hasAlpha {
            return self
        }

        // Create new image with alpha channel
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            draw(at: .zero)
        }
    }

    var hasAlpha: Bool {
        guard let cgImage = cgImage else { return false }
        let alpha = cgImage.alphaInfo
        return alpha == .first || alpha == .last || alpha == .premultipliedFirst || alpha == .premultipliedLast
    }
}
#endif
