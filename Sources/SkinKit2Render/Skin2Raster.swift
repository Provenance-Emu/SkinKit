import Accelerate
import CoreGraphics
import Foundation
import SkinKit2Core

/// sRGB colours and gradients: the renderer never uses a device colour space, so the macOS host and iOS draw the
/// same bytes (section 5.1: "colours interpolate in sRGB").
enum Skin2Color2CG {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    static let gray = CGColorSpaceCreateDeviceGray()

    static func cg(_ c: Skin2Color, opacity: Double = 1) -> CGColor {
        CGColor(colorSpace: sRGB, components: [CGFloat(c.red), CGFloat(c.green), CGFloat(c.blue), CGFloat(c.alpha * opacity)])!
    }

    static func gradient(_ stops: [Skin2Stop], opacity: Double) -> CGGradient? {
        let sorted = stops.enumerated().sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }.map(\.element)
        var components: [CGFloat] = []
        var locations: [CGFloat] = []
        for s in sorted {
            let a = s.color.alpha * (s.opacity ?? 1) * opacity
            components += [CGFloat(s.color.red), CGFloat(s.color.green), CGFloat(s.color.blue), CGFloat(a)]
            locations.append(CGFloat(s.at))
        }
        return CGGradient(colorSpace: sRGB, colorComponents: components, locations: locations, count: sorted.count)
    }
}

/// An offscreen RGBA8 (premultiplied, sRGB) bitmap over `region` (canvas points) at `scale` pixels per point. Its
/// context's user space is canvas points, y down, the same as the context the renderer draws into.
final class Skin2Bitmap {
    let region: CGRect
    let scale: CGFloat
    let width: Int
    let height: Int
    let context: CGContext

    /// Pixels kept in a buffer: a 4096 × 4096 limit keeps a stray huge shadow from allocating gigabytes.
    static let maxSide = 4096

    init?(region: CGRect, scale: CGFloat) {
        let r = region.standardized
        guard r.width > 0, r.height > 0, scale > 0, r.width.isFinite, r.height.isFinite else { return nil }
        var s = scale
        let longest = max(r.width, r.height) * s
        if longest > CGFloat(Self.maxSide) { s *= CGFloat(Self.maxSide) / longest }
        let w = max(1, Int((r.width * s).rounded(.up))), h = max(1, Int((r.height * s).rounded(.up)))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: Skin2Color2CG.sRGB,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: s, y: -s)
        ctx.translateBy(x: -r.minX, y: -r.minY)
        Skin2Bitmap.configure(ctx)
        self.region = CGRect(x: r.minX, y: r.minY, width: CGFloat(w) / s, height: CGFloat(h) / s)
        self.scale = s
        width = w; height = h; context = ctx
    }

    static func configure(_ ctx: CGContext) {
        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldSmoothFonts(false)
        ctx.setShouldSubpixelPositionFonts(false)
        ctx.setShouldSubpixelQuantizeFonts(false)
        ctx.interpolationQuality = .high
    }

    func image() -> CGImage? { context.makeImage() }

    /// The alpha channel as a Planar8 buffer the caller owns.
    func alpha() -> Skin2Mask? {
        guard let data = context.data else { return nil }
        let rowBytes = context.bytesPerRow
        let src = data.assumingMemoryBound(to: UInt8.self)
        let mask = Skin2Mask(width: width, height: height, region: region, scale: scale)
        for y in 0..<height {
            for x in 0..<width { mask.bytes[y * width + x] = src[y * rowBytes + x * 4 + 3] }
        }
        return mask
    }

    /// Blurs the bitmap in place with a Gaussian of σ = `sigma` points.
    func blur(sigma: CGFloat) {
        guard let data = context.data else { return }
        let kernel = Skin2Mask.gaussian(sigma: sigma * scale)
        guard kernel.count > 1 else { return }
        var buffer = vImage_Buffer(data: data, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: context.bytesPerRow)
        let copy = UnsafeMutableRawPointer.allocate(byteCount: context.bytesPerRow * height, alignment: 16)
        defer { copy.deallocate() }
        copy.copyMemory(from: data, byteCount: context.bytesPerRow * height)
        var src = vImage_Buffer(data: copy, height: buffer.height, width: buffer.width, rowBytes: buffer.rowBytes)
        let background: [UInt8] = [0, 0, 0, 0]
        _ = kernel.withUnsafeBufferPointer { k in
            vImageSepConvolve_ARGB8888(&src, &buffer, nil, 0, 0, k.baseAddress!, UInt32(k.count), k.baseAddress!, UInt32(k.count),
                                       0, background, vImage_Flags(kvImageBackgroundColorFill))
        }
    }
}

/// An 8-bit coverage mask over `region` (canvas points) at `scale` pixels per point; row 0 is the top.
final class Skin2Mask {
    let width: Int
    let height: Int
    let region: CGRect
    let scale: CGFloat
    var bytes: [UInt8]

    init(width: Int, height: Int, region: CGRect, scale: CGFloat) {
        self.width = width; self.height = height; self.region = region; self.scale = scale
        bytes = [UInt8](repeating: 0, count: width * height)
    }

    /// A normalised Gaussian kernel with radius ⌈3σ⌉ pixels (one tap when σ is under a tenth of a pixel).
    static func gaussian(sigma: CGFloat) -> [Float] {
        guard sigma >= 0.1 else { return [1] }
        let radius = Int((3 * sigma).rounded(.up))
        var k = (-radius...radius).map { i -> Float in Float(exp(-Double(i * i) / (2 * Double(sigma * sigma)))) }
        let sum = k.reduce(0, +)
        k = k.map { $0 / sum }
        return k
    }

    func blur(sigma: CGFloat) {
        let kernel = Self.gaussian(sigma: sigma * scale)
        guard kernel.count > 1 else { return }
        let src = bytes
        src.withUnsafeBufferPointer { s in
            bytes.withUnsafeMutableBufferPointer { d in
                var sb = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: s.baseAddress!), height: vImagePixelCount(height),
                                       width: vImagePixelCount(width), rowBytes: width)
                var db = vImage_Buffer(data: d.baseAddress!, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width)
                _ = kernel.withUnsafeBufferPointer { k in
                    vImageSepConvolve_Planar8(&sb, &db, nil, 0, 0, k.baseAddress!, UInt32(k.count), k.baseAddress!, UInt32(k.count),
                                              0, 0, vImage_Flags(kvImageBackgroundColorFill))
                }
            }
        }
    }

    /// Grows (positive) or shrinks (negative) the covered area by `points`, with a round structuring element.
    func spread(_ points: CGFloat) {
        let r = Int((abs(points) * scale).rounded())
        guard r > 0 else { return }
        let side = 2 * r + 1
        var kernel = [UInt8](repeating: 255, count: side * side)
        for y in 0..<side {
            for x in 0..<side where (x - r) * (x - r) + (y - r) * (y - r) <= r * r { kernel[y * side + x] = 0 }
        }
        let src = bytes
        src.withUnsafeBufferPointer { s in
            bytes.withUnsafeMutableBufferPointer { d in
                var sb = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: s.baseAddress!), height: vImagePixelCount(height),
                                       width: vImagePixelCount(width), rowBytes: width)
                var db = vImage_Buffer(data: d.baseAddress!, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width)
                if points > 0 {
                    _ = vImageDilate_Planar8(&sb, &db, 0, 0, kernel, vImagePixelCount(side), vImagePixelCount(side), vImage_Flags(kvImageNoFlags))
                } else {
                    // Erode is min(src + k): the same 0-inside, 255-outside disc excludes the corners.
                    _ = vImageErode_Planar8(&sb, &db, 0, 0, kernel, vImagePixelCount(side), vImagePixelCount(side), vImage_Flags(kvImageNoFlags))
                }
            }
        }
    }

    func invert() { for i in bytes.indices { bytes[i] = 255 - bytes[i] } }

    /// A DeviceGray image of the mask for `CGContext.clip(to:mask:)`.
    func image() -> CGImage? {
        let data = Data(bytes) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width, space: Skin2Color2CG.gray,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)
    }
}

extension CGContext {
    /// Draws a top-row-first image (a `Skin2Bitmap` or a decoded file) into `rect` of a y-down user space.
    func drawTopDown(_ image: CGImage, in rect: CGRect) {
        saveGState()
        translateBy(x: 0, y: rect.minY + rect.maxY)
        scaleBy(x: 1, y: -1)
        draw(image, in: rect)
        restoreGState()
    }

    /// Clips to a top-row-first mask image placed at `rect` of a y-down user space.
    func clipTopDown(to rect: CGRect, mask: CGImage) {
        // The clip is set in the flipped space and survives the transform change.
        translateBy(x: 0, y: rect.minY + rect.maxY)
        scaleBy(x: 1, y: -1)
        clip(to: rect, mask: mask)
        scaleBy(x: 1, y: -1)
        translateBy(x: 0, y: -(rect.minY + rect.maxY))
    }

    /// Pixels per point along the current transform (the square root of its determinant).
    var pixelScale: CGFloat {
        let t = userSpaceToDeviceSpaceTransform
        let s = sqrt(abs(t.a * t.d - t.b * t.c))
        return s > 0 ? s : 1
    }
}
