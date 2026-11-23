import CoreGraphics
import Foundation
import SkinKit2Core
@testable import SkinKit2Render
import Testing

/// The resolver, validator and drawer recurse once per tree level, and their frames hold several copies of a
/// node. Secondary threads have 512 KB of stack, so the node has to stay small: growing it broke drawing five
/// levels deep in debug builds.
@Suite("Stack use")
struct StackDepthTests {
    @Test("A node stays small enough to recurse with")
    func nodeSize() {
        #expect(MemoryLayout<Skin2Node>.size <= 800, "Skin2Node is \(MemoryLayout<Skin2Node>.size) bytes: box large fields (Skin2Boxed)")
    }

    @Test("Eight nested groups resolve, validate and draw on a 512 KB stack")
    func deepTreeOnASmallStack() throws {
        var node = ##"{ "type": "shape", "shape": { "kind": "rect" }, "fills": [ { "type": "linear", "start": [0, 0], "end": [1, 1], "stops": [["#FF0000", 0], ["#0000FF", 1]] } ] }"##
        for i in 0..<8 { node = #"{ "type": "group", "id": "g\#(i)", "layout": { "inset": 1 }, "children": [ \#(node) ] }"# }
        let json = """
        { "formatVersion": "2.0", "requires": ["shapes.parametric", "paint.gradients"], "identifier": "deep", "name": "Deep",
          "gameTypes": ["com.rileytestut.delta.game.snes"], "reference": { "shortSide": 100, "minScale": 1, "maxScale": 1 },
          "root": { "type": "group", "children": [ \(node) ] } }
        """
        final class Box: @unchecked Sendable { var alpha: UInt8 = 0; var valid = false }
        let box = Box()
        let thread = Thread {
            let report = Skin2Validator.validate(data: Data(json.utf8))
            box.valid = report.isValid
            guard let doc = report.document else { return }
            let r = Skin2Resolver.resolve(doc, in: Skin2Environment(size: Skin2Size(width: 100, height: 100)))
            if let image = Skin2Renderer.image(r, scale: 1), let px = Pixels(image) { box.alpha = px[50, 50].a }
        }
        thread.stackSize = 512 * 1024
        thread.start()
        while !thread.isFinished { usleep(1000) }
        #expect(box.valid)
        #expect(box.alpha == 255)
    }
}
