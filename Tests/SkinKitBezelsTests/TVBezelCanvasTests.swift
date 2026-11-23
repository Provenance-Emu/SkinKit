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
}
