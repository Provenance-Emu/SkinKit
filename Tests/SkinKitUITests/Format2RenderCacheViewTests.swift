#if canImport(UIKit) && !os(tvOS)
import CoreGraphics
import Foundation
import SkinKit2Core
import SkinKit2Render
import SwiftUI
import Testing
import UIKit
@testable import SkinKitUI

/// The skin view draws through the render cache in a real SwiftUI `Canvas` (issue 162).
@Suite("Format 2.0 skin view render cache", .serialized)
@MainActor
struct Format2RenderCacheViewTests {
    static func document() throws -> Skin2Document {
        try Skin2Document.load(data: Data("""
        { "formatVersion": "2.0", "requires": ["shapes.parametric", "effects.shadow", "effects.blur", "effects.blend", "text", "states", "controls.thumbstick"],
          "identifier": "com.example.cacheview", "name": "Cache view", "gameTypes": ["com.rileytestut.delta.game.snes"],
          "reference": { "shortSide": 390, "minScale": 1, "maxScale": 1 },
          "root": { "type": "group", "children": [
            { "type": "shape", "shape": { "kind": "rect" }, "fills": [ { "type": "solid", "color": "#1C1C22" } ] },
            { "type": "shape", "shape": { "kind": "ellipse" }, "layout": { "frame": [20.5, 380, 190, 190] }, "opacity": 0.6,
              "fills": [ { "type": "solid", "color": "#9E7AF2" } ], "effects": [ { "type": "blur", "radius": 12 } ] },
            { "type": "control", "id": "stick", "kind": "thumbstick", "input": "leftThumbstick", "travel": 34, "layout": { "frame": [50, 410, 130, 130] },
              "children": [
                { "type": "shape", "role": "base", "shape": { "kind": "ellipse" }, "fills": [ { "type": "solid", "color": "#2A2A35" } ] },
                { "type": "shape", "role": "knob", "shape": { "kind": "ellipse" }, "layout": { "size": { "width": "50%", "height": "50%" } },
                  "fills": [ { "type": "solid", "color": "#8A8F99" } ],
                  "effects": [ { "type": "shadow", "color": "#000000", "opacity": 0.6, "radius": 4, "offset": [0, 3] } ] } ] },
            { "type": "control", "id": "a", "kind": "button", "input": "a", "layout": { "frame": [280, 430, 72, 72] },
              "states": { "pressed": { "scale": 0.9 }, "selected": { "opacity": 0.5 } },
              "children": [
                { "type": "shape", "shape": { "kind": "ellipse" }, "fills": [ { "type": "solid", "color": "#52DB66" } ],
                  "effects": [ { "type": "shadow", "color": "#000000", "opacity": 0.5, "radius": 4, "offset": [0, 2] } ] },
                { "type": "text", "text": "A", "font": { "size": 18, "weight": "bold" }, "color": "#1C1C22" } ] },
            { "type": "shape", "shape": { "kind": "ellipse" }, "layout": { "frame": [30, 390, 220, 110] }, "opacity": 0.5,
              "fills": [ { "type": "solid", "color": "#FFFFFF" } ], "effects": [ { "type": "blend", "mode": "overlay" } ] } ] } }
        """.utf8))
    }

    static let size = CGSize(width: 393, height: 600)

    /// A window that shows one skin view after another in the same place, as a touch changing its state does, and
    /// captures what SwiftUI drew as RGBA bytes.
    @MainActor
    final class Hosted {
        let window: UIWindow
        let host: UIHostingController<AnyView>

        init() {
            host = UIHostingController(rootView: AnyView(EmptyView()))
            window = UIWindow(frame: CGRect(origin: .zero, size: Format2RenderCacheViewTests.size))
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = window.bounds
            host.view.backgroundColor = .clear
        }

        deinit { MainActor.assumeIsolated { window.isHidden = true } }

        func render(_ view: Skin2SkinView) async throws -> [UInt8] {
            let size = Format2RenderCacheViewTests.size
            host.rootView = AnyView(view.frame(width: size.width, height: size.height).ignoresSafeArea())
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 150_000_000)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 3
            format.opaque = false
            let shot = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { ctx in
                if !host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true) { host.view.layer.render(in: ctx.cgContext) }
            }
            let image = try #require(shot.cgImage)
            var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
            bytes.withUnsafeMutableBytes { buffer in
                let ctx = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                ctx.setBlendMode(.copy)
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            return bytes
        }
    }

    static func view(held: [String: Skin2ControlState] = [:], selected: Set<String> = [], cache: Skin2RenderCache?) throws -> Skin2SkinView {
        var view = Skin2SkinView(document: try document(), screenPlaceholders: true, selected: selected, playsHaptics: false,
                                 safeAreaOverride: Skin2Insets(top: 0, left: 0, bottom: 0, right: 0))
        view.heldForTesting = held
        view.renderCacheForTesting = cache
        view.usesRenderCache = cache != nil
        return view
    }

    static let held: [[String: Skin2ControlState]] = [
        [:],
        ["stick": Skin2ControlState(pressed: true, stick: Skin2StickValue(x: 0.7, y: -0.5))],
        ["a": Skin2ControlState(pressed: true)],
        ["a": Skin2ControlState(pressed: true, scaleProgress: 0.35)],
        ["stick": Skin2ControlState(pressed: true, stick: Skin2StickValue(x: -1, y: 0)), "a": Skin2ControlState(pressed: true)],
    ]

    @Test("SwiftUI's canvas is a target the cache serves, and held controls do not repaint the tree")
    func canvasIsCached() async throws {
        let cache = Skin2RenderCache()
        let hosted = Hosted()
        for states in Self.held { _ = try await hosted.render(try Self.view(held: states, cache: cache)) }
        #expect(cache.statistics.restDraws + cache.statistics.partialDraws > 0, "the canvas never drew")
        #expect(cache.statistics.directRenders == 0, "the canvas' context was not one the cache could serve: \(cache.lastRejection ?? "")")
        #expect(cache.statistics.restRenders == 1, "the tree was painted \(cache.statistics.restRenders) times for \(Self.held.count) states")
        #expect(cache.statistics.partialDraws >= Self.held.count - 1)
    }

    /// How two captures differ: the bytes that differ and the largest step. Nil when they are the same.
    static func difference(_ a: [UInt8], _ b: [UInt8]) -> (count: Int, worst: Int)? {
        guard a.count == b.count else { return (max(a.count, b.count), 255) }
        var count = 0, worst = 0
        for i in a.indices where a[i] != b[i] { count += 1; worst = max(worst, abs(Int(a[i]) - Int(b[i]))) }
        return count == 0 ? nil : (count, worst)
    }

    /// The reference renderer's bytes for what the view shows: the skin on the view's canvas with `states`.
    static func reference(_ states: [String: Skin2ControlState], selected: Set<String> = []) throws -> [UInt8] {
        let environment = Skin2Environment(size: Skin2Size(width: size.width, height: size.height),
                                           safeArea: Skin2Insets(top: 0, left: 0, bottom: 0, right: 0),
                                           device: .iphone, displayType: .edgeToEdge, flags: [], capabilities: [])
        let resolution = Skin2Resolver.resolve(try document(), in: environment)
        var all = states
        for id in selected { all[id, default: Skin2ControlState()].selected = true }
        let image = try #require(Skin2Renderer.image(resolution, scale: 3, options: Skin2RenderOptions(states: all, screenPlaceholders: true)))
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setBlendMode(.copy)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }

    /// With the cache the canvas is handed images of the reference renderer's output, so the screen shows the
    /// reference bytes. Without it SwiftUI rasterises the drawing calls itself and a few edge pixels come out a
    /// level or two different; that difference is what the cached view may differ from the old drawing by.
    @Test("The cached view shows the reference renderer's pixels, at rest and with controls held")
    func showsReferencePixels() async throws {
        let cache = Skin2RenderCache()
        let cachedHost = Hosted(), directHost = Hosted()
        var cases: [([String: Skin2ControlState], Set<String>)] = Self.held.map { ($0, []) }
        cases.append((Self.held[1], ["a"]))
        for (states, selected) in cases {
            let direct = try await directHost.render(try Self.view(held: states, selected: selected, cache: nil))
            let cached = try await cachedHost.render(try Self.view(held: states, selected: selected, cache: cache))
            let reference = try Self.reference(states, selected: selected)
            #expect(Set(cached).count > 8, "the view drew nothing to compare")
            let exact = Self.difference(cached, reference)
            #expect(exact == nil, "cached view and reference renderer differ for \(states): \(exact.map { "\($0.count) bytes, largest step \($0.worst)" } ?? "")")
            // The old path, for the record: close to the reference, not equal to it.
            if let old = Self.difference(direct, reference) {
                #expect(old.count < cached.count / 500 && old.worst <= 8,
                        "direct drawing is further from the reference than expected: \(old.count) bytes, largest step \(old.worst)")
            }
        }
        #expect(cache.statistics.restRenders == 2, "the tree is painted once, and once more for the new selection")
        #expect(cache.statistics.directRenders == 0)
    }
}
#endif
