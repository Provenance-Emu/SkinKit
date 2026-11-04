import CoreGraphics
import Foundation
import Testing
@testable import SkinKitCore

/// `Sample-NES` is the skins repo's generated-art `sample-nes.deltaskin` (fixtures/variants), unzipped.
/// iCube's store tests install the same archive, so this checks SkinKit decodes it the way the apps will.
@Suite("Sample NES fixture")
struct SampleNESFixtureTests {

    private static func skin() throws -> DeltaSkin {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/Sample-NES", withExtension: "deltaskin"))
        return try DeltaSkin(fileURL: url)
    }

    private static let layouts: [(DeltaSkinDevice, DeltaSkinDisplayType, DeltaSkinOrientation)] = [
        (.iphone, .edgeToEdge, .portrait), (.iphone, .edgeToEdge, .landscape),
        (.iphone, .standard, .portrait), (.iphone, .standard, .landscape),
        (.ipad, .standard, .portrait), (.ipad, .standard, .landscape),
    ]

    @Test("Decodes strictly as an NES skin with no variants")
    func decodes() throws {
        let skin = try Self.skin()
        #expect(skin.gameType == .nes)
        #expect(skin.identifier == "com.provenance-emu.sample.nes")
        #expect(skin.name == "Sample NES")
        #expect(!skin.hasAltRepresentations)
        #expect(skin.info.altRepresentations == nil)
    }

    @Test("Every iPhone and iPad layout has the NES buttons, a 256×240 screen and its artwork")
    func layouts() throws {
        let skin = try Self.skin()
        for (device, displayType, orientation) in Self.layouts {
            let traits = DeltaSkinTraits(device: device, displayType: displayType, orientation: orientation)
            let rep = try #require(skin.representation(for: traits), "\(device) \(displayType) \(orientation)")
            var inputs = Set<String>()
            for item in rep.items ?? [] {
                switch item.inputs {
                case .single(let names): inputs.formUnion(names)
                case .directional(let map): inputs.formUnion(map.values)
                }
            }
            #expect(inputs == ["a", "b", "select", "start", "menu", "up", "down", "left", "right"])
            #expect(rep.screens?.first?.inputFrame == CGRect(x: 0, y: 0, width: 256, height: 240))
            let art = try #require(rep.assets.filename(for: .medium))
            #expect(FileManager.default.fileExists(atPath: skin.fileURL.appendingPathComponent(art).path))
        }
    }

    @Test("Passes the validator with no errors")
    func validates() throws {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/Sample-NES", withExtension: "deltaskin"))
        let result = DeltaSkinValidator.validate(url: url)
        #expect(result.errors.isEmpty, "\(result.errors.map(\.title))")
    }
}
