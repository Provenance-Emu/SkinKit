import Foundation

/// Fixtures for creator profiles (SkinKit#60):
///
/// - `creators.json`: a `creators.json` as the catalog build publishes it (creator profiles spec §2),
///   plus hand-written records that exercise lenient decoding. Slugs: `starvingartist` (claimed, full
///   profile), `nostromocrew01` (claimed by login only), `janza` (unclaimed, avatar only), `held`
///   (`hidden: true`), `typedrift` (every field the wrong type), `dupe-alias` (repeats an alias of
///   `starvingartist`). Two records have no usable slug and are dropped.
/// - `creator-catalog.json`: nine entries around the spec §6 override case ("ClearDoom by
///   NostromoCrew01" credits `starvingartist`).
/// - `author-slugs.json`: every distinct `author` in the live catalog (2026-11-04) with the slug the
///   Python `slugify()` produces for it, plus edge cases.
enum SkinCreatorFixture {
    static let droppedCreatorCount = 2
    static let creatorCount = 6

    static var creatorsData: Data {
        data("creators")
    }

    static var catalogData: Data {
        data("creator-catalog")
    }

    struct SlugCase: Decodable {
        let author: String
        let slug: String
    }

    struct SlugFixture: Decodable {
        let cases: [SlugCase]
    }

    static func slugCases() throws -> [SlugCase] {
        try JSONDecoder().decode(SlugFixture.self, from: data("author-slugs")).cases
    }

    private static func data(_ name: String) -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
              let data = try? Data(contentsOf: url)
        else {
            fatalError("Fixtures/\(name).json is missing from the test bundle")
        }
        return data
    }
}
