//
//  BezelPackageTests.swift
//  SkinKitBezels
//
//  What the package adds for apps that share it: stored choices, the choice in effect, built
//  scenes and the plain (shader-free) layout.
//

import CoreGraphics
import Foundation
import Testing
@testable import SkinKitBezels

@Suite("UserDefaultsBezelSettings")
struct UserDefaultsBezelSettingsTests {

    private func settings() -> UserDefaultsBezelSettings {
        let name = "SkinKitBezelsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return UserDefaultsBezelSettings(defaults: defaults, prefix: "test.bezel.")
    }

    @Test("A player who never chose has Automatic, system matching on and nothing else")
    func defaults() {
        let settings = settings()
        #expect(settings.chosenBezel == ExternalDisplayBezelRules.automaticBezelID)
        #expect(settings.matchesSystem)
        #expect(settings.lightsRoom == nil)
        #expect(!settings.showsGameArtwork)
        #expect(settings.bezelProjectStyle == .gameArt)
        #expect(settings.pinnedBezels.isEmpty)
    }

    @Test("Every value reads back as it was stored")
    func roundTrip() {
        let settings = settings()
        settings.chosenBezel = "studio-monitor"
        settings.matchesSystem = false
        settings.lightsRoom = false
        settings.showsGameArtwork = true
        settings.bezelProjectStyle = .systemArt
        settings.pinnedBezels["game"] = ExternalDisplayBezelRules.noBezelID
        #expect(settings.chosenBezel == "studio-monitor")
        #expect(!settings.matchesSystem)
        #expect(settings.lightsRoom == false)
        #expect(settings.showsGameArtwork)
        #expect(settings.bezelProjectStyle == .systemArt)
        #expect(settings.pinnedBezel(forGame: "game") == ExternalDisplayBezelRules.noBezelID)
        #expect(settings.pinnedBezel(forGame: "other") == nil)
        #expect(settings.pinnedBezel(forGame: nil) == nil)
        settings.lightsRoom = nil
        #expect(settings.lightsRoom == nil)
    }
}

@Suite("BezelChoice")
@MainActor
struct BezelChoiceTests {

    private func settings() -> UserDefaultsBezelSettings {
        let name = "SkinKitBezelsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return UserDefaultsBezelSettings(defaults: defaults)
    }

    @Test("The stored choice decides, and a game's pin comes before it")
    func storedChoiceAndPin() {
        let settings = settings()
        settings.chosenBezel = "studio-monitor"
        #expect(BezelChoice.resolve(gameID: "a", systemID: nil, systemSuitsTV: true, preview: nil, settings: settings)
            .bezel?.id == "studio-monitor")
        settings.pinnedBezels["a"] = "computer-monitor"
        #expect(BezelChoice.resolve(gameID: "a", systemID: nil, systemSuitsTV: true, preview: nil, settings: settings)
            .bezel?.id == "computer-monitor")
        #expect(BezelChoice.resolve(gameID: "b", systemID: nil, systemSuitsTV: true, preview: nil, settings: settings)
            .bezel?.id == "studio-monitor")
    }

    @Test("A preview is read ahead of the pin and the stored choice, and Off is not 'no preview'")
    func preview() {
        let settings = settings()
        settings.chosenBezel = "studio-monitor"
        settings.pinnedBezels["a"] = "computer-monitor"
        let tried = BezelPreview(choice: "living-room-tv", lightsRoom: false)
        #expect(BezelChoice.resolve(gameID: "a", systemID: nil, systemSuitsTV: true, preview: tried, settings: settings)
            .bezel?.id == "living-room-tv")
        let off = BezelPreview(choice: ExternalDisplayBezelRules.noBezelID, lightsRoom: false)
        let resolved = BezelChoice.resolve(gameID: "a", systemID: nil, systemSuitsTV: true, preview: off, settings: settings)
        #expect(resolved.bezel == nil)
        #expect(resolved.resolution.outcome == .noneChosen)
        #expect(!BezelChoice.lightsRoom(preview: off))
        #expect(BezelChoice.lightsRoom(preview: BezelPreview(choice: "living-room-tv", lightsRoom: true)))
    }

    @Test("A TV chosen for every game over a running game is the TV that game shows")
    func chooseForEveryGame() {
        let settings = settings()
        let rules = ExternalDisplayBezelRules.self
        func shown(_ game: String) -> String? {
            BezelChoice.resolve(gameID: game, systemID: nil, systemSuitsTV: true, preview: nil, settings: settings).bezel?.id
        }
        // A pin would hide the new choice: it goes.
        settings.pinnedBezels["pinned"] = "computer-monitor"
        BezelChoice.chooseForEveryGame("studio-monitor", playing: "pinned", systemID: nil, systemSuitsTV: true, settings: settings)
        #expect(settings.chosenBezel == "studio-monitor")
        #expect(settings.pinnedBezel(forGame: "pinned") == nil)
        #expect(shown("pinned") == "studio-monitor")

        // Artwork found for the game comes ahead of the saved choice, so the choice is pinned to it too.
        settings.showsGameArtwork = true
        let style = settings.bezelProjectStyle
        #expect(ExternalDisplayGameArtwork.shared.begin(game: "with-art", style: style))
        #expect(ExternalDisplayGameArtwork.shared.finish(game: "with-art", style: style, bezelID: "dorm-tv"))
        #expect(shown("with-art") == "dorm-tv")
        BezelChoice.chooseForEveryGame("living-room-tv", playing: "with-art", systemID: nil, systemSuitsTV: true, settings: settings)
        #expect(settings.pinnedBezel(forGame: "with-art") == "living-room-tv")
        #expect(shown("with-art") == "living-room-tv")
        #expect(shown("another") == "living-room-tv")

        // Off is a choice as well: the artwork would still show, so Off is pinned.
        BezelChoice.chooseForEveryGame(rules.noBezelID, playing: "with-art", systemID: nil, systemSuitsTV: true, settings: settings)
        #expect(settings.pinnedBezel(forGame: "with-art") == rules.noBezelID)
        #expect(shown("with-art") == nil)

        // Automatic hands the choice back to the rules: the pin goes and the artwork shows.
        BezelChoice.chooseForEveryGame(rules.automaticBezelID, playing: "with-art", systemID: nil, systemSuitsTV: true, settings: settings)
        #expect(settings.pinnedBezel(forGame: "with-art") == nil)
        #expect(shown("with-art") == "dorm-tv")

        // With no game running only the choice is saved.
        settings.pinnedBezels["kept"] = "computer-monitor"
        BezelChoice.chooseForEveryGame("studio-monitor", playing: nil, systemID: nil, systemSuitsTV: true, settings: settings)
        #expect(settings.pinnedBezels == ["kept": "computer-monitor"])
    }

    @Test("Automatic gives a console a TV and a handheld none")
    func automatic() {
        let settings = settings()
        let console = BezelChoice.resolve(gameID: nil, systemID: "com.provenance.snes", systemSuitsTV: true,
                                          preview: nil, settings: settings)
        #expect(console.bezel?.id == ExternalDisplayBezelRules.automaticDefaultBezelID)
        #expect(console.resolution.isAutomatic)
        // A console of about 2000 gets the TV of its day, not the wood-grain set.
        let later = BezelChoice.resolve(gameID: nil, systemID: "com.provenance.gamecube", systemSuitsTV: true,
                                        preview: nil, settings: settings)
        #expect(later.bezel?.id == "flat-tube-tv")
        #expect(later.resolution.isAutomatic)
        let handheld = BezelChoice.resolve(gameID: nil, systemID: "com.provenance.gba", systemSuitsTV: false,
                                           preview: nil, settings: settings)
        #expect(handheld.bezel == nil)
    }
}

@Suite("TVBezelScene")
struct TVBezelSceneTests {

    private let bezel = TVBezelCatalog.bundled.first

    @Test("A scene made for a canvas carries it, keys on it and sizes its tube from its width")
    func sceneForCanvas() throws {
        let bezel = try #require(TVBezelCatalog.bezel(id: "studio-monitor"))
        let canvas = CGSize(width: 1440, height: 1080)
        let key = TVBezelScene.key(bezel: bezel, lightsRoom: false, flatGlass: false, scenePixelWidth: 480, canvas: canvas)
        #expect(key != TVBezelScene.key(bezel: bezel, lightsRoom: false, flatGlass: false, scenePixelWidth: 480))
        let scene = try #require(TVBezelScene.make(bezel: bezel, lightsRoom: false, flatGlass: false, scenePixelWidth: 480,
                                                   key: key, canvas: canvas) { _ in true })
        #expect(scene.canvas == canvas)
        #expect(scene.values["fr_zoom"] == Float(scene.tubeRect.height / canvas.width * 100))
    }

    @Test("The default canvas leaves a scene's key as it was")
    func defaultCanvasKey() throws {
        let bezel = try #require(bezel)
        #expect(TVBezelScene.key(bezel: bezel, lightsRoom: false, flatGlass: false, scenePixelWidth: 480)
                == "\(bezel.id)|480|false|false")
    }

    @Test("A built-in TV becomes a preset, its values and its cabinet as a PNG")
    func builtIn() throws {
        let bezel = try #require(bezel)
        let key = TVBezelScene.key(bezel: bezel, lightsRoom: false, flatGlass: false, scenePixelWidth: 480)
        let scene = try #require(TVBezelScene.make(bezel: bezel, lightsRoom: false, flatGlass: false,
                                                   scenePixelWidth: 480, key: key) { _ in true })
        #expect(scene.key == key)
        #expect(scene.presetID == TVBezelShader.bezelOnlyID)
        #expect(scene.values["fr_zoom"] != nil)
        #expect(scene.values[TVBezelShader.glassCurvatureName] != 0)
        #expect(try #require(scene.borderPNG).starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(scene.tubeRect == (try TVBezelArtwork(bezel: bezel)).tubeRect)
    }

    @Test("Room light uses the ambient preset when the library has it, else the plain one")
    func roomLight() throws {
        let bezel = try #require(bezel)
        let lit = TVBezelScene.make(bezel: bezel, lightsRoom: true, flatGlass: true, scenePixelWidth: 320, key: "a") { _ in true }
        #expect(lit?.presetID == TVBezelShader.ambientID)
        #expect(lit?.values[TVBezelShader.glassCurvatureName] == 0)
        let fallback = TVBezelScene.make(bezel: bezel, lightsRoom: true, flatGlass: false, scenePixelWidth: 320, key: "b") {
            $0 == TVBezelShader.bezelOnlyID
        }
        #expect(fallback?.presetID == TVBezelShader.bezelOnlyID)
    }

    @Test("An app with no shader library gets no scene, and no shader-only TVs")
    func noLibrary() throws {
        let bezel = try #require(bezel)
        #expect(TVBezelScene.make(bezel: bezel, lightsRoom: false, flatGlass: false, scenePixelWidth: 320, key: "c") { _ in false } == nil)
        let preset = TVBezel(presetID: TVBezelShader.ambientID, name: "Ambient")
        #expect(TVBezelScene.make(bezel: preset, lightsRoom: false, flatGlass: false, scenePixelWidth: 320, key: "d") { _ in false } == nil)
        let standalone = TVBezelScene.make(bezel: preset, lightsRoom: false, flatGlass: false, scenePixelWidth: 320, key: "e") { _ in true }
        #expect(standalone?.borderPNG == nil)
        #expect(standalone?.presetID == TVBezelShader.ambientID)
    }
}

@Suite("TVBezelLayout")
struct TVBezelLayoutTests {

    @Test("From a seat, a built-in TV's artwork is the whole container and the tube is centred in it")
    func seatedLayoutFillsTheContainer() throws {
        let bezel = try #require(TVBezelCatalog.bezel(id: "studio-monitor"))
        let container = CGSize(width: 1440, height: 1080)
        let layout = try #require(TVBezelLayout(bezel: bezel, container: container, pictureAspect: CGSize(width: 4, height: 3),
                                                seat: .back))
        #expect(layout.artworkFrame == CGRect(origin: .zero, size: container))
        #expect(layout.screenFrame == CGRect(x: 216, y: 162, width: 1008, height: 756))
        #expect(layout.canvas == container)
        #expect(layout.placement == .behindPicture)
        // Half the size, same shape: everything halves.
        let half = try #require(TVBezelLayout(bezel: bezel, container: CGSize(width: 720, height: 540),
                                              pictureAspect: CGSize(width: 4, height: 3), seat: .back))
        #expect(half.screenFrame == CGRect(x: 108, y: 81, width: 504, height: 378))
    }

    @Test("A closer seat draws the tube larger in the same container")
    func closerSeat() throws {
        let bezel = try #require(TVBezelCatalog.bezel(id: "studio-monitor"))
        let container = CGSize(width: 1200, height: 900)
        let front = try #require(TVBezelLayout(bezel: bezel, container: container, pictureAspect: CGSize(width: 4, height: 3),
                                               seat: .front))
        #expect(front.screenFrame == CGRect(x: 96, y: 72, width: 1008, height: 756))
        let back = try #require(TVBezelLayout(bezel: bezel, container: container, pictureAspect: CGSize(width: 4, height: 3),
                                              seat: .back))
        #expect(back.screenFrame.width < front.screenFrame.width)
    }

    @Test("A container outside the supported shapes gets the nearest canvas, fitted whole")
    func seatedLayoutOutsideTheRange() throws {
        let bezel = try #require(TVBezelCatalog.bezel(id: "studio-monitor"))
        let layout = try #require(TVBezelLayout(bezel: bezel, container: CGSize(width: 1000, height: 1000),
                                                pictureAspect: CGSize(width: 4, height: 3), seat: .back))
        #expect(layout.canvas == CGSize(width: 1440, height: 1080))
        #expect(layout.artworkFrame == CGRect(x: 0, y: 125, width: 1000, height: 750))
    }

    @Test("Without a seat the layout is the fixed 16:9 one, and an image bezel has no canvas")
    func unseatedLayoutUnchanged() throws {
        let bezel = try #require(TVBezelCatalog.bezel(id: "studio-monitor"))
        let layout = try #require(TVBezelLayout(bezel: bezel, container: CGSize(width: 1440, height: 1080),
                                                pictureAspect: CGSize(width: 4, height: 3)))
        #expect(layout.artworkFrame == CGRect(x: 0, y: 135, width: 1440, height: 810))
        #expect(layout.canvas == TVBezelArtwork.canvas)
    }

    @Test("Plain artwork drawn for a canvas has its shape, with the tube painted black")
    func plainArtworkForCanvas() throws {
        let bezel = try #require(TVBezelCatalog.bezel(id: "studio-monitor"))
        let canvas = CGSize(width: 1440, height: 1080)
        let image = try #require(TVBezelPlainArtwork.image(for: bezel, maxPixel: 480, canvas: canvas))
        #expect(image.width == 480 && image.height == 360)
        #expect(TVBezelPlainArtwork.tubeRect(of: bezel, canvas: canvas) == CGRect(x: 216, y: 162, width: 1008, height: 756))
        #expect(TVBezelPlainArtwork.tubeRect(of: bezel) == CGRect(x: 456, y: 162, width: 1008, height: 756))
        let data = try #require(image.dataProvider?.data as Data?)
        let centre = (180 * image.bytesPerRow) + 240 * 4
        #expect(data[centre] == 0 && data[centre + 1] == 0 && data[centre + 2] == 0)
    }

    @Test("A built-in TV fills a 16:9 container, with a 4:3 picture filling its tube")
    func builtIn() throws {
        let bezel = try #require(TVBezelCatalog.bezel(id: "living-room-tv"))
        let layout = try #require(TVBezelLayout(bezel: bezel, container: CGSize(width: 960, height: 540),
                                                pictureAspect: CGSize(width: 4, height: 3)))
        #expect(layout.placement == .behindPicture)
        #expect(layout.artworkFrame == CGRect(x: 0, y: 0, width: 960, height: 540))
        // The tube is 960x720 at (480, 180) on the 1920x1080 canvas.
        #expect(layout.screenFrame == CGRect(x: 240, y: 90, width: 480, height: 360))
        #expect(layout.pictureFrame == layout.screenFrame)
    }

    @Test("A wider container letterboxes the scene, and a wide picture gets the TV's wide tube")
    func letterboxed() throws {
        let bezel = try #require(TVBezelCatalog.bezel(id: "living-room-tv"))
        let layout = try #require(TVBezelLayout(bezel: bezel, container: CGSize(width: 1200, height: 540),
                                                pictureAspect: CGSize(width: 16, height: 9)))
        #expect(layout.artworkFrame == CGRect(x: 120, y: 0, width: 960, height: 540))
        // The wide tube is 1280x720 at (320, 180) on the 1920x1080 canvas.
        #expect(layout.screenFrame == CGRect(x: 280, y: 90, width: 640, height: 360))
        #expect(layout.pictureFrame.width == layout.screenFrame.width)
        #expect(abs(layout.pictureFrame.height - 360) < 0.001)
        #expect(abs(layout.pictureFrame.midY - layout.screenFrame.midY) < 0.001)
    }

    @Test("An image bezel goes above the picture, which fills its see-through screen")
    func imageBezel() throws {
        let art = TVBezel.ImageArtwork(fileURL: URL(fileURLWithPath: "/nowhere.png"), size: CGSize(width: 1920, height: 1080),
                                       screen: CGRect(x: 240, y: 0, width: 1440, height: 1080))
        let bezel = TVBezel(id: "file:test.png", name: "Test", preferredSystems: [], image: art, source: .imported, isListed: true)
        let layout = try #require(TVBezelLayout(bezel: bezel, container: CGSize(width: 960, height: 540),
                                                pictureAspect: CGSize(width: 4, height: 3)))
        #expect(layout.placement == .abovePicture)
        #expect(layout.screenFrame == CGRect(x: 120, y: 0, width: 720, height: 540))
        #expect(layout.pictureFrame == layout.screenFrame)
    }

    @Test("A shader-only TV and an empty container have no plain layout")
    func none() throws {
        let preset = TVBezel(presetID: TVBezelShader.ambientID, name: "Ambient")
        #expect(TVBezelLayout(bezel: preset, container: CGSize(width: 960, height: 540), pictureAspect: CGSize(width: 4, height: 3)) == nil)
        let bezel = try #require(TVBezelCatalog.bundled.first)
        #expect(TVBezelLayout(bezel: bezel, container: .zero, pictureAspect: CGSize(width: 4, height: 3)) == nil)
        #expect(TVBezelPlainArtwork.image(for: preset, maxPixel: 320) == nil)
    }

    @Test("Plain artwork is the cabinet with a black tube")
    func plainArtwork() throws {
        let bezel = try #require(TVBezelCatalog.bezel(id: "living-room-tv"))
        let image = try #require(TVBezelPlainArtwork.image(for: bezel, maxPixel: 480))
        #expect(image.width == 480 && image.height == 270)
        var pixel = [UInt8](repeating: 255, count: 4)
        let context = try #require(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Draw so the image's centre, which is inside the tube, lands on the one pixel.
        context.draw(image, in: CGRect(x: -240, y: -135, width: 480, height: 270))
        #expect(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 0 && pixel[3] == 255)
    }
}
