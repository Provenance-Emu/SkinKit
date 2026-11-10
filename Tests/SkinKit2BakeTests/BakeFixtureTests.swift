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
