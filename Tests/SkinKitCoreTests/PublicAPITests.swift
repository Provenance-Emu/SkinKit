import CoreGraphics
import Foundation
import Testing
import SkinKitCore   // deliberately not @testable: this file only compiles if the API Provenance uses is public

/// Touches the API surface Provenance's views, input handling and managers use from outside the
/// module, so a missing `public` fails the build here instead of in the app.
@Suite("Public API surface")
struct PublicAPITests {

    private static let infoJSON = #"""
    {
      "name": "API Skin", "identifier": "com.example.api", "gameTypeIdentifier": "com.rileytestut.delta.game.gba",
      "keyboardOverlay": { "variant": "compact", "autoShow": true },
      "themes": [ { "id": "neon", "name": "Neon",
                    "assets": { "iphone": { "standard": { "portrait": { "resizable": "neon.pdf" } } } } } ],
      "gameOverrides": { "Metroid": { "iphone": { "standard": { "portrait": {
          "assets": { "resizable": "metroid.pdf" }, "mappingSize": { "width": 100, "height": 200 }, "items": [] } } } } },
      "representations": { "iphone": { "standard": { "portrait": {
        "assets": { "small": "s.png", "large": "l.png" },
        "mappingSize": { "width": 375, "height": 812 },
        "extendedEdges": { "top": 1, "left": 2, "bottom": 3, "right": 4 },
        "translucent": true,
        "gameScreenFrame": { "x": 0, "y": 0, "width": 375, "height": 300 },
        "screens": [ { "inputFrame": { "x": 0, "y": 0, "width": 240, "height": 160 },
                       "outputFrame": { "x": 0, "y": 50, "width": 375, "height": 250 },
                       "placement": "controller",
                       "filters": [ { "name": "CIGaussianBlur", "parameters": { "inputRadius": 2 } } ] } ],
        "items": [
          { "inputs": ["a"], "frame": { "x": 300, "y": 600, "width": 60, "height": 60 },
            "extendedEdges": { "top": 5, "left": 5, "bottom": 5, "right": 5 },
            "haptic": { "style": "light", "intensity": 0.5 },
            "states": { "normal": { "image": "n.png" }, "pressed": { "image": "p.png" } } },
          { "inputs": { "up": "up", "down": "down", "left": "left", "right": "right" },
            "frame": { "x": 20, "y": 600, "width": 120, "height": 120 },
            "thumbstick": { "name": "stick.pdf", "width": 40, "height": 40 } }
        ]
      } } } }
    }
    """#

    private func makeSkin() throws -> (DeltaSkin, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkinKitCoreTests-\(UUID().uuidString).deltaskin", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(Self.infoJSON.utf8).write(to: dir.appendingPathComponent("info.json"))
        try Data("l".utf8).write(to: dir.appendingPathComponent("l.png"))
        return (try DeltaSkin(fileURL: dir), dir)
    }

    @Test("Model, info and representation members are readable from outside the module")
    func readsModel() throws {
        let (skin, dir) = try makeSkin()
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(skin.info.name == "API Skin")
        #expect(skin.info.gameTypeIdentifier == .gba)
        #expect(skin.info.debug == false)
        #expect(skin.info.caseController == false)
        #expect(skin.info.themes?.first?.assets?["iphone"] != nil)
        #expect(skin.info.gameOverrides?["Metroid"] != nil)
        #expect(skin.keyboardOverlay?.variant == .compact)
        #expect(skin.availableThemes.first?.id == "neon")
        #expect(skin.isCaseControllerSkin == false)
        #expect(!skin.jsonRepresentation.isEmpty)

        let traits = DeltaSkinTraits(device: .iphone, displayType: .standard, orientation: .portrait)
        let rep = try #require(skin.representation(for: traits))
        #expect(rep.mappingSize == CGSize(width: 375, height: 812))
        #expect(rep.translucent == true)
        #expect(rep.extendedEdges == DeltaSkinEdgeInsets(top: 1, left: 2, bottom: 3, right: 4))
        #expect(rep.gameScreenFrame?.height == 300)
        #expect(rep.assets.candidates() == ["l.png", "s.png"])
        #expect(rep.assets.filename == "l.png")
        #expect(rep.assets.filename(for: .small) == "s.png")

        let screen = try #require(rep.screens?.first)
        #expect(screen.placement == .controller)
        #expect(screen.maintainAspectRatio)
        #expect(screen.filters?.first?.name == "CIGaussianBlur")

        let items = try #require(rep.items)
        #expect(items[0].frame.width == 60)
        #expect(items[0].haptic?.style == "light")
        #expect(items[0].states?.pressed?.image == "p.png")
        #expect(items[1].thumbstick?.name == "stick.pdf")
        if case .single(let inputs) = items[0].inputs { #expect(inputs == ["a"]) } else { Issue.record("expected single") }
        let group = skin.toButtonGroup(from: rep)
        #expect(group.buttons.count == 2)

        // Game override resolves by title, and the cache keeps the base representation separate.
        let metroid = DeltaSkinTraits(device: .iphone, displayType: .standard, orientation: .portrait, gameIdentifier: "metroid")
        #expect(skin.mappingSize(for: metroid) == CGSize(width: 100, height: 200))
        #expect(skin.mappingSize(for: traits) == CGSize(width: 375, height: 812))
        DeltaSkin.clearRepresentationCache()
    }

    @Test("Screens, buttons and groups the views consume")
    func derivedLayout() throws {
        let (skin, dir) = try makeSkin()
        defer { try? FileManager.default.removeItem(at: dir) }
        let traits = DeltaSkinTraits(device: .iphone, displayType: .standard, orientation: .portrait)

        let buttons = try #require(skin.buttons(for: traits))
        #expect(buttons.map(\.buttonKind) == [.normal, .normal])
        #expect(buttons[0].withFrame(.zero).frame == .zero)
        #expect(buttons[0].extendedEdges?.top == 5)
        #expect(skin.screens(for: traits)?.count == 1)
        #expect(skin.screenGroups(for: traits)?.first?.translucent == true)
        #expect(!skin.buttonMappings(for: traits).isEmpty)
        #expect(try skin.loadAssetData("l.png") == Data("l".utf8))
    }

    @Test("Value types can be constructed from outside the module")
    func constructs() {
        let button = DeltaSkinButton(id: "a", input: .single("a"), frame: .zero, extendedEdges: .zero)
        let group = DeltaSkinButtonGroup(buttons: [button], extendedEdges: nil, translucent: false)
        #expect(group.buttons.count == 1)
        _ = DeltaSkinButtonStateImage(image: "x.png")
        _ = DeltaSkinButtonAnimated(frames: ["a"], fps: 8, loops: true)
        _ = DeltaSkinButtonStates(normal: DeltaSkinButtonStateImage(image: "n.png"))
        _ = DeltaSkinButtonSwitchAnimation()
        _ = DeltaSkinHaptic()
        _ = DeltaSkinBackgroundAnimation(type: .gif, file: "bg.gif")
        _ = DeltaSkin.Theme(id: "t", name: "T")
        _ = DeltaSkin.ThumbstickConfig(name: "s.pdf", width: 1, height: 1)
        _ = DeltaSkin.AssetRepresentation(resizable: "r.pdf", small: nil, medium: nil, large: nil)
        let info = DeltaSkin.FilterInfo(name: "CIColorControls", parameters: ["inputBrightness": .number(0.2)])
        #expect(DeltaSkinScreenFilter(filterInfo: info) != nil)
        let screen = DeltaSkinScreen(id: "s", inputFrame: nil, outputFrame: .zero, placement: .app, filters: nil)
        _ = DeltaSkinScreenGroup(id: "g", screens: [screen], extendedEdges: nil, translucent: nil, gameScreenFrame: nil)
        _ = DeltaSkin.RepresentationInfo(assets: DeltaSkin.AssetRepresentation(resizable: nil, small: nil, medium: nil, large: nil))
        _ = KeyboardOverlayConfig(variant: .full)
        _ = DeltaSkinTraits()
        _ = DeltaSkinFilter(name: "n", parameters: [:])
        #expect(DeltaSkinDevice.iphone.assetSize(for: .standard) != .zero)
        #expect(DeltaSkinGameType.gba.registryKey == "gba")
        #expect(DeltaSkinGameType.gbc.skinLayoutGroup == "gb-family")
        #expect(DeltaSkinAssetSize.large.rawValue == "large")
    }

    @Test("Hooks the host app sets are public")
    func hooks() {
        let original = DeltaSkinCompanionSkinDetection.matcher
        defer { DeltaSkinCompanionSkinDetection.matcher = original }
        DeltaSkinCompanionSkinDetection.matcher = { $0.hasPrefix("com.provenance.defaultskins.backbone") }
        #expect(DeltaSkinCompanionSkinDetection.matcher("com.provenance.defaultskins.backbone.gba"))
        #expect(!DeltaSkinCompanionSkinDetection.matcher("com.example"))
        #expect(DeltaSkinThemeSelection.keyPrefix == "com.provenance.deltaskin.theme.")
    }

    @Test("Decoding options and what they need are public")
    func decodingOptions() throws {
        let options: DeltaSkin.DecodingOptions = [.stripsComments, .dropsInvalidElements, .limitsFrames, .inheritsEdges,
                                                  .requiresCompleteDirections, .keepsItemAssets, .canonicalGameTypes]
        #expect(options == .lenient)
        #expect(DeltaSkin.DecodingOptions.maxFrameMagnitude > 0)
        let info = try DeltaSkin.Info.decode(Data(Self.infoJSON.utf8), options: .lenient)
        #expect(info.representations.isEmpty == false)
        _ = DeltaSkin.ItemAsset(normal: "a.pdf")
        #expect(DeltaSkinInfoError.noUsableRepresentation != .unsupportedGameType("x"))
        #expect(try DeltaSkin.stripComments(Data("{} // x".utf8)).isEmpty == false)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("api-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(Self.infoJSON.utf8).write(to: url.appendingPathComponent("info.json"))
        _ = try DeltaSkin(fileURL: url, options: .lenient)
    }
}
