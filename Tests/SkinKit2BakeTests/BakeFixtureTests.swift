import Foundation
import SkinKit2Bake
import SkinKitCore
import Testing

private let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Format2Fixtures")

private let fixtureNames = ((try? FileManager.default.contentsOfDirectory(atPath: fixtures.path)) ?? [])
    .filter { FileManager.default.fileExists(atPath: fixtures.appendingPathComponent($0 + "/skin.json").path) }
    .sorted()

@Test("Baked fixture archives load with the classic parser and validator", arguments: fixtureNames)
func bakedFixture(name: String) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = fixtures.appendingPathComponent(name + "/skin.json")
    let urls = try Skin2Baker.write(Skin2Baker.bake(sourceURL: source), to: root)
    try #require(!urls.isEmpty)
    let peer = ProcessInfo.processInfo.environment["SKIN2_TYPESCRIPT_BAKES"].map {
        URL(fileURLWithPath: $0).appendingPathComponent(name)
    }
    for url in urls {
        try validateArchive(url)
        if let peer { try validateArchive(peer.appendingPathComponent(url.lastPathComponent)) }
    }
}

private func validateArchive(_ url: URL) throws {
    let validation = DeltaSkinValidator.validate(url: url)
    #expect(validation.isValid, "\(validation.errors.map(\.detail))")
    let skin = try DeltaSkin(fileURL: url)
    let traits = DeltaSkinTraits(device: .iphone, displayType: .edgeToEdge, orientation: .portrait)
    #expect(skin.mappingSize(for: traits) != nil)
    let info = try #require(skin.representation(for: traits))
    let path = try #require(info.assets.resizable)
    #expect(try skin.loadAssetData(path).starts(with: Data("%PDF".utf8)))
}

private func info(_ bundle: Skin2BakedBundle) throws -> DeltaSkin.Info {
    try JSONDecoder().decode(DeltaSkin.Info.self, from: #require(bundle.files["info.json"]))
}

@Test("Classic GameCube bake preserves left and right thumbstick input names")
func bakedStickIdentity() throws {
    let bundles = try Skin2Baker.bake(sourceURL: fixtures.appendingPathComponent("gamecube-icube/skin.json"))
    let classic = try info(#require(bundles.first))
    let items = try #require(classic.representations[.iphone]?.edgeToEdge?["portrait"]?.items)
    let stickUps = items.compactMap { item -> String? in
        guard item.thumbstick != nil, case .directional(let directions) = item.inputs else { return nil }
        return directions["up"]
    }
    #expect(Set(stickUps) == ["leftThumbstickUp", "rightThumbstickUp"])
}

@Test("Layout-changing themes have complete classic layouts of their own")
func bakedThemeGeometry() throws {
    let bundles = try Skin2Baker.bake(sourceURL: fixtures.appendingPathComponent("variants/skin.json"))
    let base = try info(#require(bundles.first))
    let large = try info(#require(bundles.first { $0.variantLabel == "big" }))
    #expect(base.themes?.map(\.id) == ["red"])
    #expect(large.identifier != base.identifier)
    func faceWidth(_ skin: DeltaSkin.Info) throws -> CGFloat {
        let items = try #require(skin.representations[.iphone]?.edgeToEdge?["portrait"]?.items)
        let face = try #require(items.first { if case .single(["a"]) = $0.inputs { return true }; return false })
        return face.frame.width
    }
    #expect(try faceWidth(large) > faceWidth(base))
}

@Test("Unknown native resolution leaves classic source crop unset")
func unknownFrameBuffer() throws {
    let source = try Data(contentsOf: fixtures.appendingPathComponent("layout/skin.json"))
    var document = try #require(JSONSerialization.jsonObject(with: source) as? [String: Any])
    document["gameTypes"] = ["com.rileytestut.delta.game.nes"]
    document["root"] = ["type": "group", "children": [
        ["type": "screen", "id": "screen", "role": "main", "aspect": 1.5, "layout": ["frame": [0, 0, 100, 100]]],
    ]]
    let bundles = try Skin2Baker.bake(source: JSONSerialization.data(withJSONObject: document))
    let classic = try info(#require(bundles.first))
    let screen = try #require(classic.representations[.iphone]?.edgeToEdge?["portrait"]?.screens?.first)
    #expect(screen.inputFrame == nil)
}
