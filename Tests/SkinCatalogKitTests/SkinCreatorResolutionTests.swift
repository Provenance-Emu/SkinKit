import XCTest
@testable import SkinCatalogKit

/// `SkinCreatorIndex` resolution (creator profiles spec §6 and §7): the catalog's `creator` first,
/// then an alias match on `author`, then the local slug.
final class SkinCreatorResolutionTests: XCTestCase {
    private var index: SkinCreatorIndex!
    private var catalog: SkinCatalog!

    override func setUpWithError() throws {
        index = try SkinCreatorIndex.decode(SkinCreatorFixture.creatorsData)
        catalog = try SkinCatalog.decode(SkinCreatorFixture.catalogData)
    }

    private func entry(_ id: String) throws -> SkinCatalogEntry {
        try XCTUnwrap(catalog.skins.first { $0.id == id }, "missing \(id)")
    }

    func testCatalogDecodesCreatorKey() throws {
        XCTAssertEqual(catalog.skins.count, 9)
        XCTAssertEqual(catalog.droppedEntryCount, 0)
        XCTAssertEqual(try entry("clear-doom").creatorSlug, "nostromocrew01")
        XCTAssertEqual(try entry("starving-no-key").creatorSlug, nil)
        XCTAssertNil(try entry("blank-creator").creatorSlug, "whitespace is no slug")
        XCTAssertNil(try entry("mistyped-creator").creatorSlug, "a mistyped creator drops the field, not the entry")
    }

    /// The case spec §6 names: `author` is `starvingartist`, a claimed alias, but the entry's
    /// `creator` says `nostromocrew01`. Alias-first would hand the skin back to the uploader.
    func testCreatorSlugBeatsAClaimedAlias() throws {
        let clearDoom = try entry("clear-doom")
        XCTAssertEqual(clearDoom.author, "starvingartist")
        XCTAssertEqual(index.creator(for: "starvingartist")?.aliases.contains("starvingartist"), true)
        XCTAssertEqual(index.slug(for: clearDoom), "nostromocrew01")
        XCTAssertEqual(index.creator(for: clearDoom)?.displayName, "NostromoCrew01")
    }

    func testOverrideMovesTheSkinBetweenCreatorPages() throws {
        let starving = try XCTUnwrap(index.creator(for: "starvingartist"))
        let nostromo = try XCTUnwrap(index.creator(for: "nostromocrew01"))
        XCTAssertEqual(
            index.skins(by: starving, in: catalog).map(\.id),
            ["starving-own", "starving-no-key"]
        )
        XCTAssertEqual(index.skins(by: nostromo, in: catalog).map(\.id), ["clear-doom"])
    }

    func testAliasMatchWhenTheCatalogHasNoCreator() throws {
        let entry = try entry("starving-no-key")
        XCTAssertEqual(index.slug(for: entry), "starvingartist")
        XCTAssertEqual(index.creator(for: entry)?.isClaimed, true)
    }

    func testAliasMatchIsExactAndFirstWins() throws {
        var entry = try entry("starving-no-key")
        // `dupe-alias` repeats the alias `starvingartist`; the earlier record in the file wins.
        XCTAssertEqual(index.slug(for: entry), "starvingartist")
        XCTAssertNotNil(index.creator(for: "dupe-alias"), "the second record still exists by slug")
        // A different spelling is not an alias; it falls through to the local slug.
        entry.author = "StarvingArtist"
        XCTAssertEqual(index.slug(for: entry), "starvingartist")
        entry.author = "Starving Artist"
        XCTAssertEqual(index.slug(for: entry), "starving-artist")
    }

    func testAliasWithOddCharactersMatchesBeforeSlugging() {
        let creator = SkinCreator(slug: "felix", aliases: ["felix#6506"])
        let index = SkinCreatorIndex(creators: [creator])
        let entry = SkinCatalogEntry(
            id: "e", name: "E", author: "felix#6506", systems: [], downloadURL: URL(string: "https://example.com/e")!
        )
        XCTAssertEqual(index.slug(for: entry), "felix", "the alias beats the local slug 'felix-6506'")
        var other = entry
        other.author = "felix#6507"
        XCTAssertEqual(index.slug(for: other), "felix-6507")
    }

    func testUnlistedAuthorGetsALocalSlugAndAMinimalProfile() throws {
        let entry = try entry("unlisted-author")
        XCTAssertEqual(index.slug(for: entry), "brand-new-person")
        let creator = try XCTUnwrap(index.creator(for: entry))
        XCTAssertEqual(creator.slug, "brand-new-person")
        XCTAssertEqual(creator.displayName, "Brand New Person!")
        XCTAssertFalse(creator.isClaimed)
        XCTAssertNil(index.creator(for: "brand-new-person"), "synthesised, not in the directory")
    }

    func testCatalogSlugMissingFromTheDirectoryStaysPut() throws {
        // The catalog is newer than creators.json. The slug still wins; no alias or slug guess.
        let entry = try entry("creator-not-in-directory")
        XCTAssertEqual(index.slug(for: entry), "ghost")
        let creator = try XCTUnwrap(index.creator(for: entry))
        XCTAssertEqual(creator.slug, "ghost")
        XCTAssertEqual(creator.displayName, "Ghost Writer")
    }

    func testBlankAndMistypedCreatorFallBackToTheAuthor() throws {
        XCTAssertEqual(index.slug(for: try entry("blank-creator")), "janza")
        XCTAssertEqual(index.slug(for: try entry("mistyped-creator")), "janza")
    }

    func testEntryWithoutAnAuthorHasNoCreator() throws {
        let entry = try entry("no-author")
        XCTAssertNil(index.slug(for: entry))
        XCTAssertNil(index.creator(for: entry))
        var unsluggable = entry
        unsluggable.author = "日本語のみ"
        XCTAssertNil(index.creator(for: unsluggable), "an author with nothing to slug has no addressable profile")
        unsluggable.author = "   "
        XCTAssertNil(index.creator(for: unsluggable))
    }

    // MARK: - Old catalogs

    /// The done-when: a catalog from before the `creator` key, and no directory at all, still
    /// resolves a profile for every entry that credits an author.
    func testOldCatalogWithoutCreatorResolvesEveryAuthoredEntry() throws {
        let old = try SkinCatalog.decode(SkinCatalogFixture.data)
        XCTAssertTrue(old.skins.allSatisfy { $0.creatorSlug == nil }, "the fixture predates `creator`")
        for directory in [SkinCreatorIndex.empty, index!] {
            var authored = 0
            for skin in old.skins {
                let creator = directory.creator(for: skin)
                if let author = skin.author {
                    authored += 1
                    let resolved = try XCTUnwrap(creator, "\(skin.id) by \(author)")
                    XCTAssertEqual(resolved.slug, SkinCreatorSlug.make(from: author), skin.id)
                    XCTAssertFalse(resolved.displayName.isEmpty)
                } else {
                    XCTAssertNil(creator, skin.id)
                }
            }
            XCTAssertEqual(authored, 37)
        }
    }

    func testOldCatalogGroupsAnAuthorsSkinsUnderOneProfile() throws {
        let old = try SkinCatalog.decode(SkinCatalogFixture.data)
        let creator = try XCTUnwrap(SkinCreatorIndex.empty.creator(
            for: XCTUnwrap(old.skins.first { $0.id == SkinCatalogFixture.dreamcastIDs[0] })
        ))
        XCTAssertEqual(creator.slug, "starvingartist")
        let skins = SkinCreatorIndex.empty.skins(by: creator, in: old)
        XCTAssertEqual(skins.count, 4)
        XCTAssertTrue(skins.allSatisfy { $0.author == "starvingartist" })
    }

    func testSkinsByCreatorKeepsCatalogOrderAndFindsNothingForAStranger() throws {
        XCTAssertEqual(index.skins(bySlug: "janza", in: catalog).map(\.id), ["janza-skin", "blank-creator", "mistyped-creator"])
        XCTAssertTrue(index.skins(bySlug: "nobody", in: catalog).isEmpty)
    }
}
