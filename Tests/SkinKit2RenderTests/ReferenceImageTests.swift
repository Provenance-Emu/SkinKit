import CoreGraphics
import Foundation
import SkinKit2Core
@testable import SkinKit2Render
import Testing

/// The reference images (9.2, 9.3): every fixture under `Tests/Format2Fixtures/` rendered at 2× on each trait set
/// it bakes to, per variant, theme and state set, and compared with `expected/*@2x.png` per pixel.
///
/// At most 0.25 % of pixels may differ by more than 10 % in a channel (1.0 % for `effects`, whose blur kernels
/// differ between renderers). `SKIN2_RECORD=1 xcrun swift test --filter SkinKit2RenderTests` rewrites the images;
/// review them before committing.
@Suite("Format 2.0 reference images")
struct ReferenceImageTests {
    static func tolerance(_ fixture: String) -> Double { fixture == "effects" ? 0.01 : 0.0025 }

    @Test("The renderer supports every feature the fixtures require", arguments: RenderPaths.fixtureNames)
    func supportsFixture(_ name: String) throws {
        let doc = try Skin2Document.load(data: RenderPaths.skinData(name))
        #expect(SkinKit2Render.supports(doc.requires), "unsupported: \(Set(doc.requires).subtracting(SkinKit2Render.supportedFeatures))")
    }

    @Test("Renders to the recorded reference images", arguments: RenderPaths.fixtureNames)
    func matchesReferences(_ name: String) throws {
        let references = try ReferenceImage.all(name)
        let dir = RenderPaths.expected(name)
        let fm = FileManager.default
        let existing = Set(((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix("@2x.png") })
        let generated = Set(references.map(\.file))

        if RenderPaths.recording {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for stale in existing.subtracting(generated) { try fm.removeItem(at: dir.appendingPathComponent(stale)) }
            for ref in references {
                guard let data = PNG.data(try ref.render(name)) else { throw RenderTestError("could not encode \(ref.file)") }
                try data.write(to: dir.appendingPathComponent(ref.file))
            }
            Issue.record("Recorded \(references.count) reference images for \(name); run again without SKIN2_RECORD")
            return
        }

        #expect(existing == generated, "reference images differ from the set to render: run with SKIN2_RECORD=1 and review")
        for ref in references where existing.contains(ref.file) {
            let actual = try ref.render(name)
            guard let expectedImage = PNG.read(dir.appendingPathComponent(ref.file)), let expected = Pixels(expectedImage),
                  let got = Pixels(actual) else {
                Issue.record("\(name)/\(ref.file): could not read")
                continue
            }
            let (fraction, diff) = got.difference(expected)
            if fraction > Self.tolerance(name) {
                let out = RenderPaths.failures.appendingPathComponent(name, isDirectory: true)
                try? fm.createDirectory(at: out, withIntermediateDirectories: true)
                let stem = String(ref.file.dropLast(".png".count))
                try? PNG.data(actual)?.write(to: out.appendingPathComponent(stem + ".actual.png"))
                if let diff { try? PNG.data(diff)?.write(to: out.appendingPathComponent(stem + ".diff.png")) }
                Issue.record("\(name)/\(ref.file): \(String(format: "%.3f", fraction * 100)) % of pixels differ (limit \(Self.tolerance(name) * 100) %); actual and diff in \(out.path)")
            }
        }
    }
}
