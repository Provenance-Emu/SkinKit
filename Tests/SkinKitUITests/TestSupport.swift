#if canImport(UIKit)
import Foundation
import SkinKitCore
import Testing
import UIKit
@testable import SkinKitUI

/// Shared helpers for the SkinKitUI tests: fixture skins, declared traits, synthetic skins.
enum TestSupport {
    /// Every fixture skin (the five Provenance test skins plus the 23 bundled default skins).
    static let fixtureNames: [String] = {
        guard let dir = Bundle.module.url(forResource: "Fixtures", withExtension: nil),
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.filter { $0.hasSuffix(".deltaskin") }.sorted()
    }()

    /// The 23 shipped default skins (full artwork). The five `-Test` skins are UITesting layouts
    /// without artwork files, so they cannot render.
    static let defaultSkinNames: [String] = fixtureNames.filter { !$0.hasSuffix("-Test.deltaskin") }

    /// The `-Test` fixtures: layouts only, no artwork.
    static let layoutOnlyNames: [String] = fixtureNames.filter { $0.hasSuffix("-Test.deltaskin") }

    static func fixtureURL(_ name: String) throws -> URL {
        try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil))
    }

    static func loadFixture(_ name: String) throws -> DeltaSkin {
        try DeltaSkin(fileURL: fixtureURL(name))
    }

    /// Every device / display type / orientation the skin's `info.json` declares a representation for.
    static func declaredTraits(of skin: DeltaSkin) -> [DeltaSkinTraits] {
        var result: [DeltaSkinTraits] = []
        for (device, reps) in skin.info.representations {
            let byDisplayType: [(DeltaSkinDisplayType, [String: DeltaSkin.OrientationRepresentations]?)] = [
                (.standard, reps.standard), (.edgeToEdge, reps.edgeToEdge), (.splitView, reps.splitView),
                (.stageManager, reps.stageManager), (.externalDisplay, reps.externalDisplay),
            ]
            for (displayType, orientations) in byDisplayType {
                for orientationName in (orientations ?? [:]).keys {
                    guard let orientation = DeltaSkinOrientation(rawValue: orientationName) else { continue }
                    let traits = DeltaSkinTraits(device: device, displayType: displayType, orientation: orientation)
                    if skin.supports(traits) { result.append(traits) }
                }
            }
        }
        return result
    }

    /// Removes the on-disk raster cache so a PNG left by an earlier run cannot hide a regression.
    static func clearDiskRasterCache() {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        try? FileManager.default.removeItem(at: caches.appendingPathComponent("DeltaSkinImageCache", isDirectory: true))
    }

    /// Turns the default-skin fallback off so a broken render cannot be hidden by a substitute skin.
    static func disableDefaultSkinFallback() {
        DeltaSkinRendering.defaultSkinProvider = { _ in nil }
    }

    static func makeScratch(_ label: String = "SkinKitUITests") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Synthetic artwork

    /// A one-rect PDF (`size` points) with a visible fill.
    static func makePDFData(size: CGSize = CGSize(width: 100, height: 100), color: UIColor = .red) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size))
        return renderer.pdfData { ctx in
            ctx.beginPage()
            color.setFill()
            ctx.fill(CGRect(x: 10, y: 10, width: size.width - 20, height: size.height - 20))
        }
    }

    /// An opaque PNG (no alpha channel) of a solid colour.
    static func makeOpaquePNG(size: CGSize = CGSize(width: 32, height: 32), color: UIColor = .blue) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).pngData { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// Writes a skin directory with `info.json` and `files`, returning its URL.
    static func writeSkin(info: [String: Any], files: [String: Data], in dir: URL, name: String = "Synthetic.deltaskin") throws -> URL {
        let skinDir = dir.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: skinDir, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: info).write(to: skinDir.appendingPathComponent("info.json"))
        for (file, data) in files {
            try data.write(to: skinDir.appendingPathComponent(file))
        }
        return skinDir
    }

    /// An `info.json` for a GBA skin with one iPhone portrait representation that uses `asset`.
    static func gbaInfo(identifier: String, asset: String, themes: [[String: Any]]? = nil, extraItems: [[String: Any]] = []) -> [String: Any] {
        var info: [String: Any] = [
            "name": "Synthetic",
            "identifier": identifier,
            "gameTypeIdentifier": "com.rileytestut.delta.game.gba",
            "debug": false,
            "representations": [
                "iphone": [
                    "standard": [
                        "portrait": [
                            "assets": ["resizable": asset],
                            "mappingSize": ["width": 100, "height": 200],
                            "translucent": false,
                            "screens": [[
                                "inputFrame": ["x": 0, "y": 0, "width": 240, "height": 160],
                                "outputFrame": ["x": 0, "y": 0, "width": 100, "height": 67],
                            ]],
                            "items": extraItems,
                        ],
                    ],
                ],
            ],
        ]
        if let themes { info["themes"] = themes }
        return info
    }

    static let portrait = DeltaSkinTraits(device: .iphone, displayType: .standard, orientation: .portrait)
}
#endif
