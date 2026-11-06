import XCTest
@testable import SkinCatalogKit

/// The badge vocabulary (gamification spec §1) and how creator badges resolve against it (SkinKit#69).
final class SkinBadgeTests: XCTestCase {
    private let catalog = SkinBadgeCatalog.bundled

    // MARK: - The bundled file

    func testBundledFileLoadsAndIdsAreUnique() throws {
        let url = try XCTUnwrap(SkinBadgeCatalog.bundledURL, "Resources/badges.json is not bundled")
        let raw = try JSONDecoder().decode(RawFile.self, from: Data(contentsOf: url))
        XCTAssertEqual(catalog.version, 1)
        XCTAssertEqual(catalog.definitions.count, raw.badges.count, "a badge was dropped or duplicated")
        XCTAssertEqual(Set(catalog.definitions.map(\.id)).count, catalog.definitions.count)
    }

    func testEveryBundledBadgeIsLabelledAndMatchesItsAudiencePrefix() {
        for badge in catalog.definitions {
            XCTAssertNotNil(badge.audience, badge.id)
            XCTAssertTrue(badge.id.hasPrefix("\(badge.audience?.rawValue ?? "?")."), badge.id)
            XCTAssertFalse(badge.title.isEmpty, badge.id)
            XCTAssertFalse(badge.detail?.isEmpty ?? true, "\(badge.id) has no description")
            XCTAssertFalse(badge.symbol?.isEmpty ?? true, "\(badge.id) has no symbol")
        }
    }

    func testSpecBadgesArePresent() {
        let creatorIDs: Set = [
            "creator.first-release", "creator.systems.3", "creator.systems.5", "creator.systems.10",
            "creator.family-builder", "creator.completionist", "creator.dual-screen", "creator.veteran",
            "creator.reach.1", "creator.reach.2", "creator.reach.3", "creator.claimed", "creator.open-source",
        ]
        let userIDs: Set = [
            "user.first-install", "user.systems.3", "user.systems.5", "user.systems.10", "user.themes.1",
            "user.alt-layout.1", "user.family.1", "user.creators.5", "user.follow.1",
        ]
        XCTAssertEqual(Set(catalog.definitions(for: .creator).map(\.id)), creatorIDs)
        XCTAssertEqual(Set(catalog.definitions(for: .user).map(\.id)), userIDs)
        XCTAssertEqual(catalog.definition(for: "user.systems.3")?.title, "Explorer")
        XCTAssertEqual(catalog.definition(for: "user.systems.3")?.symbol, "map")
    }

    func testReachBadgesNeverSayDownloads() {
        for badge in catalog.definitions(for: .creator) where badge.id.hasPrefix("creator.reach.") {
            XCTAssertFalse((badge.title + (badge.detail ?? "")).localizedCaseInsensitiveContains("download"), badge.id)
        }
    }

    /// The skins repo owns `badges.json`; this copy must not drift from it. `Fixtures/skins-badges.json`
    /// is the skins repo's file. Refresh it (and `Resources/badges.json`) together when it changes.
    func testBundledFileMatchesTheSkinsRepoCopy() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "skins-badges", withExtension: "json", subdirectory: "Fixtures")
        )
        let skins = try SkinBadgeCatalog(data: Data(contentsOf: url))
        XCTAssertEqual(catalog.version, skins.version, "badges.json version differs from the skins repo")
        XCTAssertEqual(catalog.definitions, skins.definitions, "badges.json differs from the skins repo")
    }

    // MARK: - Resolving

    func testUnknownIDResolvesToAGenericBadgeWithATitle() {
        let badge = catalog.resolve("creator.fancy-new-thing")
        XCTAssertEqual(badge.title, "Fancy new thing")
        XCTAssertEqual(badge.symbol, SkinBadgeCatalog.genericSymbol)
        XCTAssertNil(badge.detail)
        XCTAssertEqual(badge.audience, .creator)
        XCTAssertNil(catalog.definition(for: "creator.fancy-new-thing"))

        XCTAssertEqual(catalog.resolve("creator.systems.20").title, "Systems 20")
        XCTAssertEqual(catalog.resolve("whatever").title, "Whatever")
        XCTAssertNil(catalog.resolve("whatever").audience)
    }

    func testDegenerateIDsStillGetATitle() {
        XCTAssertFalse(catalog.resolve("").title.isEmpty)
        XCTAssertFalse(catalog.resolve("creator.").title.isEmpty)
        XCTAssertFalse(catalog.resolve("...").title.isEmpty)
        XCTAssertFalse(catalog.resolve("---").title.isEmpty)
        XCTAssertFalse(SkinBadgeCatalog().resolve("user.x").title.isEmpty, "an empty catalog still resolves")
    }

    func testKnownIDResolvesFromTheBundle() {
        let badge = catalog.resolve(SkinCreatorBadge(id: "creator.claimed"))
        XCTAssertEqual(badge.title, "Claimed profile")
        XCTAssertEqual(badge.symbol, "checkmark.seal.fill")
        XCTAssertNotNil(badge.detail)
    }

    func testLabelsOnTheCreatorRecordWinOverTheBundle() {
        let badge = catalog.resolve(
            SkinCreatorBadge(id: "creator.claimed", title: "Verified", detail: "Hand-labelled", symbol: "star", tier: 2)
        )
        XCTAssertEqual(badge.title, "Verified")
        XCTAssertEqual(badge.detail, "Hand-labelled")
        XCTAssertEqual(badge.symbol, "star")
        XCTAssertEqual(badge.tier, 2)

        let blank = catalog.resolve(SkinCreatorBadge(id: "creator.claimed", title: "  ", symbol: ""))
        XCTAssertEqual(blank.title, "Claimed profile", "blank labels fall through to the bundle")
        XCTAssertEqual(blank.symbol, "checkmark.seal.fill")
    }

    func testUnknownCreatorBadgeKeepsItsOwnLabels() {
        let labelled = catalog.resolve(SkinCreatorBadge(id: "creator.new", title: "Brand new", symbol: "bolt"))
        XCTAssertEqual(labelled.title, "Brand new")
        XCTAssertEqual(labelled.symbol, "bolt")
        let bare = catalog.resolve(SkinCreatorBadge(id: "creator.new"))
        XCTAssertEqual(bare.title, "New")
        XCTAssertEqual(bare.symbol, SkinBadgeCatalog.genericSymbol)
    }

    // MARK: - Tiers

    func testHighestTierOfEachStemWins() {
        XCTAssertEqual(
            SkinBadgeCatalog.highestTiers(of: [
                "creator.first-release", "creator.systems.3", "creator.systems.10", "creator.systems.5",
                "creator.reach.1", "creator.reach.2", "creator.claimed",
            ]),
            ["creator.first-release", "creator.systems.10", "creator.reach.2", "creator.claimed"]
        )
        // Numeric, not lexical: 10 beats 5 and 9.
        XCTAssertEqual(SkinBadgeCatalog.highestTiers(of: ["a.n.9", "a.n.10", "a.n.5"]), ["a.n.10"])
        // Different stems are independent; duplicates collapse.
        XCTAssertEqual(
            SkinBadgeCatalog.highestTiers(of: ["user.systems.3", "creator.systems.5", "user.systems.3"]),
            ["user.systems.3", "creator.systems.5"]
        )
        XCTAssertEqual(SkinBadgeCatalog.highestTiers(of: []), [])
    }

    func testStemAndThreshold() {
        let tiered = SkinBadgeDefinition(id: "creator.systems.10")
        XCTAssertEqual(tiered.stem, "creator.systems")
        XCTAssertEqual(tiered.threshold, 10)
        let plain = SkinBadgeDefinition(id: "creator.claimed")
        XCTAssertEqual(plain.stem, "creator.claimed")
        XCTAssertNil(plain.threshold)
        XCTAssertNil(SkinBadgeDefinition(id: "creator.v2x").threshold)
        XCTAssertNil(SkinBadgeDefinition(id: "creator.").threshold)
    }

    func testDisplayBadgesForACreator() throws {
        let data = Data("""
        {"slug":"c","badges":[
          "creator.systems.3",
          {"id":"creator.systems.5","earnedAt":"2026-01-01"},
          "creator.brand-new-badge",
          {"id":"creator.claimed","title":"Verified"}
        ]}
        """.utf8)
        let creator = try JSONDecoder().decode(SkinCreator.self, from: data)
        let shown = catalog.displayBadges(for: creator)
        XCTAssertEqual(shown.map(\.id), ["creator.systems.5", "creator.brand-new-badge", "creator.claimed"])
        XCTAssertEqual(shown.map(\.title), ["Five systems", "Brand new badge", "Verified"])
    }

    // MARK: - Lenient decoding

    func testDefinitionDecodesLeniently() throws {
        let data = Data(#"""
        {"id":" user.x.1 ","for":"nobody","title":7,"description":"Does a thing","symbol":["no"],"tier":"high"}
        """#.utf8)
        let badge = try JSONDecoder().decode(SkinBadgeDefinition.self, from: data)
        XCTAssertEqual(badge.id, "user.x.1")
        XCTAssertEqual(badge.audience, .user, "an unknown audience falls back to the id prefix")
        XCTAssertEqual(badge.title, "X 1", "a mistyped title falls back to one derived from the id")
        XCTAssertEqual(badge.detail, "Does a thing")
        XCTAssertNil(badge.symbol)
        XCTAssertNil(badge.tier)

        XCTAssertThrowsError(try JSONDecoder().decode(SkinBadgeDefinition.self, from: Data(#"{"title":"x"}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(SkinBadgeDefinition.self, from: Data(#"{"id":"  "}"#.utf8)))
    }

    func testCatalogSurvivesBadEntriesAndUnknownKeys() throws {
        let data = Data("""
        {"version":2,"future":true,"badges":[
          {"id":"user.a.1","for":"user","title":"A","extra":{"x":1}},
          {"title":"no id"},
          5,
          {"id":"user.a.1","title":"duplicate"},
          {"id":"creator.b","for":"creator","title":"B"}
        ]}
        """.utf8)
        let parsed = try SkinBadgeCatalog(data: data)
        XCTAssertEqual(parsed.version, 2)
        XCTAssertEqual(parsed.definitions.map(\.id), ["user.a.1", "creator.b"])
        XCTAssertEqual(parsed.definition(for: "user.a.1")?.title, "A", "the first definition of an id wins")

        let noBadges = try SkinBadgeCatalog(data: Data(#"{"version":"x"}"#.utf8))
        XCTAssertEqual(noBadges.version, 0)
        XCTAssertTrue(noBadges.definitions.isEmpty)
        XCTAssertThrowsError(try SkinBadgeCatalog(data: Data("[]".utf8)))
    }

    func testCreatorStatsAndBadgesSurviveOddTypes() throws {
        // Stats of the wrong shape and a badge list with junk in it must not cost the creator.
        let weirdStats = try JSONDecoder().decode(
            SkinCreator.self, from: Data(#"{"slug":"a","stats":"lots","badges":[null,3,"creator.claimed",{"id":9}]}"#.utf8)
        )
        XCTAssertNil(weirdStats.stats)
        XCTAssertEqual(weirdStats.badges.map(\.id), ["creator.claimed"])

        let oddFields = try JSONDecoder().decode(
            SkinCreatorStats.self,
            from: Data(#"{"releases":3,"reachTier":"high","dualScreen":null,"lastAddedAt":"not a date","extra":1}"#.utf8)
        )
        XCTAssertEqual(oddFields.releases, 3)
        XCTAssertNil(oddFields.reachTier)
        XCTAssertNil(oddFields.dualScreen)
        XCTAssertNil(oddFields.lastAddedAt)

        let notObjects = try JSONDecoder().decode(
            SkinCreator.self, from: Data(#"{"slug":"a","badges":"creator.claimed"}"#.utf8)
        )
        XCTAssertTrue(notObjects.badges.isEmpty)
    }

    private struct RawFile: Decodable {
        var badges: [RawBadge]
    }

    private struct RawBadge: Decodable {
        var id: String
    }
}
