#if canImport(UIKit)
import Foundation
import SkinCatalogKit

enum SkinCatalogEntryFixture {
    static let entry = SkinCatalogEntry(
        id: "test.backbone-gba", name: "Backbone GBA", author: "Provenance", systems: ["gba"],
        gameTypeIdentifier: "com.rileytestut.delta.game.gba",
        downloadURL: URL(string: "https://example.invalid/backbone-gba.deltaskin")!,
        tags: ["controller"], deviceSupport: ["iphone"])
}
#endif
