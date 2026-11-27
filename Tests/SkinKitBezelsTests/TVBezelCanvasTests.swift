//
//  TVBezelCanvasTests.swift
//  SkinKitBezels
//
//  The canvas a built-in TV is drawn on for a display's shape and a seat.
//

import CoreGraphics
import Testing
@testable import SkinKitBezels

@Suite("TVBezelCanvas")
struct TVBezelCanvasTests {

    @Test("16:9 from the back is today's canvas")
    func sixteenNine() {
        #expect(TVBezelCanvas.size(display: CGSize(width: 3840, height: 2160)) == CGSize(width: 1920, height: 1080))
    }

    @Test("The canvas has the display's proportions",
          arguments: [CGSize(width: 2360, height: 1640), CGSize(width: 2622, height: 1206), CGSize(width: 3440, height: 1440)])
    func proportions(display: CGSize) {
        let canvas = TVBezelCanvas.size(display: display)
        #expect(canvas.height == 1080)
        #expect(abs(canvas.width / canvas.height - display.width / display.height) < 0.0001)
        #expect(TVBezelCanvas.fitsDisplay(display))
    }

    @Test("Seats set the canvas height")
    func seats() {
        let display = CGSize(width: 1600, height: 1200)
        #expect(TVBezelCanvas.size(display: display, seat: .middle) == CGSize(width: 980.0 * 4 / 3, height: 980))
        #expect(TVBezelCanvas.size(display: display, seat: .front) == CGSize(width: 1200, height: 900))
    }

    @Test("Shapes outside 4:3 to 2.4:1 get the nearest supported canvas")
    func clamped() {
        #expect(TVBezelCanvas.size(display: CGSize(width: 1000, height: 1000)) == CGSize(width: 1440, height: 1080))
        #expect(TVBezelCanvas.size(display: CGSize(width: 5120, height: 1440)) == CGSize(width: 2592, height: 1080))
        #expect(!TVBezelCanvas.fitsDisplay(CGSize(width: 1000, height: 1000)))
        #expect(!TVBezelCanvas.fitsDisplay(CGSize(width: 5120, height: 1440)))
    }

    @Test("An empty display gets the default canvas")
    func empty() {
        #expect(TVBezelCanvas.size(display: .zero) == TVBezelArtwork.canvas)
        #expect(!TVBezelCanvas.fitsDisplay(.zero))
    }

    @Test("A portrait display gets a canvas of its own shape, as wide as the seat says",
          arguments: [CGSize(width: 430, height: 932), CGSize(width: 820, height: 1180), CGSize(width: 1024, height: 1366)])
    func portrait(display: CGSize) throws {
        let canvas = try #require(TVBezelCanvas.portraitSize(display: display))
        #expect(canvas.width == TVBezelSeat.back.portraitCanvasWidth)
        #expect(abs(canvas.width / canvas.height - display.width / display.height) < 0.001)
        #expect(try #require(TVBezelCanvas.portraitSize(display: display, seat: .front)).width == 1152)
        // The landscape canvas, which shader-drawn TVs use, is unchanged.
        #expect(TVBezelCanvas.size(display: display) == CGSize(width: 1440, height: 1080))
    }

    @Test("Landscape and nearly square displays have no portrait canvas",
          arguments: [CGSize(width: 932, height: 430), CGSize(width: 1000, height: 1000), CGSize(width: 900, height: 1000), CGSize.zero])
    func notPortrait(display: CGSize) {
        #expect(TVBezelCanvas.portraitSize(display: display) == nil)
    }

    @Test("A picture is wide from 16:10", arguments: [
        (CGSize(width: 4, height: 3), TVBezelPictureShape.standard),
        (CGSize(width: 3, height: 2), .standard),
        (CGSize(width: 16, height: 10), .wide),
        (CGSize(width: 16, height: 9), .wide),
        (CGSize(width: 1.7777, height: 1), .wide),
        (CGSize.zero, .standard)
    ])
    func pictureShape(aspect: CGSize, expected: TVBezelPictureShape) {
        #expect(TVBezelPictureShape(aspect: aspect) == expected)
    }

    @Test("A portrait canvas for a known tube is the tube and a thin edge each side")
    func portraitForTube() throws {
        let display = CGSize(width: 430, height: 932)
        let back = try #require(TVBezelCanvas.portraitSize(display: display, tube: CGSize(width: 1040, height: 780)))
        #expect(back.width == 1040 + 2 * TVBezelSeat.back.portraitTubeMargin)
        #expect(abs(back.width / back.height - display.width / display.height) < 0.001)
        let front = try #require(TVBezelCanvas.portraitSize(display: display, seat: .front, tube: CGSize(width: 1040, height: 780)))
        #expect(front.width < back.width)
        #expect(TVBezelCanvas.portraitSize(display: CGSize(width: 932, height: 430), tube: CGSize(width: 1040, height: 780)) == nil)
        #expect(TVBezelCanvas.portraitSize(display: display, tube: .zero) == nil)
        // A tablet held upright has the width to spare: the set keeps to its share of the height.
        let tablet = try #require(TVBezelCanvas.portraitSize(display: CGSize(width: 820, height: 1180),
                                                             tube: CGSize(width: 1040, height: 780)))
        #expect(tablet.width > back.width)
        #expect((780 + 260) / tablet.height <= TVBezelCanvas.portraitSetShare + 0.001)
    }
}
