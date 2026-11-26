//
//  TVBezelFormsTests.swift
//  SkinKitBezels
//
//  A built-in TV drawn for a portrait screen and for a widescreen picture.
//

import CoreGraphics
import Foundation
import Testing
@testable import SkinKitBezels

@Suite("TV forms: portrait and widescreen")
struct TVBezelFormsTests {

    static let phone = CGSize(width: 430, height: 932)
    static let tablet = CGSize(width: 820, height: 1180)
    static let phoneLandscape = CGSize(width: 932, height: 430)
    static let standard = CGSize(width: 4, height: 3)
    static let wide = CGSize(width: 16, height: 9)

    private func flatTube() throws -> TVBezel { try #require(TVBezelCatalog.bezel(id: "flat-tube-tv")) }

    private func aspect(_ rect: CGRect) -> CGFloat { rect.width / rect.height }

    @Test("In portrait the room is the whole screen and the tube is in its upper half", arguments: [phone, tablet])
    func portrait(container: CGSize) throws {
        let layout = try #require(TVBezelLayout(bezel: flatTube(), container: container, pictureAspect: Self.standard, seat: .back))
        let canvas = try #require(layout.canvas)
        #expect(layout.artworkFrame == CGRect(origin: .zero, size: container))
        #expect(canvas.height > canvas.width)
        #expect(layout.screenFrame.width > container.width * 0.8)
        #expect(layout.screenFrame.minY > 0)
        #expect(layout.screenFrame.maxY < container.height * 0.6)
        #expect(abs(layout.screenFrame.midX - container.width / 2) < 0.5)
        #expect(layout.pictureFrame == layout.screenFrame)
    }

    @Test("A wide picture fills a wide tube: no bars", arguments: [phone, tablet, phoneLandscape, CGSize(width: 1920, height: 1080)])
    func widescreen(container: CGSize) throws {
        let layout = try #require(TVBezelLayout(bezel: flatTube(), container: container, pictureAspect: Self.wide, seat: .back))
        #expect(layout.shape == .wide)
        #expect(abs(aspect(layout.screenFrame) - 16.0 / 9) < 0.01)
        #expect(abs(layout.pictureFrame.width - layout.screenFrame.width) < 0.5)
        #expect(abs(layout.pictureFrame.height - layout.screenFrame.height) < 1)
        #expect(CGRect(origin: .zero, size: container).contains(layout.screenFrame))
    }

    @Test("In landscape the wide tube is as tall as the 4:3 one, so the picture is larger")
    func widescreenIsLarger() throws {
        let bezel = try flatTube()
        let standard = try #require(TVBezelLayout(bezel: bezel, container: Self.phoneLandscape, pictureAspect: Self.standard, seat: .back))
        let wide = try #require(TVBezelLayout(bezel: bezel, container: Self.phoneLandscape, pictureAspect: Self.wide, seat: .back))
        #expect(abs(wide.screenFrame.height - standard.screenFrame.height) < 0.5)
        #expect(wide.pictureFrame.width > standard.screenFrame.width * 1.3)
    }

    @Test("A 4:3 picture keeps the 4:3 tube")
    func standardUnchanged() throws {
        let layout = try #require(TVBezelLayout(bezel: flatTube(), container: Self.phoneLandscape, pictureAspect: Self.standard, seat: .back))
        #expect(layout.shape == .standard)
        #expect(abs(aspect(layout.screenFrame) - 4.0 / 3) < 0.01)
    }

    @Test("Every bundled TV has both forms", arguments: TVBezelCatalog.bundled.map(\.id))
    func everyTV(id: String) throws {
        let bezel = try #require(TVBezelCatalog.bezel(id: id))
        #expect(bezel.drawsPortrait)
        for container in [Self.phone, Self.tablet] {
            let layout = try #require(TVBezelLayout(bezel: bezel, container: container, pictureAspect: Self.standard, seat: .back))
            #expect(layout.artworkFrame == CGRect(origin: .zero, size: container))
            #expect(layout.screenFrame.maxY < container.height * 0.6)
            #expect(abs(aspect(layout.screenFrame) - 4.0 / 3) < 0.01)
        }
        for container in [Self.phone, Self.phoneLandscape, CGSize(width: 1920, height: 1080)] {
            let layout = try #require(TVBezelLayout(bezel: bezel, container: container, pictureAspect: Self.wide, seat: .back))
            #expect(abs(aspect(layout.screenFrame) - 16.0 / 9) < 0.01)
            #expect(CGRect(origin: .zero, size: container).contains(layout.screenFrame))
        }
        // The landscape scene for a 4:3 picture is what it always was: the tube is centred.
        let landscape = try TVBezelArtwork(bezel: bezel)
        #expect(abs(landscape.tubeRect.midX - TVBezelArtwork.canvas.width / 2) < 0.5)
        #expect(abs(landscape.tubeAspect - 4.0 / 3) < 0.01)
    }

    @Test("An image bezel keeps its own shape, near the top of a portrait screen")
    func imageBezelInPortrait() throws {
        let art = TVBezel.ImageArtwork(fileURL: URL(fileURLWithPath: "/nonexistent.png"), size: CGSize(width: 1920, height: 1080),
                                       screen: CGRect(x: 480, y: 180, width: 960, height: 720))
        let bezel = TVBezel(id: "file:test", name: "Test", preferredSystems: [], image: art, source: .imported, isListed: true)
        let layout = try #require(TVBezelLayout(bezel: bezel, container: Self.phone, pictureAspect: Self.wide, seat: .back))
        #expect(layout.shape == .standard)
        #expect(abs(layout.artworkFrame.minY - Self.phone.height * TVBezelLayout.portraitTopFraction) < 0.5)
        #expect(layout.artworkFrame.width == Self.phone.width)
        let landscape = try #require(TVBezelLayout(bezel: bezel, container: Self.phoneLandscape, pictureAspect: Self.wide, seat: .back))
        #expect(abs(landscape.artworkFrame.midY - Self.phoneLandscape.height / 2) < 0.5)
    }

    @Test("The artwork is drawn at the canvas's shape", arguments: [phone, phoneLandscape])
    func image(container: CGSize) throws {
        let bezel = try flatTube()
        let layout = try #require(TVBezelLayout(bezel: bezel, container: container, pictureAspect: Self.wide, seat: .back))
        let canvas = try #require(layout.canvas)
        let image = try #require(TVBezelPlainArtwork.image(for: bezel, maxPixel: 600, canvas: canvas, shape: layout.shape))
        #expect(max(image.width, image.height) <= 600)
        #expect(abs(CGFloat(image.width) / CGFloat(image.height) - canvas.width / canvas.height) < 0.01)
    }

    @Test("The tube can be left see-through, for artwork laid over the picture")
    func cutOutTube() throws {
        let bezel = try flatTube()
        let layout = try #require(TVBezelLayout(bezel: bezel, container: Self.phone, pictureAspect: Self.standard, seat: .back))
        let canvas = try #require(layout.canvas)
        let image = try #require(TVBezelPlainArtwork.image(for: bezel, maxPixel: 600, canvas: canvas, cutsOutTube: true))
        let tube = try #require(TVBezelPlainArtwork.tubeRect(of: bezel, canvas: canvas))
        let scale = CGFloat(image.width) / canvas.width
        func alpha(x: CGFloat, y: CGFloat) throws -> UInt8 {
            let data = try #require(image.dataProvider?.data as Data?)
            return data[Int(y * scale) * image.bytesPerRow + Int(x * scale) * 4 + 3]
        }
        #expect(try alpha(x: tube.midX, y: tube.midY) == 0)
        #expect(try alpha(x: tube.midX, y: tube.maxY + 400) == 255)
    }

    @Test("The shader scene has the wide tube for a wide picture, under its own key")
    func shaderScene() throws {
        let bezel = try flatTube()
        let standardKey = TVBezelScene.key(bezel: bezel, lightsRoom: false, flatGlass: false, scenePixelWidth: 480)
        let wideKey = TVBezelScene.key(bezel: bezel, lightsRoom: false, flatGlass: false, scenePixelWidth: 480, shape: .wide)
        #expect(standardKey != wideKey)
        let scene = try #require(TVBezelScene.make(bezel: bezel, lightsRoom: false, flatGlass: false, scenePixelWidth: 480,
                                                   key: wideKey, shape: .wide, hasPreset: { _ in true }))
        #expect(abs(scene.tubeRect.width / scene.tubeRect.height - 16.0 / 9) < 0.01)
        #expect(abs(scene.tubeRect.midX - TVBezelArtwork.canvas.width / 2) < 0.5)
    }
}
