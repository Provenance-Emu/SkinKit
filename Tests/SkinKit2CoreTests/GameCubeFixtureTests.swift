import Foundation
import Testing
@testable import SkinKit2Core

/// iCube's generated GameCube pad as one 2.0 file (the spike skin, ported): one skin, both orientations, and
/// iCube's geometry.
@Suite("GameCube fixture")
struct GameCubeFixtureTests {
    static let portrait = Skin2Environment(size: Skin2Size(width: 393, height: 852), safeArea: Skin2Insets(top: 59, bottom: 34))
    static let landscape = Skin2Environment(size: Skin2Size(width: 852, height: 393), safeArea: Skin2Insets(left: 59, bottom: 21, right: 59))
    static let ipadLandscape = Skin2Environment(size: Skin2Size(width: 1180, height: 820), safeArea: Skin2Insets(top: 24, bottom: 20), device: .ipad)
    static let noInsets = Skin2Environment(size: Skin2Size(width: 414, height: 736), displayType: .standard)

    @Test("Parts expand, controls carry their inputs and labels")
    func expandsParts() throws {
        let doc = try Skin2Document.fixture("gamecube-icube")
        #expect(doc.formatVersion == "2.0")
        let r = Skin2Resolver.resolve(doc, in: Self.portrait)
        let inputs = r.controls.flatMap(\.node.inputNames).sorted()
        #expect(inputs == ["a", "b", "down", "l", "left", "leftThumbstick", "r", "right", "rightThumbstick", "start", "up", "x", "y", "z"])
        #expect(r.node(id: "a")?.children.last?.node.text == "A")
        // Inner part ids are scoped to the instance, so seven face buttons don't collide.
        #expect(r.node(id: "a.body") != nil)
        #expect(r.node(id: "a")?.node.states["pressed"]?.patch.first?.target == "#a.body")
        #expect(r.node(id: "z")?.node.kind == .button)
        #expect(r.node(id: "l")?.node.kind == .trigger)
    }

    @Test("A theme swaps tokens")
    func themeSwapsTokens() throws {
        let base = Skin2Resolver.resolve(try Skin2Document.fixture("gamecube-icube"), in: Self.portrait)
        let wii = Skin2Resolver.resolve(try Skin2Document.fixture("gamecube-icube", theme: "wii"), in: Self.portrait)
        #expect(base.node(id: "a")?.children.last?.node.color == Skin2Color(hex: "#FFFFFFE6"))
        #expect(wii.node(id: "a")?.children.last?.node.color == Skin2Color(hex: "#0000008C"))
        #expect(wii.theme == "wii")
    }

    @Test("The microphone button shows only with its flag, and takes no space without it")
    func microphoneIsFlagGated() throws {
        let doc = try Skin2Document.fixture("gamecube-icube")
        let without = Skin2Resolver.resolve(doc, in: Self.portrait)
        #expect(without.node(id: "mic") == nil)
        var env = Self.portrait
        env.flags = ["microphone"]
        let with = Skin2Resolver.resolve(doc, in: env)
        let mic = try #require(with.node(id: "mic"))
        let start = try #require(with.node(id: "start"))
        #expect(mic.frame.maxY < start.frame.minY)
        #expect(without.node(id: "start")?.frame == start.frame)
    }

    @Test("One skin lays out portrait, landscape and iPad without overlaps", arguments: [portrait, landscape, ipadLandscape, noInsets])
    func noOverlaps(env: Skin2Environment) throws {
        let r = Skin2Resolver.resolve(try Skin2Document.fixture("gamecube-icube"), in: env)
        #expect(r.warnings.isEmpty)
        let controls = r.controls
        #expect(controls.count == 11)
        for c in controls {
            #expect(env.canvasRect.contains(c.frame), "\(c.id ?? "?") off canvas: \(c.frame)")
            #expect(min(c.frame.width, c.frame.height) >= 44, "\(c.id ?? "?") under 44 pt")
        }
        for (i, a) in controls.enumerated() {
            for b in controls[(i + 1)...] {
                #expect(!(a.hitFrame!.overlaps(b.hitFrame!)), "\(a.id ?? "?") overlaps \(b.id ?? "?")")
            }
        }
        let screen = try #require(r.node(id: "screen"))
        if env.orientation == .portrait {
            #expect(abs(screen.exactFrame.width / screen.exactFrame.height - 4.0 / 3.0) < 0.01)
            #expect(screen.frame.minY == env.safeRect.minY)
            // Controls start below the picture (iCube's regionTop rule).
            let top = controls.map(\.frame.minY).min()!
            #expect(top > screen.frame.maxY, "controls overlap the picture")
        } else {
            #expect(screen.frame == env.canvasRect)
        }
    }

    @Test("Landscape: iCube's 70 pt diagonal and stack spacing")
    func landscapeDiagonal() throws {
        let r = Skin2Resolver.resolve(try Skin2Document.fixture("gamecube-icube"), in: Self.landscape)
        let dpad = try #require(r.node(id: "dpad")).exactFrame
        let stick = try #require(r.node(id: "mainStick")).exactFrame
        let unit = 393.0 / 390.0
        #expect(r.unit == unit)
        #expect(abs((dpad.midX - stick.midX) - 70 * unit) < 0.01)
        #expect(abs(dpad.minY - (stick.maxY + 8 * unit)) < 0.01)
        let cStick = try #require(r.node(id: "cStick")).exactFrame
        let face = try #require(r.node(id: "face")).exactFrame
        #expect(abs((face.midX - cStick.midX) - 70 * unit) < 0.01)
    }

    /// iCube: a column's outer edge is `max(safeInset, 8) + 8` from the canvas edge, its bottom
    /// `max(safeBottom, 8) + 6` (the spike only got this right where the safe inset was above 8).
    @Test("Edges follow iCube's max(safe, 8) + 8 rule", arguments: [portrait, landscape, noInsets])
    func edgeRule(env: Skin2Environment) throws {
        let r = Skin2Resolver.resolve(try Skin2Document.fixture("gamecube-icube"), in: env)
        let u = r.unit
        let left = try #require(r.node(id: "leftColumn")).exactFrame
        let right = try #require(r.node(id: "rightColumn")).exactFrame
        let s = env.safeArea
        // Split up so Xcode 26's type checker finishes in time.
        let leftInset: Double = left.minX
        let rightInset: Double = env.size.width - right.maxX
        let bottomInset: Double = env.size.height - left.maxY
        let expectedLeft: Double = max(s.left, 8 * u) + 8 * u
        let expectedRight: Double = max(s.right, 8 * u) + 8 * u
        let expectedBottom: Double = max(s.bottom, 8 * u) + 6 * u
        #expect(abs(leftInset - expectedLeft) < 0.001)
        #expect(abs(rightInset - expectedRight) < 0.001)
        #expect(abs(bottomInset - expectedBottom) < 0.001)
        if s.left == 0 { #expect(abs(left.minX - 16 * u) < 0.001) }
        if s.left == 59 { #expect(abs(left.minX - 67.0605) < 0.01) }
    }

    @Test("The d-pad arrows are four copies turning about the d-pad's centre")
    func dpadArrows() throws {
        let r = Skin2Resolver.resolve(try Skin2Document.fixture("gamecube-icube"), in: Self.portrait)
        let dpad = try #require(r.node(id: "dpad")).exactFrame
        let arrow = try #require(r.node(id: "arrow"))
        #expect(arrow.copies.count == 4)
        #expect(arrow.copies[0] == .identity)
        // Copy 1 (right): the arrow's centre, above the d-pad's centre, turns 90° clockwise to its right.
        let p = arrow.copies[1].apply(x: arrow.exactFrame.midX, y: arrow.exactFrame.midY)
        let up = dpad.midY - arrow.exactFrame.midY
        #expect(abs(p.x - (dpad.midX + up)) < 0.001)
        #expect(abs(p.y - dpad.midY) < 0.001)
        let thumb = try #require(r.node(id: "mainStick"))
        #expect(abs((thumb.travel ?? 0) - 0.35 * thumb.exactFrame.width) < 0.001)
    }
}
