import CoreGraphics
import Testing
@testable import SkinKitUI

/// A D-pad touch steers the pad until it lifts, so offsets far outside the pad still press a direction.
@Suite("D-pad directions")
struct SkinDPadDirectionsTests {
    private static let pad = CGSize(width: 150, height: 150)

    private func directions(_ dx: CGFloat, _ dy: CGFloat) -> Set<String> {
        SkinDPadDirections.directions(offset: CGVector(dx: dx, dy: dy), padSize: Self.pad)
    }

    @Test("Each arm presses its cardinal direction")
    func cardinals() {
        #expect(directions(0, -60) == ["up"])
        #expect(directions(0, 60) == ["down"])
        #expect(directions(-60, 0) == ["left"])
        #expect(directions(60, 0) == ["right"])
    }

    @Test("A corner between two arms presses the diagonal")
    func diagonals() {
        #expect(directions(60, -60) == ["up", "right"])
        #expect(directions(-60, 60) == ["down", "left"])
    }

    @Test("A finger dragged past the pad's edge keeps pressing that way")
    func farOutside() {
        #expect(directions(400, 10) == ["right"])
        #expect(directions(-10, -400) == ["up"])
        #expect(directions(-400, 300) == ["down", "left"])
    }

    @Test("The centre and under-threshold offsets resolve to the nearest single direction, never nothing")
    func centre() {
        #expect(directions(0, 0) == ["right"])
        #expect(directions(10, -30) == ["up"])
        #expect(directions(-30, 10) == ["left"])
    }
}
