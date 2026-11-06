import XCTest
@testable import SkinCatalogKit

/// The "New from creators you follow" shelf (follow creators spec §3): followed, installable, not
/// installed, family-collapsed, newest first, with the unseen count.
final class SkinFollowFeedTests: XCTestCase {
    private var index: SkinCreatorIndex!

    override func setUpWithError() throws {
        index = try SkinCreatorIndex.decode(SkinCreatorFixture.creatorsData)
    }

    private static func date(_ iso: String) -> Date {
        SkinCatalogDates.parse(iso)!
    }

    private func entry(
        _ id: String,
        author: String?,
        creator: String? = nil,
        systems: [String] = ["gba"],
        ext: String = "deltaskin",
        tags: [String] = [],
        groupId: String? = nil,
        groupOrder: Int? = nil,
        added: String? = nil,
        updated: String? = nil
    ) -> SkinCatalogEntry {
        SkinCatalogEntry(
            id: id,
            name: groupId == nil ? "Skin \(id)" : "Group Skin — \(id)",
            author: author,
            creatorSlug: creator,
            systems: systems,
            downloadURL: URL(string: "https://example.com/\(id).\(ext)")!,
            tags: tags,
            lastUpdated: updated.map(Self.date),
            addedAt: added.map(Self.date),
            groupId: groupId,
            groupOrder: groupOrder
        )
    }

    /// A policy that pins visibility so the tests never read the app-wide setting.
    private func policy(showTest: Bool = false, showMature: Bool = false) -> SkinStorePolicy {
        SkinStorePolicy(
            sections: [SkinStoreSection(id: "all", title: "All", systemCodes: ["gba", "psx", "dreamcast", "gamecube"])],
            visibility: SkinContentVisibility(showTestSkins: showTest, showMatureSkins: showMature)
        )
    }

    private func feed(
        _ entries: [SkinCatalogEntry],
        following: Set<String> = ["starvingartist"],
        since: Date? = nil,
        installed: Set<String> = [],
        policy: SkinStorePolicy? = nil,
        creators: SkinCreatorIndex? = nil
    ) -> SkinFollowFeed {
        SkinFollowFeed.make(
            in: SkinCatalog(skins: entries),
            creators: creators ?? index,
            following: following,
            since: since,
            installed: installed,
            policy: policy ?? self.policy()
        )
    }

    private func ids(_ feed: SkinFollowFeed) -> [[String]] {
        feed.items.map { $0.family.members.map(\.id) }
    }

    // MARK: - Who is on the shelf

    func testOnlyFollowedCreatorsAppear() {
        let entries = [
            entry("mine", author: "starvingartist", added: "2026-10-01"),
            entry("theirs", author: "JanZa", added: "2026-10-02"),
        ]
        XCTAssertEqual(ids(feed(entries)), [["mine"]])
        XCTAssertEqual(ids(feed(entries, following: ["janza", "starvingartist"])), [["theirs"], ["mine"]])
    }

    func testFollowingNobodyIsEmpty() {
        let result = feed([entry("a", author: "starvingartist", added: "2026-10-01")], following: [])
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(result.unseenCount, 0)
        XCTAssertNil(result.newestDate)
    }

    func testAnUnfollowedCreatorsSkinsLeaveTheShelf() {
        let entries = [entry("a", author: "starvingartist", added: "2026-10-01")]
        XCTAssertEqual(feed(entries, following: ["starvingartist"]).items.count, 1)
        XCTAssertTrue(feed(entries, following: []).isEmpty)
        XCTAssertTrue(feed(entries, following: ["nostromocrew01"]).isEmpty)
    }

    /// Spec §6: "ClearDoom" credits `starvingartist` but belongs to `nostromocrew01`, so following the
    /// artist does not put it on the shelf and following the creator does.
    func testTheCreatorOverrideDecidesWhoseSkinItIs() throws {
        let catalog = try SkinCatalog.decode(SkinCreatorFixture.catalogData)
        let all = SkinStorePolicy(
            sections: [SkinStoreSection(id: "all", title: "All", systemCodes: ["psx", "dreamcast", "gba", "nes", "snes"])],
            visibility: SkinContentVisibility(showTestSkins: false, showMatureSkins: false)
        )
        func shelf(_ following: Set<String>) -> Set<String> {
            let result = SkinFollowFeed.make(
                in: catalog, creators: index, following: following, since: nil, installed: [], policy: all
            )
            return Set(result.items.flatMap { $0.family.members.map(\.id) })
        }
        XCTAssertEqual(shelf(["starvingartist"]), ["starving-own", "starving-no-key"])
        XCTAssertEqual(shelf(["nostromocrew01"]), ["clear-doom"])
    }

    /// An alias resolves to the claimed creator, not to the local slug of the author string.
    func testAnAliasResolvesToTheClaimedCreator() {
        let directory = SkinCreatorIndex(creators: [SkinCreator(slug: "felix", aliases: ["felix#6506"])])
        let entries = [entry("f", author: "felix#6506", added: "2026-10-01")]
        XCTAssertEqual(ids(feed(entries, following: ["felix"], creators: directory)), [["f"]])
        XCTAssertTrue(feed(entries, following: ["felix-6506"], creators: directory).isEmpty,
                      "the local slug is not the creator once an alias claims the author")
        XCTAssertEqual(ids(feed(entries, following: ["felix-6506"], creators: .empty)), [["f"]],
                       "without a directory the local slug is all there is")
    }

    // MARK: - What the store can show

    func testWhatTheStoreCannotInstallIsLeftOut() {
        let entries = [
            entry("ok", author: "starvingartist", added: "2026-10-01"),
            entry("zip", author: "starvingartist", ext: "zip", added: "2026-10-02"),
            entry("no-shelf", author: "starvingartist", systems: ["nes"], added: "2026-10-03"),
        ]
        XCTAssertEqual(ids(feed(entries)), [["ok"]])
    }

    func testSampleAndMatureEntriesFollowTheVisibilitySetting() {
        let entries = [
            entry("shown", author: "starvingartist", added: "2026-10-01"),
            entry("sample", author: "starvingartist", tags: ["sample"], added: "2026-10-02"),
            entry("adult", author: "starvingartist", tags: ["mature"], added: "2026-10-03"),
        ]
        XCTAssertEqual(ids(feed(entries)), [["shown"]])
        XCTAssertEqual(ids(feed(entries, policy: policy(showTest: true, showMature: true))), [["adult"], ["sample"], ["shown"]])
    }

    func testNoPolicyAppliesOnlyVisibility() {
        let entries = [
            entry("zip", author: "starvingartist", ext: "zip", added: "2026-10-01"),
            entry("deltaskin", author: "starvingartist", systems: ["nes"], added: "2026-10-02"),
        ]
        let result = SkinFollowFeed.make(
            in: SkinCatalog(skins: entries), creators: index, following: ["starvingartist"], since: nil, installed: []
        )
        XCTAssertEqual(result.items.count, 2, "no policy means the plain browser's rules")
    }

    // MARK: - Installed

    func testInstalledEntriesAreNotNew() {
        let entries = [
            entry("a", author: "starvingartist", added: "2026-10-01"),
            entry("b", author: "starvingartist", added: "2026-10-02"),
        ]
        XCTAssertEqual(ids(feed(entries, installed: ["b"])), [["a"]])
        XCTAssertTrue(feed(entries, installed: ["a", "b"]).isEmpty)
    }

    /// One variant installed and another not: the family stays, whole, and only the missing variant is "new".
    func testAFamilyWithOneMissingVariantStaysOnTheShelfWhole() {
        let entries = [
            entry("v1", author: "starvingartist", groupId: "g", groupOrder: 1, added: "2026-09-01"),
            entry("v2", author: "starvingartist", groupId: "g", groupOrder: 2, added: "2026-10-05"),
        ]
        let result = feed(entries, installed: ["v1"])
        XCTAssertEqual(ids(result), [["v1", "v2"]])
        XCTAssertEqual(result.items[0].newMembers.map(\.id), ["v2"])
        XCTAssertEqual(result.items[0].effectiveDate, Self.date("2026-10-05"),
                       "the date is the new variant's, not the installed one's")
    }

    // MARK: - Families

    func testAFamilyIsOneItemWithEveryMember() {
        let entries = [
            entry("v3", author: "starvingartist", groupId: "g", groupOrder: 3, added: "2026-10-03"),
            entry("v1", author: "starvingartist", groupId: "g", groupOrder: 1, added: "2026-10-01"),
            entry("solo", author: "starvingartist", added: "2026-09-01"),
            entry("v2", author: "starvingartist", groupId: "g", groupOrder: 2, added: "2026-10-02"),
        ]
        let result = feed(entries)
        XCTAssertEqual(ids(result), [["v1", "v2", "v3"], ["solo"]])
        XCTAssertEqual(result.items[0].effectiveDate, Self.date("2026-10-03"), "a new variant makes the family recent")
    }

    /// A member by someone else stays in the family (its card shows the whole set) but is not "new from" the follow.
    func testAMixedAuthorFamilyKeepsEveryMemberButOnlyFollowedOnesAreNew() {
        let entries = [
            entry("mine", author: "starvingartist", groupId: "g", groupOrder: 1, added: "2026-10-01"),
            entry("other", author: "JanZa", groupId: "g", groupOrder: 2, added: "2026-10-09"),
        ]
        let result = feed(entries)
        XCTAssertEqual(ids(result), [["mine", "other"]])
        XCTAssertEqual(result.items[0].newMembers.map(\.id), ["mine"])
        XCTAssertEqual(result.items[0].creatorSlugs, ["starvingartist"])
        XCTAssertEqual(result.items[0].effectiveDate, Self.date("2026-10-01"))
    }

    func testAFamilyOfTwoFollowedCreatorsListsBoth() {
        let entries = [
            entry("a", author: "starvingartist", groupId: "g", groupOrder: 1, added: "2026-10-01"),
            entry("b", author: "JanZa", groupId: "g", groupOrder: 2, added: "2026-10-02"),
        ]
        let result = feed(entries, following: ["starvingartist", "janza"])
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].creatorSlugs, ["starvingartist", "janza"])
    }

    // MARK: - Order

    func testNewestFirstWithUndatedLastInCatalogOrder() {
        let entries = [
            entry("undated-1", author: "starvingartist"),
            entry("old", author: "starvingartist", added: "2025-01-01"),
            entry("undated-2", author: "starvingartist"),
            entry("new", author: "starvingartist", added: "2026-10-20"),
            entry("updated", author: "starvingartist", added: "2024-01-01", updated: "2026-11-01"),
        ]
        XCTAssertEqual(ids(feed(entries)), [["updated"], ["new"], ["old"], ["undated-1"], ["undated-2"]],
                       "the date is lastUpdated, else addedAt")
    }

    func testEqualDatesKeepCatalogOrder() {
        let entries = ["c", "a", "b"].map { entry($0, author: "starvingartist", added: "2026-10-01") }
        XCTAssertEqual(ids(feed(entries)), [["c"], ["a"], ["b"]])
    }

    // MARK: - Unseen

    func testWithNoSinceEveryDatedItemIsUnseen() {
        let entries = [
            entry("dated", author: "starvingartist", added: "2026-10-01"),
            entry("undated", author: "starvingartist"),
        ]
        let result = feed(entries, since: nil)
        XCTAssertEqual(result.items.map(\.isUnseen), [true, false], "nothing says when an undated item appeared")
        XCTAssertEqual(result.unseenCount, 1)
    }

    func testOnlyItemsAfterSinceAreUnseen() {
        let entries = [
            entry("newer", author: "starvingartist", added: "2026-10-20"),
            entry("same", author: "starvingartist", added: "2026-10-10"),
            entry("older", author: "starvingartist", added: "2026-10-01"),
        ]
        let result = feed(entries, since: Self.date("2026-10-10"))
        XCTAssertEqual(result.items.map(\.isUnseen), [true, false, false], "the day the user saw through is seen")
        XCTAssertEqual(result.unseenCount, 1)
        XCTAssertEqual(result.items.count, 3, "seen items stay on the shelf")
    }

    func testOpeningTheShelfClearsTheBadge() {
        let entries = [
            entry("a", author: "starvingartist", added: "2026-10-20"),
            entry("b", author: "starvingartist", added: "2026-10-10"),
        ]
        let before = feed(entries, since: Self.date("2026-10-01"))
        XCTAssertEqual(before.unseenCount, 2)
        XCTAssertEqual(before.newestDate, Self.date("2026-10-20"))

        let after = feed(entries, since: before.newestDate)
        XCTAssertEqual(after.unseenCount, 0)
        XCTAssertEqual(after.items.count, 2)
    }

    func testANewSkinAfterTheShelfWasSeenIsUnseen() {
        var entries = [entry("a", author: "starvingartist", added: "2026-10-20")]
        let seen = feed(entries).newestDate
        entries.append(entry("b", author: "starvingartist", added: "2026-10-25"))
        let result = feed(entries, since: seen)
        XCTAssertEqual(result.items.map { $0.family.primary.id }, ["b", "a"])
        XCTAssertEqual(result.unseenCount, 1)
    }

    func testNewestDateIsNilWhenNothingIsDated() {
        XCTAssertNil(feed([entry("a", author: "starvingartist")]).newestDate)
    }
}
