import Foundation
import Testing
import SkinKitCore

/// Loads every skin Provenance bundles as a default (`PVUIBase/Resources/DefaultSkins`) through the
/// public API and resolves each representation it declares. These are the real shipped skins, so
/// this is the widest "nothing changed in the move" check in the suite.
@Suite("Bundled default skins")
struct DefaultSkinsTests {

    static let skinNames: [String] = {
        guard let dir = Bundle.module.url(forResource: "Fixtures", withExtension: nil),
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.filter { $0.hasSuffix(".deltaskin") && !$0.hasSuffix("-Test.deltaskin") }.sorted()
    }()

    @Test("The default skins are present in the fixtures")
    func fixturesPresent() {
        #expect(Self.skinNames.count == 23)
    }

    @Test("Each default skin loads and resolves every representation it declares", arguments: skinNames)
    func loadsAndResolves(name: String) throws {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil))
        let skin = try DeltaSkin(fileURL: url)
        #expect(!skin.identifier.isEmpty)
        #expect(skin.identifier.hasPrefix("com.provenance.defaultskins."))

        var resolved = 0
        for (device, reps) in skin.info.representations {
            let byDisplayType: [(DeltaSkinDisplayType, [String: DeltaSkin.OrientationRepresentations]?)] = [
                (.standard, reps.standard), (.edgeToEdge, reps.edgeToEdge), (.splitView, reps.splitView),
                (.stageManager, reps.stageManager), (.externalDisplay, reps.externalDisplay),
            ]
            for (displayType, orientations) in byDisplayType {
                for orientationName in (orientations ?? [:]).keys {
                    let orientation = try #require(DeltaSkinOrientation(rawValue: orientationName))
                    let traits = DeltaSkinTraits(device: device, displayType: displayType, orientation: orientation)
                    let rep = try #require(skin.representation(for: traits), "\(name) \(device) \(displayType) \(orientationName)")
                    #expect(rep.mappingSize.width > 0 && rep.mappingSize.height > 0)
                    #expect(skin.screens(for: traits)?.isEmpty == false)
                    for asset in rep.assets.candidates() {
                        #expect(!(try skin.loadAssetData(asset)).isEmpty, "\(name): asset \(asset)")
                    }
                    resolved += 1
                }
            }
        }
        #expect(resolved > 0)
    }
}
