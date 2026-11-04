import XCTest
@testable import SkinCatalogKit

/// `SkinCreatorSlug` against the Python `slugify()` it ports (`author-slugs.json` holds the Python's
/// output for every author string in the catalog on 2026-11-04).
final class SkinCreatorSlugTests: XCTestCase {
    func testMatchesPythonSlugifyForEveryCatalogAuthor() throws {
        let cases = try SkinCreatorFixture.slugCases()
        XCTAssertGreaterThanOrEqual(cases.count, 149, "the fixture lost authors")
        for item in cases {
            XCTAssertEqual(SkinCreatorSlug.make(from: item.author), item.slug, "author: \(item.author)")
        }
    }

    func testHandPickedBehaviour() {
        XCTAssertEqual(SkinCreatorSlug.make(from: "felix#6506"), "felix-6506")
        XCTAssertEqual(SkinCreatorSlug.make(from: "  Spaced  Out  "), "spaced-out")
        XCTAssertEqual(SkinCreatorSlug.make(from: "starvingartist"), "starvingartist")
        XCTAssertEqual(SkinCreatorSlug.make(from: "Dr. Who? (v2)"), "dr-who-v2")
    }

    func testNonASCIIIsSeparatorNotTransliterated() {
        // Python lowercases and then drops everything outside a-z0-9, so "ü" is a separator.
        XCTAssertEqual(SkinCreatorSlug.make(from: "Müller"), "m-ller")
        XCTAssertEqual(SkinCreatorSlug.make(from: "日本語のみ"), "")
        XCTAssertEqual(SkinCreatorSlug.make(from: ""), "")
        XCTAssertEqual(SkinCreatorSlug.make(from: "---"), "")
    }

    func testTruncatesAfterStrippingLikePython() {
        let long = String(repeating: "a", count: 60)
        XCTAssertEqual(SkinCreatorSlug.make(from: long).count, SkinCreatorSlug.maxLength)
        // 25 "x-" pairs end the 50-character window on a hyphen; Python does not re-strip.
        let slug = SkinCreatorSlug.make(from: String(repeating: "x-", count: 30))
        XCTAssertEqual(slug.count, 50)
        XCTAssertTrue(slug.hasSuffix("-"))
    }

    func testOutputAlphabet() throws {
        for item in try SkinCreatorFixture.slugCases() {
            let slug = SkinCreatorSlug.make(from: item.author)
            XCTAssertTrue(
                slug.unicodeScalars.allSatisfy { ("a" ... "z").contains($0) || ("0" ... "9").contains($0) || $0 == "-" },
                slug
            )
        }
    }
}
