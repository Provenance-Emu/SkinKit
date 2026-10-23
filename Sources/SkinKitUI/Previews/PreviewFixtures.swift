#if DEBUG && canImport(UIKit)
import Foundation
import SkinKitCore
import SkinKitManager
import SkinCatalogKit

/// Fixture skins for the `#Preview`s in this module.
///
/// Previews cannot see the test target's resources, and shipping sample skins in the library would
/// bloat every app. So the previews read the skins that live in `Tests/SkinKitUITests/Fixtures`
/// straight from the source tree, through `#filePath`. That works in Xcode previews (the
/// package is open from its checkout) and is compiled out of release builds.
enum PreviewFixtures {
    /// `Tests/SkinKitUITests/Fixtures`, found relative to this source file.
    static let directory: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Previews
        .deletingLastPathComponent() // SkinKitUI
        .deletingLastPathComponent() // Sources
        .deletingLastPathComponent() // package root
        .appendingPathComponent("Tests/SkinKitUITests/Fixtures", isDirectory: true)

    /// A fixture skin, e.g. `"Backbone-GBA"`.
    static func skin(_ name: String) -> DeltaSkin {
        do {
            return try DeltaSkin(fileURL: directory.appendingPathComponent("\(name).deltaskin", isDirectory: true))
        } catch {
            fatalError("Preview fixture \(name) missing at \(directory.path): \(error)")
        }
    }

    static let portrait = DeltaSkinTraits(device: .iphone, displayType: .standard, orientation: .portrait)
    static let landscape = DeltaSkinTraits(device: .iphone, displayType: .standard, orientation: .landscape)

    /// The fixture skins a few of the previews list.
    static let names = ["PocketTaco-GBA", "PocketTaco-NES", "PocketTaco-SNES", "PocketTaco-N64", "PocketTaco-Genesis", "Soolra-GBA", "Backbone-GBA"]

    /// A manager that scans the fixture skins and keeps its imports in a scratch directory.
    @MainActor
    static func makeManager() -> DeltaSkinManager {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("SkinKitUIPreview", isDirectory: true)
        let urls = names.map { directory.appendingPathComponent("\($0).deltaskin", isDirectory: true) }
        return DeltaSkinManager(configuration: .init(skinsDirectory: scratch, bundledSkinLocations: { urls }))
    }

    /// Systems for the picker previews. Normally the app provides these.
    static let systems: [DeltaSkinSystem] = [
        DeltaSkinSystem(id: SkinSystemID("GBA"), fullName: "Game Boy Advance", gameType: .gba,
                        skinCatalogSystemCode: "gba", relatedSkinCatalogSystemCodes: ["gba"]),
        DeltaSkinSystem(id: SkinSystemID("NES"), fullName: "Nintendo Entertainment System", gameType: .nes,
                        skinCatalogSystemCode: "nes", relatedSkinCatalogSystemCodes: ["nes"]),
        DeltaSkinSystem(id: SkinSystemID("SNES"), fullName: "Super Nintendo", gameType: .snes,
                        skinCatalogSystemCode: "snes", relatedSkinCatalogSystemCodes: ["snes"]),
        DeltaSkinSystem(id: SkinSystemID("N64"), fullName: "Nintendo 64", gameType: .n64,
                        skinCatalogSystemCode: "n64", relatedSkinCatalogSystemCodes: ["n64"]),
        DeltaSkinSystem(id: SkinSystemID("Genesis"), fullName: "Sega Genesis", gameType: .genesis,
                        skinCatalogSystemCode: "genesis", relatedSkinCatalogSystemCodes: ["genesis"]),
    ]

    /// Points the shared manager and system directory at the fixtures, once, for the picker previews.
    @MainActor
    static func installSharedPreviewEnvironment() {
        DeltaSkinManager.shared = makeManager()
        DeltaSkinSystemDirectory.current = DeltaSkinSystemDirectory(systems: systems, displayNameForCatalogCode: { code in
            systems.first { $0.skinCatalogSystemCode == code.lowercased() }?.fullName ?? code.uppercased()
        })
    }

    static let catalogEntry = SkinCatalogEntry(
        id: "preview.backbone-gba",
        name: "Backbone GBA",
        author: "Provenance",
        systems: ["gba"],
        gameTypeIdentifier: "com.rileytestut.delta.game.gba",
        downloadURL: URL(string: "https://example.invalid/backbone-gba.deltaskin")!,
        tags: ["controller", "backbone"],
        deviceSupport: ["iphone"],
        description: "A fixture entry for previews."
    )
}
#endif

#if DEBUG && canImport(UIKit)
import UIKit

extension PreviewFixtures {
    /// A skin with two themes, written to a scratch directory, for the theme picker preview.
    static func themedSkin() -> DeltaSkin {
        func pdf(_ color: UIColor) -> Data {
            UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 200)).pdfData { ctx in
                ctx.beginPage()
                color.setFill()
                ctx.fill(CGRect(x: 8, y: 8, width: 84, height: 184))
            }
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SkinKitUIThemed.deltaskin", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "name": "Themed",
            "identifier": "com.skinkit.preview.themed",
            "gameTypeIdentifier": "com.rileytestut.delta.game.gba",
            "debug": false,
            "themes": [
                ["id": "neon", "name": "Neon", "assets": ["iphone": ["standard": ["portrait": ["resizable": "neon.pdf"]]]]],
                ["id": "ember", "name": "Ember", "assets": ["iphone": ["standard": ["portrait": ["resizable": "ember.pdf"]]]]],
            ],
            "representations": ["iphone": ["standard": ["portrait": [
                "assets": ["resizable": "base.pdf"],
                "mappingSize": ["width": 100, "height": 200],
                "translucent": false,
                "screens": [["inputFrame": ["x": 0, "y": 0, "width": 240, "height": 160],
                             "outputFrame": ["x": 0, "y": 0, "width": 100, "height": 67]]],
                "items": [],
            ]]]],
        ]
        if let data = try? JSONSerialization.data(withJSONObject: info) {
            try? data.write(to: dir.appendingPathComponent("info.json"))
        }
        try? pdf(.systemGray).write(to: dir.appendingPathComponent("base.pdf"))
        try? pdf(.systemTeal).write(to: dir.appendingPathComponent("neon.pdf"))
        try? pdf(.systemOrange).write(to: dir.appendingPathComponent("ember.pdf"))
        return try! DeltaSkin(fileURL: dir)
    }
}
#endif
