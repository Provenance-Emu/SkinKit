import XCTest
@testable import SkinCatalogKit

/// Decoding of `creators.json` and the value types in it.
final class SkinCreatorTests: XCTestCase {
    private var index: SkinCreatorIndex!

    override func setUpWithError() throws {
        index = try SkinCreatorIndex.decode(SkinCreatorFixture.creatorsData)
    }

    private func creator(_ slug: String) throws -> SkinCreator {
        try XCTUnwrap(index.creator(for: slug), "missing \(slug)")
    }

    func testRootAndLossyCreators() throws {
        XCTAssertEqual(index.version, 1)
        XCTAssertEqual(index.creators.count, SkinCreatorFixture.creatorCount)
        XCTAssertEqual(index.droppedCreatorCount, SkinCreatorFixture.droppedCreatorCount)
        let updated = try XCTUnwrap(index.updated)
        XCTAssertEqual(updated.timeIntervalSince1970, 1_793_750_400, accuracy: 1) // 2026-11-04
        XCTAssertEqual(index.creators.first?.slug, "starvingartist", "file order is kept")
    }

    func testClaimedProfile() throws {
        let creator = try creator("starvingartist")
        XCTAssertEqual(creator.id, "starvingartist")
        XCTAssertEqual(creator.displayName, "Starving Artist")
        XCTAssertEqual(creator.aliases, ["starvingartist"])
        XCTAssertTrue(creator.isClaimed)
        XCTAssertEqual(creator.githubLogin, "starvingartist")
        XCTAssertEqual(creator.bio, "Dreamcast and PSX skins with a worn-hardware look. Requests on Discord.")
        XCTAssertEqual(creator.avatarURL?.host, "github.com")
        XCTAssertNotNil(creator.bannerURL)
        XCTAssertEqual(creator.skinIds, ["3957312ad9e7c59e", "4ce9beceec67aa26"])
    }

    func testLinksKeepOnlyHTTPSAndDefaultTheLabel() throws {
        let links = try creator("starvingartist").links
        XCTAssertEqual(links.map(\.url.absoluteString), ["https://example.com/starving", "https://example.org/no-label"])
        XCTAssertEqual(links.map(\.label), ["Website", "example.org"])
    }

    func testSocialsDropUnknownKeysAndFollowPlatformOrder() throws {
        let socials = try creator("starvingartist").socials
        XCTAssertEqual(socials.map(\.platform), [.github, .discord, .bluesky, .mastodon, .kofi])
        XCTAssertEqual(socials.map(\.handle), [
            "starvingartist", "starving#0001", "starving.bsky.social", "starving@retro.example",
            "starving artist/../x",
        ])
    }

    func testSocialURLsAreBuiltFromHandlesOnly() throws {
        let socials = try creator("starvingartist").socials
        let urls = Dictionary(uniqueKeysWithValues: socials.map { ($0.platform, $0.url?.absoluteString) })
        XCTAssertEqual(urls[.github], "https://github.com/starvingartist")
        XCTAssertEqual(urls[.bluesky], "https://bsky.app/profile/starving.bsky.social")
        XCTAssertEqual(urls[.mastodon], "https://retro.example/@starving")
        // A hostile handle cannot add path segments or climb out of its slot.
        XCTAssertEqual(urls[.kofi], "https://ko-fi.com/starving%20artist%2F..%2Fx")
        // Discord handles have no stable URL.
        XCTAssertNil(socials.first { $0.platform == .discord }?.url)
        XCTAssertEqual(urls.count, 5)
    }

    func testEverySocialPlatformHasTitleSymbolAndURL() throws {
        XCTAssertEqual(SkinCreatorSocial.Platform.allCases.count, 14)
        for platform in SkinCreatorSocial.Platform.allCases {
            let handle = platform == .mastodon ? "me@host.example" : "me"
            let social = try XCTUnwrap(SkinCreatorSocial(platform: platform, handle: handle))
            XCTAssertFalse(social.title.isEmpty, platform.rawValue)
            XCTAssertFalse(social.symbolName.isEmpty, platform.rawValue)
            XCTAssertEqual(social.id, platform.rawValue)
            if platform == .discord {
                XCTAssertNil(social.url)
            } else {
                XCTAssertEqual(social.url?.scheme, "https", platform.rawValue)
            }
        }
    }

    func testSocialHandleNormalisation() {
        XCTAssertEqual(SkinCreatorSocial(platform: .x, handle: "  @@someone ")?.handle, "someone")
        XCTAssertNil(SkinCreatorSocial(platform: .x, handle: "  @ "))
        XCTAssertNil(SkinCreatorSocial(platform: .mastodon, handle: "no-host")?.url)
        XCTAssertNil(SkinCreatorSocial(platform: .mastodon, handle: "me@bad host/x")?.url)
    }

    func testStatsAndBadges() throws {
        let creator = try creator("starvingartist")
        let stats = try XCTUnwrap(creator.stats)
        XCTAssertEqual(stats.releases, 4)
        XCTAssertEqual(stats.files, 9)
        XCTAssertEqual(stats.variantsCompleted, 5)
        XCTAssertEqual(stats.systems, 3)
        XCTAssertEqual(stats.dualScreen, 0)
        XCTAssertEqual(stats.reachTier, 2)
        XCTAssertEqual(stats.claimed, true)
        XCTAssertNotNil(stats.firstAddedAt)
        XCTAssertNotNil(stats.lastAddedAt)

        XCTAssertEqual(creator.badges.map(\.id), ["creator.first-release", "creator.systems.5", "creator.claimed"])
        let first = creator.badges[0]
        XCTAssertEqual(first.title, "First release")
        XCTAssertEqual(first.detail, "Published a skin on EmuSkins.")
        XCTAssertEqual(first.symbol, "sparkles")
        XCTAssertNotNil(first.earnedAt)
        XCTAssertEqual(creator.badges[1].tier, 1)
        XCTAssertNil(creator.badges[2].title, "a bare id string is a badge with no label")
    }

    func testStatsAcceptASystemList() throws {
        let stats = try JSONDecoder().decode(
            SkinCreatorStats.self,
            from: Data(#"{"systems":["gba","psx"],"releases":"many"}"#.utf8)
        )
        XCTAssertEqual(stats.systems, 2)
        XCTAssertNil(stats.releases)
    }

    // MARK: - Claimed or not

    func testClaimedFlagFallsBackToLoginOrStats() throws {
        // Explicit `claimed: false`.
        XCTAssertFalse(try creator("janza").isClaimed)
        // No `claimed` key, but a verifying GitHub account.
        XCTAssertTrue(try creator("nostromocrew01").isClaimed)
        // Neither: unclaimed.
        let bare = try JSONDecoder().decode(SkinCreator.self, from: Data(#"{"slug":"bare"}"#.utf8))
        XCTAssertFalse(bare.isClaimed)
        // Stats alone can say it.
        let viaStats = try JSONDecoder().decode(
            SkinCreator.self,
            from: Data(#"{"slug":"s","stats":{"claimed":true}}"#.utf8)
        )
        XCTAssertTrue(viaStats.isClaimed)
    }

    func testUnclaimedRecordIsMinimal() throws {
        let creator = try creator("janza")
        XCTAssertEqual(creator.displayName, "JanZa")
        XCTAssertEqual(creator.aliases, ["JanZa"])
        XCTAssertEqual(creator.avatarURL?.absoluteString, "https://github.com/janza.png")
        XCTAssertNil(creator.bio)
        XCTAssertTrue(creator.links.isEmpty)
        XCTAssertTrue(creator.socials.isEmpty)
        XCTAssertNil(creator.stats)
        XCTAssertTrue(creator.badges.isEmpty)
    }

    func testBlankBioIsNil() throws {
        XCTAssertNil(try creator("nostromocrew01").bio)
    }

    // MARK: - Leniency

    func testHiddenProfilePublishesNothingButTheName() throws {
        let held = try creator("held")
        XCTAssertEqual(held.displayName, "Held Profile")
        XCTAssertFalse(held.isClaimed)
        XCTAssertNil(held.bio)
        XCTAssertNil(held.avatarURL)
        XCTAssertTrue(held.links.isEmpty)
        XCTAssertTrue(held.socials.isEmpty)
    }

    func testEveryFieldOfTheWrongTypeIsDroppedNotTheCreator() throws {
        let drift = try creator("typedrift")
        XCTAssertEqual(drift.displayName, "typedrift", "falls back to the slug")
        XCTAssertTrue(drift.aliases.isEmpty)
        XCTAssertFalse(drift.isClaimed)
        XCTAssertNil(drift.bio)
        XCTAssertTrue(drift.links.isEmpty)
        XCTAssertTrue(drift.socials.isEmpty)
        XCTAssertNil(drift.stats)
        XCTAssertTrue(drift.badges.isEmpty)
        XCTAssertTrue(drift.skinIds.isEmpty)
    }

    func testOnlyHTTPSImagesSurvive() throws {
        let json = #"{"slug":"s","avatarURL":"http://example.com/a.png","bannerURL":"file:///etc/passwd"}"#
        let creator = try JSONDecoder().decode(SkinCreator.self, from: Data(json.utf8))
        XCTAssertNil(creator.avatarURL)
        XCTAssertNil(creator.bannerURL)
    }

    func testUnknownKeysAreIgnored() throws {
        let json = #"{"slug":"s","displayName":"S","futureField":{"a":1},"claim":{"issue":1}}"#
        XCTAssertEqual(try JSONDecoder().decode(SkinCreator.self, from: Data(json.utf8)).displayName, "S")
    }

    func testSlugIsRequired() {
        XCTAssertThrowsError(try JSONDecoder().decode(SkinCreator.self, from: Data(#"{"displayName":"x"}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(SkinCreator.self, from: Data(#"{"slug":" "}"#.utf8)))
    }

    func testMinimalFactory() {
        let creator = SkinCreator.minimal(slug: "someone", displayName: "Some One")
        XCTAssertEqual(creator.slug, "someone")
        XCTAssertEqual(creator.displayName, "Some One")
        XCTAssertEqual(creator.aliases, ["Some One"])
        XCTAssertFalse(creator.isClaimed)
        XCTAssertEqual(SkinCreator.minimal(slug: "x").displayName, "x")
    }

    func testNotACreatorDirectoryThrows() {
        XCTAssertThrowsError(try SkinCreatorIndex.decode(Data("[1,2]".utf8))) { error in
            guard case SkinCatalogError.decoding = error else { return XCTFail("\(error)") }
        }
        // A bare object is a directory with no creators.
        XCTAssertEqual(try SkinCreatorIndex.decode(Data("{}".utf8)).creators.count, 0)
    }

    func testLinkAndHashableConformances() {
        let url = URL(string: "https://example.com")!
        XCTAssertEqual(SkinCreatorLink(label: "a", url: url), SkinCreatorLink(label: "a", url: url))
        XCTAssertEqual(Set([SkinCreator.minimal(slug: "a"), SkinCreator.minimal(slug: "a")]).count, 1)
    }
}
