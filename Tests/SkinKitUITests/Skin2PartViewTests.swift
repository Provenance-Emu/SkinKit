#if canImport(UIKit)
import CoreGraphics
import Foundation
import SkinKit2Core
import SkinKit2Render
import SwiftUI
import Testing
import UIKit
@testable import SkinKitUI

@Suite("A part drawn alone", .serialized)
@MainActor
struct Skin2PartViewTests {
    @Test("The document is one instance of the part filling the view")
    func document() throws {
        let doc = try #require(Skin2PartView.document(part: "std.vmu", with: ["source": "vmu.p2"]))
        #expect(doc.node(id: "part.lcd")?.source == "vmu.p2")
        #expect(Skin2Validator.validate(json: try #require(Skin2PartView.source(part: "std.vmu", with: [:]))).errors.map(\.description) == [])
        let r = Skin2Resolver.resolve(doc, in: Skin2Environment(size: Skin2Size(width: 240, height: 160), capabilities: ["picture.vmu.p2"]))
        #expect(r.node(id: "part")?.frame == Skin2Rect(x: 0, y: 0, width: 240, height: 160))
        #expect(r.provided.pictures == ["vmu.p2"])
        let pill = try #require(Skin2PartView.document(part: "std.pill", with: ["input": "start", "label": "START"]))
        #expect(pill.node(id: "part")?.kind == .button)
    }

    @Test("An unknown part, or arguments the part rejects, give no document")
    func partViewWithUnknownPartDrawsNothing() {
        #expect(Skin2PartView.document(part: "std.nope", with: [:]) == nil)
        #expect(Skin2PartView.document(part: "std.vmu", with: ["body": "not a colour"]) == nil)
        _ = UIHostingController(rootView: Skin2PartView(part: "std.nope")).view
    }

    @Test("std.vmu hosted alone shows the app's picture in its window")
    func partViewDrawsStdVMUAlone() async throws {
        let ctx = try #require(CGContext(data: nil, width: 48, height: 32, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 48, height: 32))
        let store = Skin2PictureStore()
        store.set(try #require(ctx.makeImage()), for: "vmu.p1")
        let size = CGSize(width: 240, height: 160)
        let controller = UIHostingController(rootView: Skin2PartView(part: "std.vmu", capabilities: ["picture.vmu.p1"], pictures: store)
            .frame(width: size.width, height: size.height))
        // The small window stands in for an embedded slot. A full-screen tvOS host
        // would apply overscan insets before proposing a size to the slot.
        controller.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        func pictures(_ view: UIView) -> [Skin2PictureUIView] { (view as? Skin2PictureUIView).map { [$0] } ?? [] + view.subviews.flatMap(pictures) }
        var found: [Skin2PictureUIView] = []
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, found.isEmpty {
            try? await Task.sleep(nanoseconds: 50_000_000)
            controller.view.layoutIfNeeded()
            found = pictures(controller.view)
        }
        let picture = try #require(found.first)
        #expect(picture.layer.contents != nil)
        // The LCD sits inside the 240 × 160 view, in the LCD's shape.
        let frame = picture.convert(picture.bounds, to: controller.view)
        #expect(controller.view.bounds.contains(frame))
        #expect(abs(frame.width / frame.height - 1.5) < 0.05 && frame.width >= 96)
        window.isHidden = true
    }
}
#endif
