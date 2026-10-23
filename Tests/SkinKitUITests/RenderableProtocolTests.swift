#if canImport(UIKit)
import Foundation
import SkinKitCore
import Testing
import UIKit
@testable import SkinKitUI

@Suite("DeltaSkinRenderable")
struct RenderableProtocolTests {

    /// A conformer that only supplies `image(for:)`, to exercise the protocol's default methods.
    private struct ImageOnlySkin: DeltaSkinRenderable {
        let identifier = "com.test.image-only"
        let name = "Image only"
        let gameType = DeltaSkinGameType.gba
        let fileURL = URL(fileURLWithPath: "/tmp/image-only.deltaskin")
        let isDebugEnabled = false
        let jsonRepresentation: [String: Any] = [:]
        let imageSize: CGSize

        func supports(_ traits: DeltaSkinTraits) -> Bool { true }
        func screens(for traits: DeltaSkinTraits) -> [DeltaSkinScreen]? { nil }
        func screenGroups(for traits: DeltaSkinTraits) -> [DeltaSkinScreenGroup]? { nil }
        func buttons(for traits: DeltaSkinTraits) -> [DeltaSkinButton]? { nil }
        func mappingSize(for traits: DeltaSkinTraits) -> CGSize? { nil }
        func representation(for traits: DeltaSkinTraits) -> DeltaSkin.RepresentationInfo? { nil }
        func image(for traits: DeltaSkinTraits) async throws -> UIImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: imageSize, format: format).image { ctx in
                UIColor.orange.setFill()
                ctx.fill(CGRect(origin: .zero, size: imageSize))
            }
        }
    }

    @Test("The default thumbnail scales a large image down to maxDimension")
    func defaultThumbnailScalesDown() async throws {
        let skin = ImageOnlySkin(imageSize: CGSize(width: 400, height: 200))
        let thumbnail = try await skin.thumbnail(for: TestSupport.portrait, maxDimension: 100)
        #expect(abs(thumbnail.size.width - 100) < 1)
        #expect(abs(thumbnail.size.height - 50) < 1)
    }

    @Test("The default thumbnail leaves a small image alone")
    func defaultThumbnailKeepsSmallImage() async throws {
        let skin = ImageOnlySkin(imageSize: CGSize(width: 40, height: 20))
        let thumbnail = try await skin.thumbnail(for: TestSupport.portrait, maxDimension: 100)
        #expect(thumbnail.size == CGSize(width: 40, height: 20))
    }

    @Test("The default thumbstick loader reads PDF and PNG art, and throws on bad data")
    func defaultThumbstickLoader() async throws {
        let scratch = try TestSupport.makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        try TestSupport.makePDFData().write(to: scratch.appendingPathComponent("s.pdf"))
        try TestSupport.makeOpaquePNG().write(to: scratch.appendingPathComponent("s.png"))
        try Data("x".utf8).write(to: scratch.appendingPathComponent("bad.pdf"))

        struct FolderSkin: DeltaSkinRenderable {
            let fileURL: URL
            var identifier: String { "com.test.folder" }
            var name: String { "Folder" }
            var gameType: DeltaSkinGameType { .gba }
            var isDebugEnabled: Bool { false }
            var jsonRepresentation: [String: Any] { [:] }
            func supports(_ traits: DeltaSkinTraits) -> Bool { true }
            func screens(for traits: DeltaSkinTraits) -> [DeltaSkinScreen]? { nil }
            func screenGroups(for traits: DeltaSkinTraits) -> [DeltaSkinScreenGroup]? { nil }
            func buttons(for traits: DeltaSkinTraits) -> [DeltaSkinButton]? { nil }
            func mappingSize(for traits: DeltaSkinTraits) -> CGSize? { nil }
            func representation(for traits: DeltaSkinTraits) -> DeltaSkin.RepresentationInfo? { nil }
            func image(for traits: DeltaSkinTraits) async throws -> UIImage { UIImage() }
        }
        let skin = FolderSkin(fileURL: scratch)
        _ = try await skin.loadThumbstickImage(named: "s.pdf")
        _ = try await skin.loadThumbstickImage(named: "s.png")
        await #expect(throws: DeltaSkinError.self) { _ = try await skin.loadThumbstickImage(named: "bad.pdf") }
        await #expect(throws: DeltaSkinError.self) { _ = try await skin.loadThumbstickImage(named: "nope.png") }
    }

    @Test("A DeltaSkin seen as DeltaSkinProtocol converts back to a renderable")
    func renderableAccessor() throws {
        let skin = try TestSupport.loadFixture("Backbone-GBA.deltaskin")
        let plain: any DeltaSkinProtocol = skin
        #expect(plain.renderable != nil)
    }

    @Test("DeltaSkin.thumbnail (not the protocol default) is what DeltaSkin uses")
    func deltaSkinOverridesTheDefault() async throws {
        TestSupport.disableDefaultSkinFallback()
        let skin = try TestSupport.loadFixture("Backbone-GBA.deltaskin")
        let existential: any DeltaSkinRenderable = skin
        let traits = try #require(TestSupport.declaredTraits(of: skin).first)
        let viaProtocol = try await existential.thumbnail(for: traits, maxDimension: 64)
        let direct = try await skin.thumbnail(for: traits, maxDimension: 64)
        #expect(viaProtocol.size == direct.size)
    }
}

#if !os(tvOS)
@Suite("DeltaSkinHaptic")
struct HapticTests {
    @Test("Style names map to impact styles, unknown names to medium")
    func feedbackStyles() {
        #expect(DeltaSkinHaptic(style: "light").feedbackStyle == .light)
        #expect(DeltaSkinHaptic(style: "HEAVY").feedbackStyle == .heavy)
        #expect(DeltaSkinHaptic(style: "soft").feedbackStyle == .soft)
        #expect(DeltaSkinHaptic(style: "rigid").feedbackStyle == .rigid)
        #expect(DeltaSkinHaptic(style: "medium").feedbackStyle == .medium)
        #expect(DeltaSkinHaptic(style: "bogus").feedbackStyle == .medium)
    }

    @Test("play() asks the injected setting and does not crash either way")
    func playRespectsTheSetting() {
        let previous = DeltaSkinInteractionSettings.current
        defer { DeltaSkinInteractionSettings.current = previous }
        nonisolated(unsafe) var asked = 0
        DeltaSkinInteractionSettings.current.isButtonVibrationEnabled = { asked += 1; return false }
        DeltaSkinHaptic(style: "selection").play()
        DeltaSkinHaptic(style: "heavy", intensity: 2).play()
        #expect(asked == 2)
        DeltaSkinInteractionSettings.current.isButtonVibrationEnabled = { true }
        DeltaSkinHaptic(style: "selection").play()
        DeltaSkinHaptic(style: "rigid", intensity: -1).play()
    }
}
#endif
#endif
