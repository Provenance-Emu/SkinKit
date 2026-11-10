import Foundation
import SkinKit2Core
import SkinKitCore
@testable import SkinKit2Bake
import Testing

@Test("A resolved d-pad encodes as a classic directional item")
func classicDirectionalItem() throws {
    let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Format2Fixtures/gamecube-icube/skin.json")
    let document = try Skin2Document.load(data: Data(contentsOf: fixture))
    let environment = Skin2Environment(size: Skin2Size(width: 852, height: 393))
    let resolution = Skin2Resolver.resolve(document, in: environment)
    let dpad = try #require(resolution.controls.first { $0.node.kind == .dpad })
    let encoded = try JSONEncoder().encode(#require(ClassicItem(dpad)))
    let item = try JSONDecoder().decode(DeltaSkin.ItemRepresentation.self, from: encoded)
    guard case .directional(let directions) = item.inputs else {
        Issue.record("Expected classic directional inputs")
        return
    }
    #expect(Set(directions.keys) == ["up", "down", "left", "right"])
    #expect(abs(Double(item.frame.width) - dpad.frame.width) < 0.000_001)
    #expect(abs(Double(item.frame.height) - dpad.frame.height) < 0.000_001)
}
