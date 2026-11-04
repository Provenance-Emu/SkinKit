import XCTest
@testable import SkinCatalogKit

/// `addedAt` (the first commit of the entry's file, Provenance-Emu/skins#42) and `effectiveDate`,
/// the date the store's Recent sort and "new" sections order by (SkinKit#62).
final class SkinCatalogAddedAtTests: XCTestCase {

    private static let feed = Data("""
    { "version": 3, "skins": [
      { "id": "both", "name": "Both", "systems": ["gba"], "downloadURL": "https://example.com/a.deltaskin",
        "lastUpdated": "2025-09-23", "addedAt": "2026-04-02" },
      { "id": "added", "name": "Added only", "systems": ["gba"], "downloadURL": "https://example.com/b.deltaskin",
        "lastUpdated": null, "addedAt": "2026-05-10" },
      { "id": "old", "name": "Old feed", "systems": ["gba"], "downloadURL": "https://example.com/c.deltaskin" },
      { "id": "bad", "name": "Bad date", "systems": ["gba"], "downloadURL": "https://example.com/d.deltaskin",
        "addedAt": "2026-13-45" }
    ] }
    """.utf8)

    private func entries() throws -> [String: SkinCatalogEntry] {
        let catalog = try SkinCatalog.decode(Self.feed)
        XCTAssertEqual(catalog.skins.count, 4)
        return Dictionary(uniqueKeysWithValues: catalog.skins.map { ($0.id, $0) })
    }

    private func day(_ string: String) -> Date {
        SkinCatalogDates.parse(string)!
    }

    func testAddedAtDecodesAsABareDate() throws {
        let skins = try entries()
        XCTAssertEqual(skins["added"]?.addedAt, day("2026-05-10"))
        XCTAssertEqual(skins["both"]?.addedAt, day("2026-04-02"))
    }

    func testMissingOrUnparseableAddedAtIsNil() throws {
        let skins = try entries()
        XCTAssertNil(skins["old"]?.addedAt)
        XCTAssertNil(skins["bad"]?.addedAt)
        XCTAssertNil(skins["old"]?.effectiveDate)
    }

    func testEffectiveDatePrefersLastUpdated() throws {
        let skins = try entries()
        XCTAssertEqual(skins["both"]?.effectiveDate, day("2025-09-23"))
        XCTAssertEqual(skins["added"]?.effectiveDate, day("2026-05-10"))
    }

    func testFamilyEffectiveDateIsTheNewestMember() {
        func member(_ id: String, added: String?, updated: String? = nil) -> SkinCatalogEntry {
            SkinCatalogEntry(
                id: id, name: id, systems: ["gba"], downloadURL: URL(string: "https://example.com/\(id).deltaskin")!,
                lastUpdated: updated.map(day), addedAt: added.map(day), groupId: "g")
        }
        let family = SkinFamily(
            id: "g", groupId: "g", name: "Family",
            members: [member("a", added: "2026-01-01"), member("b", added: "2026-03-01"), member("c", added: nil)],
            labels: [:])
        XCTAssertEqual(family.effectiveDate, day("2026-03-01"))
        XCTAssertNil(family.lastUpdated)
    }

    func testRecentOrderPutsDatedEntriesFirst() throws {
        let sorted = try entries().values
            .sorted { ($0.effectiveDate ?? .distantPast) > ($1.effectiveDate ?? .distantPast) }
            .map(\.id)
        XCTAssertEqual(Array(sorted.prefix(2)), ["added", "both"])
    }
}
