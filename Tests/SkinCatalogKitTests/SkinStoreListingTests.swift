import XCTest
@testable import SkinCatalogKit

/// What the catalog browser lists when a host scopes it to one app's store.
final class SkinStoreListingTests: XCTestCase {
    private var catalog: SkinCatalog!

    override func setUpWithError() throws {
        catalog = try SkinCatalog.decode(SkinCatalogFixture.data)
        XCTAssertEqual(catalog.skins.count, SkinCatalogFixture.entryCount)
    }

    private func entry(_ id: String, name: String? = nil, systems: [String], tags: [String] = []) throws -> SkinCatalogEntry {
        try SkinCatalogEntry(
            id: id,
            name: name ?? id,
            systems: systems,
            downloadURL: XCTUnwrap(URL(string: "https://example.com/\(id).deltaskin")),
            tags: tags
        )
    }

    // MARK: - Scope

    func testListsExactlyWhatThePolicyShelves() {
        for policy in [SkinStorePolicy.iFly, .iCube] {
            let listing = SkinStoreListing(entries: catalog.skins, policy: policy, device: nil)
            let expected = policy.sections(for: catalog.skins).flatMap { $0.entries.map(\.id) }
            XCTAssertEqual(Set(listing.entries.map(\.id)), Set(expected))
            XCTAssertFalse(listing.entries.isEmpty)
        }
    }

    func testEntriesKeepFeedOrder() {
        let listing = SkinStoreListing(entries: catalog.skins, policy: .iFly, device: nil)
        let feedOrder = catalog.skins.map(\.id).filter(Set(listing.entries.map(\.id)).contains)
        XCTAssertEqual(listing.entries.map(\.id), feedOrder)
    }

    func testHidesEntriesTheAppCannotInstallOrDoesNotShelve() throws {
        let listing = SkinStoreListing(entries: catalog.skins, policy: .iFly, device: nil)
        for id in [SkinCatalogFixture.sharpX1ID, SkinCatalogFixture.n64ZipID, SkinCatalogFixture.googleDriveID,
                   SkinCatalogFixture.gbaSpaceURLID, SkinCatalogFixture.threeDSID] {
            let entry = try XCTUnwrap(catalog.skins.first { $0.id == id })
            XCTAssertFalse(listing.contains(entry), id)
            XCTAssertNil(listing.sectionId(for: entry), id)
        }
    }

    // MARK: - Categories

    func testCategoriesFollowPolicyOrderAndCountEntries() {
        let listing = SkinStoreListing(entries: catalog.skins, policy: .iFly, device: nil)
        XCTAssertEqual(listing.categories.map(\.id), ["dreamcast", "arcade", "otherSystems"])
        for category in listing.categories {
            XCTAssertEqual(category.entryCount, listing.entries(inSection: category.id).count)
            XCTAssertGreaterThan(category.entryCount, 0)
        }
        XCTAssertEqual(listing.categories.map(\.entryCount).reduce(0, +), listing.entries.count)
    }

    func testCategoryWithoutEntriesIsOmitted() throws {
        let listing = try SkinStoreListing(
            entries: [entry("a", systems: ["wii"]), entry("b", systems: ["snes"])],
            policy: .iCube,
            device: nil
        )
        XCTAssertEqual(listing.categories.map(\.id), ["wii", "snes"])
    }

    func testAnEntryIsListedOnceOnTheFirstShelfThatClaimsIt() throws {
        let both = try entry("both", systems: ["wii", "gamecube"])
        let listing = SkinStoreListing(entries: [both], policy: .iCube, device: nil)
        XCTAssertEqual(listing.sectionId(for: both), "gameCube")
        XCTAssertEqual(listing.entries(inSection: "gameCube").map(\.id), ["both"])
        XCTAssertTrue(listing.entries(inSection: "wii").isEmpty)
    }

    func testUnknownCategoryIsEmptyAndNilIsEverything() {
        let listing = SkinStoreListing(entries: catalog.skins, policy: .iCube, device: nil)
        XCTAssertTrue(listing.entries(inSection: "dreamcast").isEmpty)
        XCTAssertEqual(listing.entries(inSection: nil).map(\.id), listing.entries.map(\.id))
    }

    // MARK: - Device

    func testDeviceFilterHidesSkinsNamedForTheOtherDevice() throws {
        let entries = try [
            entry("phone", name: "Cube for iPhone", systems: ["gamecube"]),
            entry("pad", name: "Cube for iPad", systems: ["gamecube"]),
            entry("both", name: "Cube for iPhone and iPad", systems: ["gamecube"]),
            entry("plain", name: "Cube", systems: ["gamecube"])
        ]
        let phone = SkinStoreListing(entries: entries, policy: .iCube, device: .iPhone)
        XCTAssertEqual(phone.entries.map(\.id), ["phone", "both", "plain"])
        let pad = SkinStoreListing(entries: entries, policy: .iCube, device: .iPad)
        XCTAssertEqual(pad.entries.map(\.id), ["pad", "both", "plain"])
        XCTAssertEqual(pad.categories.first?.entryCount, 3)
        let unfiltered = SkinStoreListing(entries: entries, policy: .iCube, device: nil)
        XCTAssertEqual(unfiltered.entries.count, 4)
    }

    // MARK: - Search

    func testSearchMatchesNameAuthorTagsAndSourceInsideTheCategory() throws {
        var byAuthor = try entry("author", name: "Plain", systems: ["dreamcast"])
        byAuthor.author = "Sega Fan"
        var bySource = try entry("source", name: "Other", systems: ["mame"])
        bySource.source = "sega-archive"
        let entries = try [
            entry("name", name: "SEGA Blue", systems: ["dreamcast"]),
            byAuthor,
            entry("tag", name: "Tagged", systems: ["dreamcast"], tags: ["Sega"]),
            bySource,
            entry("miss", name: "Nothing", systems: ["dreamcast"])
        ]
        let listing = SkinStoreListing(entries: entries, policy: .iFly, device: nil)
        XCTAssertEqual(listing.entries(inSection: nil, matching: " sega ").map(\.id), ["name", "author", "tag", "source"])
        XCTAssertEqual(listing.entries(inSection: "dreamcast", matching: "sega").map(\.id), ["name", "author", "tag"])
        XCTAssertEqual(listing.entries(inSection: "arcade", matching: "SEGA").map(\.id), ["source"])
        XCTAssertEqual(listing.entries(inSection: "dreamcast", matching: "  ").count, 4)
        XCTAssertTrue(listing.entries(inSection: nil, matching: "zzz").isEmpty)
    }

    // MARK: - Visibility

    func testSampleAndMatureEntriesFollowThePolicyVisibility() throws {
        var hidden = SkinStorePolicy.iFly
        hidden.visibility = SkinContentVisibility(showTestSkins: false, showMatureSkins: false)
        let hiddenIds = Set(SkinStoreListing(entries: catalog.skins, policy: hidden, device: nil).entries.map(\.id))
        XCTAssertTrue(hiddenIds.isDisjoint(with: SkinCatalogFixture.sampleDreamcastIDs))
        XCTAssertFalse(hiddenIds.contains(SkinCatalogFixture.matureDreamcastID))

        var shown = SkinStorePolicy.iFly
        shown.visibility = SkinContentVisibility(showTestSkins: true, showMatureSkins: true)
        let shownIds = Set(SkinStoreListing(entries: catalog.skins, policy: shown, device: nil).entries.map(\.id))
        XCTAssertTrue(shownIds.isSuperset(of: SkinCatalogFixture.sampleDreamcastIDs))
        XCTAssertTrue(shownIds.contains(SkinCatalogFixture.matureDreamcastID))
    }
}
