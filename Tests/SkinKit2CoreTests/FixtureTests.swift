import Foundation
import Testing
@testable import SkinKit2Core

/// The shared fixtures (9.2) under `Tests/Format2Fixtures/<name>/`: each validates, matches the published schema,
/// and resolves on every trait set it bakes to exactly as `expected/<trait>.layout.json` records.
///
/// Recorded files: `<trait>.layout.json` (base), `<trait>.variant-<name>.layout.json` (every variant), and
/// `<trait>.theme-<name>.layout.json` only for themes whose tokens move something (otherwise the theme's layout
/// is the base layout). `SKIN2_RECORD=1 xcrun swift test --filter SkinKit2CoreTests` rewrites them.
@Suite("Format 2.0 fixtures")
struct FixtureTests {
    @Test("The fixture set is complete")
    func fixtureSet() {
        #expect(Skin2Paths.fixtureNames == ["dual-screen", "gamecube-icube", "layout", "stacks-grids", "variants"])
    }

    @Test("Validates with no errors or warnings", arguments: Skin2Paths.fixtureNames)
    func validates(_ name: String) throws {
        let report = Skin2Validator.validate(data: try Skin2Paths.skinData(name))
        #expect(report.errors.isEmpty, "\(report.errors.map(\.description).joined(separator: "\n"))")
        #expect(report.warnings.isEmpty, "\(report.warnings.map(\.description).joined(separator: "\n"))")
    }

    @Test("Matches the JSON Schema as written and after expansion", arguments: Skin2Paths.fixtureNames)
    func matchesSchema(_ name: String) throws {
        let schema = SchemaValidator(root: try Skin2JSON.parse(Data(contentsOf: Skin2Paths.schema)))
        let source = try Skin2JSON.parse(Skin2Paths.skinData(name))
        #expect(schema.errors(source) == [])
        let pre = try Skin2Preprocessor(source: source)
        let base = try Skin2Document.fixture(name)
        var expansions = [try pre.expand()]
        for theme in base.themeNames { expansions.append(try pre.expand(theme: theme)) }
        for variant in base.variants.keys.sorted() { expansions.append(try pre.expand(variant: variant)) }
        for expanded in expansions { #expect(schema.errors(expanded) == []) }
    }

    @Test("Resolves to the recorded layout on every bake trait set", arguments: Skin2Paths.fixtureNames)
    func layoutMatchesRecording(_ name: String) throws {
        let generated = try Self.records(name)
        let dir = Skin2Paths.fixtures.appendingPathComponent("\(name)/expected", isDirectory: true)
        let fm = FileManager.default
        let existing = Set(((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".layout.json") })

        if Skin2Paths.recording {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for stale in existing.subtracting(generated.keys) { try fm.removeItem(at: dir.appendingPathComponent(stale)) }
            for (file, data) in generated { try data.write(to: dir.appendingPathComponent(file)) }
            Issue.record("Recorded \(generated.count) layout files for \(name); run again without SKIN2_RECORD")
            return
        }

        #expect(existing == Set(generated.keys), "recorded files differ: run with SKIN2_RECORD=1 and review the diff")
        let decoder = JSONDecoder()
        for (file, data) in generated.sorted(by: { $0.key < $1.key }) where existing.contains(file) {
            let expected = try decoder.decode(Skin2LayoutRecord.self, from: Data(contentsOf: dir.appendingPathComponent(file)))
            let actual = try decoder.decode(Skin2LayoutRecord.self, from: data)
            if expected != actual {
                let firstDiff = zip(expected.nodes, actual.nodes).first { $0 != $1 }
                Issue.record("\(name)/\(file) differs; first node: expected \(String(describing: firstDiff?.0)), got \(String(describing: firstDiff?.1))")
            }
        }
    }

    /// File name → bytes for every layout this fixture records.
    static func records(_ name: String) throws -> [String: Data] {
        let base = try Skin2Document.fixture(name)
        var out: [String: Data] = [:]
        for trait in Skin2TraitSet.sets(for: base) {
            let baseRecord = Skin2LayoutRecord(Skin2Resolver.resolve(base, in: trait.environment), trait: trait.name)
            out["\(trait.name).layout.json"] = try baseRecord.encoded()
            for variant in base.variants.keys.sorted() {
                let doc = try Skin2Document.fixture(name, variant: variant)
                out["\(trait.name).variant-\(variant).layout.json"] =
                    try Skin2LayoutRecord(Skin2Resolver.resolve(doc, in: trait.environment), trait: trait.name).encoded()
            }
            for theme in base.themeNames {
                let doc = try Skin2Document.fixture(name, theme: theme)
                let record = Skin2LayoutRecord(Skin2Resolver.resolve(doc, in: trait.environment), trait: trait.name)
                if record.nodes != baseRecord.nodes { out["\(trait.name).theme-\(theme).layout.json"] = try record.encoded() }
            }
        }
        return out
    }
}
