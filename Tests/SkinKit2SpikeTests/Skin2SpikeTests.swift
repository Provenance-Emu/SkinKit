// THROWAWAY tests for the format 2.0 spike (SkinKit#24).

import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import SkinKit2Spike
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

final class Skin2SpikeTests: XCTestCase {
    static let portrait = Skin2Canvas(size: CGSize(width: 393, height: 852), safeArea: .init(top: 59, bottom: 34))
    static let landscape = Skin2Canvas(size: CGSize(width: 852, height: 393), safeArea: .init(left: 59, bottom: 21, right: 59))
    static let ipadLandscape = Skin2Canvas(size: CGSize(width: 1180, height: 820), safeArea: .init(top: 24, bottom: 20))

    func testDecodesAndExpandsParts() throws {
        let doc = try Skin2Document.loadBundledGameCube()
        XCTAssertEqual(doc.formatVersion, "2.0-draft")
        let tree = Skin2Layouter.resolve(doc, canvas: Self.portrait)
        let inputs = tree.controls().compactMap { $0.node.input }.sorted()
        XCTAssertEqual(inputs, ["a", "b", "dpad", "l", "leftThumbstick", "r", "rightThumbstick", "start", "x", "y", "z"])
        // The part's text param reached the leaf.
        XCTAssertEqual(tree.first(id: "a")?.children.last?.node.text, "A")
        // Theme override swaps a token.
        let wii = try Skin2Document.loadBundledGameCube(theme: "wii")
        let wiiTree = Skin2Layouter.resolve(wii, canvas: Self.portrait)
        XCTAssertEqual(wiiTree.first(id: "a")?.children.last?.node.color, try Skin2Color(hex: "#0000008C"))
    }

    func testMicrophoneIsFlagGated() throws {
        let doc = try Skin2Document.loadBundledGameCube()
        XCTAssertNil(Skin2Layouter.resolve(doc, canvas: Self.portrait).first(id: "mic"))
        var withMic = Self.portrait
        withMic.flags = ["microphone"]
        XCTAssertNotNil(Skin2Layouter.resolve(doc, canvas: withMic).first(id: "mic"))
    }

    func testOneSkinLaysOutBothOrientationsWithoutOverlap() throws {
        let doc = try Skin2Document.loadBundledGameCube()
        for canvas in [Self.portrait, Self.landscape, Self.ipadLandscape] {
            let tree = Skin2Layouter.resolve(doc, canvas: canvas)
            let controls = tree.controls()
            let bounds = CGRect(origin: .zero, size: canvas.size)
            for c in controls {
                XCTAssertTrue(bounds.contains(c.frame), "\(c.node.id ?? "?") off canvas in \(canvas.orientation): \(c.frame)")
                XCTAssertGreaterThanOrEqual(min(c.frame.width, c.frame.height), 44, "\(c.node.id ?? "?") under 44pt")
            }
            for (i, a) in controls.enumerated() {
                for b in controls[(i + 1)...] where a.hitFrame.intersects(b.hitFrame) {
                    XCTFail("\(a.node.id ?? "?") overlaps \(b.node.id ?? "?") in \(canvas.orientation)")
                }
            }
            let screen = tree.first(id: "screen")!
            if canvas.orientation == "portrait" {
                XCTAssertEqual(screen.frame.width / screen.frame.height, 4.0 / 3.0, accuracy: 0.01)
                XCTAssertEqual(screen.frame.minY, canvas.safeRect.minY)
                // Controls start below the picture (iCube's regionTop rule) on an iPhone.
                let top = controls.map(\.frame.minY).min()!
                XCTAssertGreaterThan(top, screen.frame.maxY, "controls overlap the picture in portrait")
            } else {
                XCTAssertEqual(screen.frame, bounds)
            }
        }
    }

    func testLandscapeDiagonalMatchesICube() throws {
        let doc = try Skin2Document.loadBundledGameCube()
        let tree = Skin2Layouter.resolve(doc, canvas: Self.landscape)
        let dpad = tree.first(id: "dpad")!.frame, stick = tree.first(id: "mainStick")!.frame
        let unit = 393.0 / 390.0 // iCube: min(max(shortSide / 390, 1), 1.35)
        XCTAssertEqual(dpad.midX - stick.midX, 70 * unit, accuracy: 0.01)
        XCTAssertEqual(dpad.minY, stick.maxY + 8 * unit, accuracy: 0.01)
        // iCube: bottom = h - max(safeBottom, 8) - 6; stick column leading = max(safeLeft, 8) + 8.
        XCTAssertEqual(dpad.maxY, 393 - 21 - 6, accuracy: 0.5)
        XCTAssertEqual(stick.minX, 59 + 8, accuracy: 0.5)
    }

    func testRendersReferencePNGs() throws {
        let doc = try Skin2Document.loadBundledGameCube()
        let outDir = ProcessInfo.processInfo.environment["SKIN2_PNG_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("skin2-spike")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        for (name, canvas) in [("portrait", Self.portrait), ("landscape", Self.landscape)] {
            let tree = Skin2Layouter.resolve(doc, canvas: canvas)
            let image = try XCTUnwrap(Self.render(tree, size: canvas.size, scale: 1))
            let url = outDir.appendingPathComponent("gamecube-\(name).png")
            try Self.writePNG(image, to: url)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            // Sanity: the A button's centre pixel is green-ish.
            let a = tree.first(id: "a")!.frame
            let px = Self.pixel(image, at: CGPoint(x: a.midX, y: a.midY))
            XCTAssertGreaterThan(px.g, px.r, "A button should be green at its centre: \(px)")
            print("spike png: \(url.path)")
        }
    }

    static func render(_ tree: Skin2ResolvedNode, size: CGSize, scale: CGFloat) -> CGImage? {
        let w = Int(size.width * scale), h = Int(size.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Core Graphics bitmaps are bottom-left; flip to the skin's top-left space.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.setFillColor(CGColor(red: 0.16, green: 0.14, blue: 0.22, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        var options = Skin2RenderOptions()
        options.showHitFrames = true
        Skin2Renderer.draw(tree, in: ctx, options: options)
        return ctx.makeImage()
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw NSError(domain: "spike", code: 1)
        }
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }

    static func pixel(_ image: CGImage, at p: CGPoint) -> (r: Int, g: Int, b: Int) {
        guard let data = image.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return (0, 0, 0) }
        let i = Int(p.y) * image.bytesPerRow + Int(p.x) * 4
        return (Int(ptr[i]), Int(ptr[i + 1]), Int(ptr[i + 2]))
    }
}
