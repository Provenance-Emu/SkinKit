import XCTest
@testable import SkinCatalogKit

/// What the creator profile sheet lists (creator profiles spec §7): the creator's skins as whole
/// variant families, cut by the host store's policy, and the creators behind a family card's credit.
final class SkinCreatorProfileFamiliesTests: XCTestCase {
    private var index: SkinCreatorIndex!

    override func setUpWithError() throws {
        index = try SkinCreatorIndex.decode(SkinCreatorFixture.creatorsData)
    }

    private func entry(
        _ id: String,
        author: String?,
        creator: String? = nil,
        systems: [String],
        ext: String = "deltaskin",
        tags: [String] = [],
        groupId: String? = nil,
        groupOrder: Int? = nil,
        downloads: Int? = nil,
        added: Date? = nil
    ) -> SkinCatalogEntry {
        SkinCatalogEntry(
            id: id,
            name: groupId == nil ? "Skin \(id)" : "Group Skin — \(id)",
            author: author,
            creatorSlug: creator,
            systems: systems,
            downloadURL: URL(string: "https://example.com/\(id).\(ext)")!,
            tags: tags,
            downloadCount: downloads,
            addedAt: added,
            groupId: groupId,
            groupOrder: groupOrder
        )
    }

    private func creator(_ slug: String) throws -> SkinCreator {
        try XCTUnwrap(index.creator(for: slug), "missing \(slug)")
    }

    private func ids(_ families: [SkinFamily]) -> [[String]] {
        families.map { $0.members.map(\.id) }
    }

    /// A policy that pins visibility so the tests never read the app-wide setting.
    private func policy(
        _ sections: [SkinStoreSection],
        showTest: Bool = false,
        showMature: Bool = false
    ) -> SkinStorePolicy {
        SkinStorePolicy(
            sections: sections,
            visibility: SkinContentVisibility(showTestSkins: showTest, showMatureSkins: showMature)
        )
    }

    private static let everything = SkinStoreSection(
        id: "all", title: "All", systemCodes: ["gba", "psx", "dreamcast", "gamecube", "nes", "snes"]
    )

    // MARK: - Override

    /// The spec §6 case on the fixture catalog: "ClearDoom" credits `starvingartist` but belongs to
    /// `nostromocrew01`, and the profile of each lists exactly its own.
    func testOverrideMovesTheSkinBetweenProfiles() throws {
        let catalog = try SkinCatalog.decode(SkinCreatorFixture.catalogData)
        let allSystems = [policy([SkinStoreSection(id: "all", title: "All", systemCodes: ["psx", "dreamcast"])])]

        for policy in [nil] + allSystems.map(Optional.some) {
            let starving = index.families(by: try creator("starvingartist"), in: catalog, policy: policy)
            XCTAssertEqual(Set(ids(starving).flatMap { $0 }), ["starving-own", "starving-no-key"])

            let nostromo = index.families(by: try creator("nostromocrew01"), in: catalog, policy: policy)
            XCTAssertEqual(ids(nostromo), [["clear-doom"]])
        }
    }

    /// An author nobody listed still gets a profile with their skins.
    func testUnlistedAuthorsSkinsAreFound() throws {
        let catalog = try SkinCatalog.decode(SkinCreatorFixture.catalogData)
        let unlisted = try XCTUnwrap(index.creator(for: try XCTUnwrap(catalog.skins.first { $0.id == "unlisted-author" })))
        XCTAssertEqual(unlisted.slug, "brand-new-person")
        XCTAssertFalse(unlisted.isClaimed)
        XCTAssertEqual(ids(index.families(by: unlisted, in: catalog)), [["unlisted-author"]])
    }

    // MARK: - Policy

    func testPolicyKeepsOnlyWhatTheHostCanInstall() throws {
        let catalog = SkinCatalog(skins: [
            entry("gc", author: "starvingartist", systems: ["gamecube"]),
            entry("psx", author: "starvingartist", systems: ["psx"]),
            entry("dc", author: "starvingartist", systems: ["dreamcast"]),
            entry("zip", author: "starvingartist", systems: ["gamecube"], ext: "zip"),
        ])
        let starving = try creator("starvingartist")

        XCTAssertEqual(ids(index.families(by: starving, in: catalog, policy: .iCube)), [["gc"]],
                       "iCube lists the GameCube skin; psx and dreamcast have no shelf, and .zip is not installable")
        XCTAssertEqual(Set(ids(index.families(by: starving, in: catalog, policy: .iFly)).flatMap { $0 }),
                       ["gc", "psx", "dc"], "iFly takes dreamcast on its own shelf and the rest on From Other Systems; .zip still drops")
        XCTAssertEqual(ids(index.families(by: starving, in: catalog)).flatMap { $0 }.count, 4,
                       "no policy means visibility only, like the plain browser")
    }

    func testAPolicyThatHidesEverythingYieldsAnEmptyList() throws {
        let catalog = SkinCatalog(skins: [entry("dc", author: "starvingartist", systems: ["dreamcast"])])
        XCTAssertTrue(index.families(by: try creator("starvingartist"), in: catalog, policy: .iCube).isEmpty)
        XCTAssertTrue(SkinCreatorProfileSummary(families: []).isEmpty)
    }

    func testHiddenEntryIdsAreHonoured() throws {
        let catalog = SkinCatalog(skins: [
            entry("keep", author: "starvingartist", systems: ["gba"]),
            entry("drop", author: "starvingartist", systems: ["gba"]),
        ])
        var hiding = policy([Self.everything])
        hiding.hiddenEntryIds = ["drop"]
        XCTAssertEqual(ids(index.families(by: try creator("starvingartist"), in: catalog, policy: hiding)), [["keep"]])
    }

    // MARK: - Visibility

    func testSampleAndMatureEntriesAreHiddenBeforeGrouping() throws {
        let catalog = SkinCatalog(skins: [
            entry("shown-1", author: "starvingartist", systems: ["gba"], groupId: "g", groupOrder: 1),
            entry("sample", author: "starvingartist", systems: ["gba"], tags: ["Sample"], groupId: "g", groupOrder: 2),
            entry("adult", author: "starvingartist", systems: ["gba"], tags: ["mature"]),
        ])
        let starving = try creator("starvingartist")

        let hidden = index.families(by: starving, in: catalog, policy: policy([Self.everything]))
        XCTAssertEqual(ids(hidden), [["shown-1"]], "a hidden member never appears inside a family card")

        let all = index.families(by: starving, in: catalog, policy: policy([Self.everything], showTest: true, showMature: true))
        XCTAssertEqual(Set(ids(all).flatMap { $0 }), ["shown-1", "sample", "adult"])
    }

    func testNoPolicyReadsTheAppWideVisibility() throws {
        let catalog = SkinCatalog(skins: [
            entry("plain", author: "starvingartist", systems: ["gba"]),
            entry("adult", author: "starvingartist", systems: ["gba"], tags: ["mature"]),
        ])
        let previous = SkinContentVisibility.current
        defer { SkinContentVisibility.current = previous }
        let starving = try creator("starvingartist")

        SkinContentVisibility.current = SkinContentVisibility()
        XCTAssertEqual(ids(index.families(by: starving, in: catalog)).flatMap { $0 }, ["plain"])
        SkinContentVisibility.current = SkinContentVisibility(showMatureSkins: true)
        XCTAssertEqual(Set(ids(index.families(by: starving, in: catalog)).flatMap { $0 }), ["plain", "adult"])
    }

    // MARK: - Families

    /// A family with a variant by someone else stays whole under both creators, each member keeping
    /// its own credit, and its label does not depend on whose profile is open.
    func testMixedAuthorFamilyIsReturnedWholeUnderBothCreators() throws {
        let catalog = SkinCatalog(skins: [
            entry("a", author: "starvingartist", systems: ["gba"], groupId: "g", groupOrder: 1),
            entry("b", author: "JanZa", creator: "janza", systems: ["gba"], groupId: "g", groupOrder: 2),
            entry("solo", author: "JanZa", creator: "janza", systems: ["gba"]),
        ])
        let starving = index.families(by: try creator("starvingartist"), in: catalog)
        XCTAssertEqual(ids(starving), [["a", "b"]])
        XCTAssertEqual(starving[0].authors, ["starvingartist", "JanZa"])

        let janza = index.families(by: try creator("janza"), in: catalog)
        XCTAssertEqual(Set(janza.map(\.id)), ["group:g", "entry:solo"])
        XCTAssertEqual(janza.first { $0.id == "group:g" }?.members.map(\.id), ["a", "b"])
        XCTAssertEqual(starving[0].labels, janza.first { $0.id == "group:g" }?.labels)
    }

    func testFamiliesAreNewestFirstThenCatalogOrder() throws {
        let day: TimeInterval = 86_400
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let catalog = SkinCatalog(skins: [
            entry("undated-1", author: "starvingartist", systems: ["gba"]),
            entry("old", author: "starvingartist", systems: ["gba"], added: base),
            entry("new", author: "starvingartist", systems: ["gba"], added: base.addingTimeInterval(10 * day)),
            entry("undated-2", author: "starvingartist", systems: ["gba"]),
            entry("mid", author: "starvingartist", systems: ["gba"], added: base.addingTimeInterval(5 * day)),
        ])
        XCTAssertEqual(
            ids(index.families(by: try creator("starvingartist"), in: catalog)).flatMap { $0 },
            ["new", "mid", "old", "undated-1", "undated-2"]
        )
    }

    // MARK: - Creators behind a card

    /// The credit says "by starvingartist" but the entry belongs to nostromocrew01, so the card's
    /// button must open nostromocrew01 (spec §6).
    func testCreatorsInFamilyFollowTheOverrideNotTheAuthorString() throws {
        let catalog = try SkinCatalog.decode(SkinCreatorFixture.catalogData)
        let family = try XCTUnwrap(catalog.families.first { $0.primary.id == "clear-doom" })
        XCTAssertEqual(family.authors, ["starvingartist"])
        XCTAssertEqual(index.creators(in: family).map(\.slug), ["nostromocrew01"])
    }

    func testCreatorsInFamilyAreDistinctAndInMemberOrder() throws {
        let catalog = SkinCatalog(skins: [
            entry("1", author: "JanZa", systems: ["gba"], groupId: "g", groupOrder: 1),
            entry("2", author: "starvingartist", systems: ["gba"], groupId: "g", groupOrder: 2),
            entry("3", author: "JanZa", systems: ["gba"], groupId: "g", groupOrder: 3),
            entry("4", author: nil, systems: ["gba"], groupId: "g", groupOrder: 4),
        ])
        let family = try XCTUnwrap(catalog.families.first)
        XCTAssertEqual(index.creators(in: family).map(\.slug), ["janza", "starvingartist"])

        let uncredited = SkinFamily(
            id: "entry:x", groupId: nil, name: "X",
            members: [entry("x", author: nil, systems: ["gba"])], labels: [:]
        )
        XCTAssertTrue(index.creators(in: uncredited).isEmpty)
    }

    // MARK: - Summary

    func testSummaryCountsFilesVariantsDownloadsAndSystems() {
        let families = SkinFamily.families(from: [
            entry("a", author: "x", systems: ["GBA", "Unknown"], groupId: "g", groupOrder: 1, downloads: 10),
            entry("b", author: "x", systems: ["gba", "nes"], groupId: "g", groupOrder: 2, downloads: 5),
            entry("c", author: "x", systems: ["snes", "unofficial"], downloads: nil),
        ])
        let summary = SkinCreatorProfileSummary(families: families)
        XCTAssertEqual(summary.skinCount, 3)
        XCTAssertEqual(summary.variantCount, 3)
        XCTAssertEqual(summary.downloadCount, 15)
        XCTAssertEqual(summary.systemCodes, ["gba", "nes", "snes"])
        XCTAssertFalse(summary.isEmpty)
    }
}
