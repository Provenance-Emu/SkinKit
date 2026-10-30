#if canImport(UIKit)
import Combine
import Foundation
import SkinKitCore
import SwiftUI
import Testing
import UIKit
@testable import SkinKitUI

extension UIKitSerial {
    @Suite("Trait resource lifecycle", .serialized)
    @MainActor
    struct TraitReloadTests {
        private static let size = CGSize(width: 414, height: 896)
        private static let edge = DeltaSkinTraits(device: .iphone, displayType: .edgeToEdge, orientation: .portrait)

        private func makeSkin() throws -> (DeltaSkin, URL) {
            let scratch = try TestSupport.makeScratch("TraitReload")
            func layout(_ prefix: String, command: String, buttonX: Int, stickX: Int) -> [String: Any] {
                [
                    "assets": ["resizable": "\(prefix).png"],
                    "mappingSize": ["width": 414, "height": 896],
                    "screens": [["inputFrame": ["x": 0, "y": 0, "width": 240, "height": 160],
                                 "outputFrame": ["x": 20, "y": 20, "width": 374, "height": 280]]],
                    "items": [
                        ["inputs": [command], "frame": ["x": buttonX, "y": 600, "width": 60, "height": 60],
                         "asset": ["normal": "\(prefix)-button.png"]],
                        ["inputs": ["up": "leftThumbstickUp", "down": "leftThumbstickDown",
                                    "left": "leftThumbstickLeft", "right": "leftThumbstickRight"],
                         "frame": ["x": stickX, "y": 750, "width": 60, "height": 60],
                         "thumbstick": ["name": "\(prefix)-stick.png", "width": 32, "height": 32]],
                    ],
                ]
            }
            let info: [String: Any] = [
                "name": "Trait reload", "identifier": "test.trait-reload.\(UUID())",
                "gameTypeIdentifier": "com.rileytestut.delta.game.gba",
                "representations": ["iphone": [
                    "standard": ["portrait": layout("standard", command: "a", buttonX: 20, stickX: 20)],
                    "edgeToEdge": ["portrait": layout("edge", command: "b", buttonX: 260, stickX: 300)],
                ]],
            ]
            let colors: [String: UIColor] = ["standard": .red, "edge": .blue,
                "standard-button": .yellow, "edge-button": .cyan,
                "standard-stick": .magenta, "edge-stick": .green]
            let files = Dictionary(uniqueKeysWithValues: colors.map { ("\($0.key).png", TestSupport.makeOpaquePNG(color: $0.value)) })
            return (try DeltaSkin(fileURL: TestSupport.writeSkin(info: info, files: files, in: scratch)), scratch)
        }

        private func prepare() {
            TestSupport.disableDefaultSkinFallback()
            DeltaSkinInteractionSettings.current = DeltaSkinInteractionSettings()
        }

        @Test("A mounted view replaces background, control art and caps when display traits change")
        func changesRepresentation() async throws {
            let oldSettings = DeltaSkinInteractionSettings.current
            defer { DeltaSkinInteractionSettings.current = oldSettings }
            prepare()
            let (skin, scratch) = try makeSkin()
            defer { try? FileManager.default.removeItem(at: scratch) }
            let host = Host(skin: skin)
            defer { host.close() }
            try #require(await host.wait { $0.red > 0.5 && $0.yellow > 0.002 && $0.magenta > 0.002 })
            host.model.traits = Self.edge
            try #require(await host.wait { $0.blue > 0.5 && $0.cyan > 0.002 && $0.green > 0.002 })
            let pixels = host.pixels()
            #expect(pixels.yellow == 0)
            #expect(pixels.magenta == 0)
            for _ in 0..<2 {
                host.model.traits = TestSupport.portrait
                try #require(await host.wait { $0.red > 0.5 && $0.magenta > 0.002 })
                host.model.traits = Self.edge
                try #require(await host.wait { $0.blue > 0.5 && $0.green > 0.002 && $0.magenta == 0 })
            }
        }

        @Test("Late old-trait loads cannot overwrite the current representation", arguments: ["background", "button", "stick"])
        func dropsLateResults(stage: String) async throws {
            let oldSettings = DeltaSkinInteractionSettings.current
            defer { DeltaSkinInteractionSettings.current = oldSettings }
            prepare()
            let (base, scratch) = try makeSkin()
            defer { try? FileManager.default.removeItem(at: scratch) }
            let gate = LoadGate()
            defer { gate.release() }
            let skin = DelayedSkin(base: base, stage: stage, gate: gate)
            let host = Host(skin: skin)
            defer { host.close() }
            try #require(await Host.waitUntil { gate.pending })
            host.model.traits = Self.edge
            try #require(await host.wait { $0.blue > 0.5 && $0.cyan > 0.002 && $0.green > 0.002 })
            gate.release()
            try #require(await Host.waitUntil { gate.finished })
            // Allow the resumed old load to publish, then inspect several rendered frames.
            for _ in 0..<3 {
                try await Task.sleep(nanoseconds: 30_000_000)
                let pixels = host.pixels()
                #expect(pixels.blue > 0.5)
                #expect(pixels.yellow == 0)
                #expect(pixels.magenta == 0)
            }
        }

        @Test("A failed artwork load can recover when another representation is selected")
        func recoversFromMissingArtwork() async throws {
            let oldSettings = DeltaSkinInteractionSettings.current
            defer { DeltaSkinInteractionSettings.current = oldSettings }
            prepare()
            let (skin, scratch) = try makeSkin()
            defer { try? FileManager.default.removeItem(at: scratch) }
            try Data("invalid artwork".utf8).write(to: skin.fileURL.appendingPathComponent("standard.png"))
            let gate = LoadGate()
            let model = Model()
            let host = Host(skin: DelayedSkin(base: skin, stage: "failed", gate: gate), model: model)
            defer { host.close() }
            try #require(await Host.waitUntil { gate.finished })
            model.traits = Self.edge
            #expect(await host.wait { $0.blue > 0.5 })
        }

        #if !os(tvOS)
        @Test("Changing layout releases held inputs and ignores old fingers until a new touch begins")
        func releasesHeldInputs() async throws {
            let oldSettings = DeltaSkinInteractionSettings.current
            defer { DeltaSkinInteractionSettings.current = oldSettings }
            prepare()
            let (skin, scratch) = try makeSkin()
            defer { try? FileManager.default.removeItem(at: scratch) }
            let handler = Handler()
            let host = Host(skin: skin, handler: handler)
            defer { host.close() }
            try #require(await host.wait { $0.red > 0.5 && $0.magenta > 0.002 })
            let touchView = try #require(Host.find(MultiTouchView.TouchDetectingView.self, in: host.controller.view))
            let finger = UITouch()
            touchView.touchHandler?(.began, [TouchPoint(touch: finger, location: CGPoint(x: 50, y: 630))])
            #expect(handler.preview.pressedButtons == ["a"])
            handler.analogStickMoved("leftAnalog", x: 0.75, y: -0.5)
            let holder = UITouch()
            touchView.touchHandler?(.began, [TouchPoint(touch: holder, location: CGPoint(x: 200, y: 150))])
            try #require(await Host.waitUntil { handler.holdBegins == 1 })
            host.model.traits = Self.edge
            try #require(await host.wait { $0.blue > 0.5 })
            #expect(handler.preview.pressedButtons.isEmpty)
            #expect(handler.preview.stickPositions["leftAnalog"] == .zero)
            #expect(handler.holdEnds == 1)
            touchView.touchHandler?(.moved, [TouchPoint(touch: finger, location: CGPoint(x: 290, y: 630))])
            #expect(handler.preview.pressedButtons.isEmpty)
            touchView.touchHandler?(.ended, [TouchPoint(touch: finger, location: CGPoint(x: 290, y: 630))])
            let newFinger = UITouch()
            touchView.touchHandler?(.began, [TouchPoint(touch: newFinger, location: CGPoint(x: 290, y: 630))])
            #expect(handler.preview.pressedButtons == ["b"])
            host.model.visible = false
            try #require(await Host.waitUntil { handler.preview.pressedButtons.isEmpty })
        }
        #endif

        @MainActor
        private final class Model: ObservableObject {
            @Published var traits = TestSupport.portrait
            @Published var visible = true
        }

        private struct Harness: View {
            @ObservedObject var model: Model
            let skin: any DeltaSkinRenderable
            let handler: any DeltaSkinInputHandling
            var body: some View {
                Group {
                    if model.visible {
                        DeltaSkinView(skin: skin, traits: model.traits, isInEmulator: true,
                                      inputHandler: handler, allowsEmptyAreaHold: true)
                    } else { Color.black }
                }.frame(width: size.width, height: size.height).background(Color.black).ignoresSafeArea()
            }
        }

        private final class Handler: DeltaSkinInputHandling, DeltaSkinHoldHandling {
            let preview = DeltaSkinPreviewInputHandler()
            var turboManager: TurboManager { preview.turboManager }
            var stickyManager: StickyButtonManager { preview.stickyManager }
            var dsScreensSwapped: Bool { false }
            var holdHandler: (any DeltaSkinHoldHandling)? { self }
            var holdDelay: TimeInterval { 0.03 }
            var holdBegins = 0
            var holdEnds = 0
            func holdDidBegin() { holdBegins += 1 }
            func holdDidEnd() { holdEnds += 1 }
            func buttonPressed(_ id: String) { preview.buttonPressed(id) }
            func buttonReleased(_ id: String) { preview.buttonReleased(id) }
            func analogStickMoved(_ id: String, x: Float, y: Float) { preview.analogStickMoved(id, x: x, y: y) }
            func ndsBottomScreenTouched(at point: CGPoint) { preview.ndsBottomScreenTouched(at: point) }
            func ndsBottomScreenTouchReleased() { preview.ndsBottomScreenTouchReleased() }
        }

        @MainActor
        private final class Host {
            let model: Model
            let window: UIWindow
            let controller: UIHostingController<Harness>
            init(skin: any DeltaSkinRenderable, model: Model? = nil, handler: any DeltaSkinInputHandling = Handler()) {
                let model = model ?? Model()
                self.model = model
                controller = UIHostingController(rootView: Harness(model: model, skin: skin, handler: handler))
                window = UIWindow(frame: CGRect(origin: .zero, size: size))
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.view.frame = window.bounds
                controller.view.layoutIfNeeded()
            }
            func close() {
                model.visible = false
                window.isHidden = true
                window.rootViewController = nil
            }
            static func find<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
                if let found = view as? T { return found }
                return view.subviews.lazy.compactMap { find(type, in: $0) }.first
            }
            static func waitUntil(_ ready: () -> Bool) async -> Bool {
                let deadline = Date().addingTimeInterval(3)
                while Date() < deadline {
                    if ready() { return true }
                    try? await Task.sleep(nanoseconds: 20_000_000)
                }
                return ready()
            }
            func wait(_ ready: (Pixels) -> Bool) async -> Bool {
                await Self.waitUntil { ready(pixels()) }
            }
            func pixels() -> Pixels {
                controller.view.layoutIfNeeded()
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
                let hierarchy = renderer.image { _ in controller.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                let values = Pixels(hierarchy)
                if values.red + values.blue > 0.1 { return values }
                return Pixels(renderer.image { controller.view.layer.render(in: $0.cgContext) })
            }
        }

        private struct Pixels {
            var red = 0.0, blue = 0.0, yellow = 0.0, cyan = 0.0, magenta = 0.0, green = 0.0
            init(_ image: UIImage) {
                guard let cg = image.cgImage else { return }
                let width = 48, height = 96
                var bytes = [UInt8](repeating: 0, count: width * height * 4)
                let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
                guard let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info.rawValue) else { return }
                context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
                let unit = 1.0 / Double(width * height)
                for offset in stride(from: 0, to: bytes.count, by: 4) {
                    let r = bytes[offset] > 180, g = bytes[offset + 1] > 180, b = bytes[offset + 2] > 180
                    if r && !g && !b { red += unit }
                    if b && !r && !g { blue += unit }
                    if r && g && !b { yellow += unit }
                    if g && b && !r { cyan += unit }
                    if r && b && !g { magenta += unit }
                    if g && !r && !b { green += unit }
                }
            }
        }

        /// Non-cooperative completion reproduces a decoder that finishes after its task is cancelled.
        private final class LoadGate: @unchecked Sendable {
            private let lock = NSLock()
            private var continuations: [CheckedContinuation<Void, Never>] = []
            private var released = false
            private var didFinish = false
            var pending: Bool { lock.withLock { !continuations.isEmpty } }
            var finished: Bool { lock.withLock { didFinish } }
            func wait() async {
                await withCheckedContinuation { continuation in
                    let resume = lock.withLock {
                        if released { return true }
                        continuations.append(continuation)
                        return false
                    }
                    if resume { continuation.resume() }
                }
            }
            func markFinished() { lock.withLock { didFinish = true } }
            func release() {
                let pending = lock.withLock {
                    released = true
                    let pending = continuations
                    continuations.removeAll()
                    return pending
                }
                for continuation in pending { continuation.resume() }
            }
        }

        private struct DelayedSkin: DeltaSkinRenderable {
            let base: DeltaSkin
            let stage: String
            let gate: LoadGate
            var identifier: String { base.identifier }
            var name: String { base.name }
            var gameType: DeltaSkinGameType { base.gameType }
            var fileURL: URL { base.fileURL }
            var isDebugEnabled: Bool { base.isDebugEnabled }
            var jsonRepresentation: [String: Any] { base.jsonRepresentation }
            func supports(_ traits: DeltaSkinTraits) -> Bool { base.supports(traits) }
            func screens(for traits: DeltaSkinTraits) -> [DeltaSkinScreen]? { base.screens(for: traits) }
            func screenGroups(for traits: DeltaSkinTraits) -> [DeltaSkinScreenGroup]? { base.screenGroups(for: traits) }
            func buttons(for traits: DeltaSkinTraits) -> [DeltaSkinButton]? { base.buttons(for: traits) }
            func mappingSize(for traits: DeltaSkinTraits) -> CGSize? { base.mappingSize(for: traits) }
            func representation(for traits: DeltaSkinTraits) -> DeltaSkin.RepresentationInfo? { base.representation(for: traits) }
            func image(for traits: DeltaSkinTraits) async throws -> UIImage {
                let delayed = stage == "background" && traits.displayType == .standard
                let tracked = traits.displayType == .standard && (stage == "background" || stage == "failed")
                if delayed { await gate.wait() }
                defer { if tracked { gate.markFinished() } }
                return try await base.image(for: traits)
            }
            func loadThumbstickImage(named: String) async throws -> UIImage {
                let delayed = named == "standard-\(stage).png"
                if delayed { await gate.wait() }
                defer { if delayed { gate.markFinished() } }
                return try await base.loadThumbstickImage(named: named)
            }
        }
    }
}
#endif
