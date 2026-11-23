#if canImport(UIKit)
import CoreGraphics
import Foundation
import SkinKit2Core
import SkinKit2Render
import SwiftUI
import Testing
import UIKit
@testable import SkinKitUI

@Suite("Format 2.0 panels in the skin view", .serialized)
@MainActor
struct Format2PanelViewTests {
    static func document(open: Bool = true, accessory: Bool = true) throws -> Skin2Document {
        let lcd = accessory ? #"{ "type": "screen", "id": "lcd", "source": "vmu.p1", "layout": { "frame": [56, 8, 96, 64] } },"# : ""
        return try Skin2Document.load(data: Data("""
        { "formatVersion": "2.0", "requires": ["shapes.parametric"], "optional": ["capabilities", "screens.accessory", "panels"],
          "identifier": "com.example.panelview", "name": "Panel view", "gameTypes": ["com.rileytestut.delta.game.dc"],
          "reference": { "shortSide": 390, "minScale": 1, "maxScale": 1 },
          "root": { "type": "group", "children": [
            { "type": "group", "id": "vmuPanel", "layout": { "frame": [100, 200, 160, 120] },
              "panel": { "name": "vmu", "label": "Visual Memory", "needs": ["picture.vmu.p1"], "presentation": "shelf", "handle": "#tab", "open": \(open) },
              "children": [
                { "type": "shape", "shape": { "kind": "rect" }, "fills": [ { "type": "solid", "color": "#E8E8EC" } ] },
                \(lcd)
                { "type": "control", "id": "tab", "kind": "action", "input": "togglePanel", "layout": { "frame": [0, 0, 48, 48] } } ] },
            { "type": "control", "id": "a", "kind": "button", "input": "a", "layout": { "frame": [100, 500, 60, 60] } } ] } }
        """.utf8))
    }

    static func scratch() -> UserDefaults { UserDefaults(suiteName: "skinkit.tests.\(UUID().uuidString)")! }

    static func image() -> CGImage {
        let ctx = CGContext(data: nil, width: 48, height: 32, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 48, height: 32))
        return ctx.makeImage()!
    }

    // MARK: Shelf state

    @Test("A shelf starts as the document says")
    func panelStateStartsFromTheDocument() throws {
        #expect(Skin2PanelState(document: try Self.document(open: true), skinIdentifier: "s", defaults: Self.scratch()).flags == ["panel.vmu.open"])
        #expect(Skin2PanelState(document: try Self.document(open: false), skinIdentifier: "s", defaults: Self.scratch()).flags == [])
    }

    @Test("A toggled shelf is remembered per skin")
    func panelStateRemembersPerSkin() throws {
        let defaults = Self.scratch()
        let doc = try Self.document(open: true)
        let state = Skin2PanelState(document: doc, skinIdentifier: "com.example.one", defaults: defaults)
        state.toggle("vmu")
        #expect(state.flags == [])
        #expect(defaults.object(forKey: "SkinKit.format2.panelOpen.com.example.one.vmu") as? Bool == false)
        #expect(Skin2PanelState(document: doc, skinIdentifier: "com.example.one", defaults: defaults).flags == [])
        #expect(Skin2PanelState(document: doc, skinIdentifier: "com.example.two", defaults: defaults).flags == ["panel.vmu.open"])
        state.toggle("vmu")
        #expect(state.flags == ["panel.vmu.open"])
        state.toggle("nope")
        #expect(state.flags == ["panel.vmu.open"])
    }

    @Test("Without a skin identifier nothing is stored")
    func nilIdentifierStoresNothing() throws {
        let defaults = Self.scratch()
        let state = Skin2PanelState(document: try Self.document(open: false), skinIdentifier: nil, defaults: defaults)
        state.toggle("vmu")
        #expect(state.flags == ["panel.vmu.open"])
        #expect(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("SkinKit.format2") }.isEmpty)
    }

    // MARK: Hosted view

    final class Log { var provided: [Skin2Provided] = [] }

    private func host<V: View>(_ view: V) -> UIWindow {
        let size = CGSize(width: 390, height: 844)
        let controller = UIHostingController(rootView: view.frame(width: size.width, height: size.height))
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        return window
    }

    private func wait(_ timeout: TimeInterval = 10, until done: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if done() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return done()
    }

    private func pictureViews(in view: UIView) -> [Skin2PictureUIView] {
        (view as? Skin2PictureUIView).map { [$0] } ?? [] + view.subviews.flatMap(pictureViews)
    }

    @Test("The skin claims a picture only while the app delivers one")
    func providedDropsPictureWhenStoreClears() async throws {
        let store = Skin2PictureStore()
        let log = Log()
        let window = host(Skin2SkinView(document: try Self.document(), capabilities: ["picture.vmu.p1"], pictures: store,
                                        onProvidedChange: { log.provided.append($0) }))
        #expect(await wait { !log.provided.isEmpty })
        #expect(log.provided.last == Skin2Provided(pictures: [], inputs: [], panels: ["vmu": true]))
        store.set(Self.image(), for: "vmu.p1")
        #expect(await wait { log.provided.last?.pictures == ["vmu.p1"] })
        store.set(nil, for: "vmu.p1")
        #expect(await wait { log.provided.last?.pictures == [] && log.provided.count >= 3 })
        window.isHidden = true
    }

    @Test("Without the capability the skin claims nothing")
    func providedNeedsTheCapability() async throws {
        let store = Skin2PictureStore()
        store.set(Self.image(), for: "vmu.p1")
        let log = Log()
        let window = host(Skin2SkinView(document: try Self.document(), pictures: store, onProvidedChange: { log.provided.append($0) }))
        #expect(await wait { !log.provided.isEmpty })
        #expect(log.provided.last == Skin2Provided.none)
        window.isHidden = true
    }

    @Test("A skin view that goes away gives everything back")
    func providedIsNoneOnDisappear() async throws {
        let store = Skin2PictureStore()
        store.set(Self.image(), for: "vmu.p1")
        let log = Log()
        let window = host(Skin2SkinView(document: try Self.document(), capabilities: ["picture.vmu.p1"], pictures: store,
                                        onProvidedChange: { log.provided.append($0) }))
        #expect(await wait { log.provided.last?.pictures == ["vmu.p1"] })
        (window.rootViewController as? UIHostingController<AnyView>)?.rootView = AnyView(EmptyView())
        window.rootViewController = UIHostingController(rootView: EmptyView())
        #expect(await wait { log.provided.last == Skin2Provided.none })
        window.isHidden = true
    }

    @Test("Picture layers exist only for accessory screens the app can fill")
    func noAccessoryScreenMeansOneCanvas() async throws {
        let store = Skin2PictureStore()
        store.set(Self.image(), for: "vmu.p1")
        let plain = host(Skin2SkinView(document: try Self.document(accessory: false), capabilities: ["picture.vmu.p1"], pictures: store))
        _ = await wait(0.5) { false }
        #expect(pictureViews(in: plain.rootViewController!.view).isEmpty)
        plain.isHidden = true

        let without = host(Skin2SkinView(document: try Self.document(), pictures: store))
        _ = await wait(0.5) { false }
        #expect(pictureViews(in: without.rootViewController!.view).isEmpty)
        without.isHidden = true

        let with = host(Skin2SkinView(document: try Self.document(), capabilities: ["picture.vmu.p1"], pictures: store))
        var found: [Skin2PictureUIView] = []
        #expect(await wait { found = pictureViews(in: with.rootViewController!.view); return found.count == 1 })
        let layer = try #require(found.first?.layer)
        #expect(layer.contents != nil && layer.magnificationFilter == .nearest)
        #expect(abs(layer.bounds.width - 96) < 0.5 && abs(layer.bounds.height - 64) < 0.5)
        store.set(nil, for: "vmu.p1")
        #expect(await wait { found.first?.layer.contents == nil })
        with.isHidden = true
    }
}
#endif
