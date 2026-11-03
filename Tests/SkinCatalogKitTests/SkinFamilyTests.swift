import XCTest
@testable import SkinCatalogKit

/// Variant families (SkinKit#17, spec §3): decoding `variantLabel` / `variants`, grouping by
/// `groupId` and `groupOrder`, the label fallback, download plans, and the `sample` / `mature`
/// visibility rules (SkinKit#13), against the fixture feed.
final class SkinFamilyTests: XCTestCase {
    private var catalog: SkinCatalog!

    override func setUpWithError() throws {
        catalog = try SkinCatalog.decode(SkinCatalogFixture.data)
        XCTAssertEqual(catalog.skins.count, SkinCatalogFixture.entryCount)
    }

    private func entry(_ id: String) throws -> SkinCatalogEntry {
        try XCTUnwrap(catalog.skins.first { $0.id == id }, "missing \(id)")
    }

    private func family(containing id: String, in families: [SkinFamily]? = nil) throws -> SkinFamily {
        try XCTUnwrap((families ?? catalog.families).first { $0.members.contains { $0.id == id } }, "no family for \(id)")
    }

    private func make(
        _ id: String,
        name: String? = nil,
        group: String? = nil,
        order: Int? = nil,
        label: String? = nil,
        url: String? = nil,
        tags: [String] = [],
        systems: [String] = ["gba"]
    ) -> SkinCatalogEntry {
        SkinCatalogEntry(
            id: id,
            name: name ?? id,
            systems: systems,
            downloadURL: URL(string: url ?? "https://example.com/\(id).deltaskin")!,
            tags: tags,
            groupId: group,
            groupOrder: order,
            variantLabel: label
        )
    }

    // MARK: - Decoding

    func testDecodesVariantLabel() throws {
        XCTAssertEqual(try entry(SkinCatalogFixture.gbaFamilyBlueID).variantLabel, "Ocean Blue")
        XCTAssertNil(try entry(SkinCatalogFixture.gbaFamilyRedID).variantLabel, "absent in the feed")
        XCTAssertNil(try entry(SkinCatalogFixture.dreamcastIDs[0]).variantLabel)
    }

    func testDecodesVariantsLossily() throws {
        let ds = try entry(SkinCatalogFixture.singleFileAltID)
        // The item without a key is dropped; the unknown kind is kept.
        XCTAssertEqual(ds.variants, [
            SkinCatalogVariant(kind: .alt, key: "alt", label: "Alternate layout"),
            SkinCatalogVariant(kind: .other("futureKind"), key: "x", label: "x"),
        ])
        XCTAssertTrue(ds.hasPackedVariants)

        let games = try entry(SkinCatalogFixture.jaguarSingleID)
        XCTAssertEqual(games.variants.map(\.kind), [.game, .game, .theme])
        XCTAssertEqual(games.variants.map(\.label), ["Doom", "AvP", "Dark"])
        XCTAssertFalse(try entry(SkinCatalogFixture.jaguarSplitID).hasPackedVariants)
    }

    func testMistypedVariantsDropOnlyTheField() throws {
        let json = #"""
        {"skins": [{"id": "a", "name": "A", "downloadURL": "https://e.com/a.deltaskin",
                    "variants": "not an array", "variantLabel": "  "}]}
        """#
        let decoded = try SkinCatalog.decode(Data(json.utf8))
        XCTAssertEqual(decoded.skins.count, 1)
        XCTAssertEqual(decoded.skins[0].variants, [])
        XCTAssertNil(decoded.skins[0].variantLabel, "blank label reads as unset")
    }

    // MARK: - Labels

    func testVariantLabelFallbackMatchesTheCatalogBackfill() {
        XCTAssertEqual(SkinVariantLabel.derive(fullName: "Paw — Doom", baseName: nil), "Doom")
        XCTAssertEqual(SkinVariantLabel.derive(fullName: "Paw - Doom", baseName: nil), "Doom")
        XCTAssertEqual(SkinVariantLabel.derive(fullName: "A - B — C", baseName: nil), "C", "an em dash anywhere wins")
        XCTAssertNil(SkinVariantLabel.derive(fullName: "— Leading", baseName: nil), "a separator at the start doesn't count")
        XCTAssertEqual(SkinVariantLabel.derive(fullName: "Fixture Pad Green", baseName: "fixture pad"), "Green")
        XCTAssertEqual(SkinVariantLabel.derive(fullName: "Fixture Pad: Green", baseName: "Fixture Pad"), "Green")
        XCTAssertNil(SkinVariantLabel.derive(fullName: "Fixture Pad", baseName: "Fixture Pad"), "nothing left")
        XCTAssertNil(SkinVariantLabel.derive(fullName: "FS-NDS Joystick LED 1", baseName: "Other"), "show the full name")
        XCTAssertEqual(SkinVariantLabel.stripSuffix("Paw — Doom"), "Paw")
        XCTAssertEqual(SkinVariantLabel.stripSuffix("Paw"), "Paw")
        XCTAssertEqual(SkinVariantLabel.resolve(explicit: "Mine", fullName: "Paw — Doom", baseName: nil), "Mine")
    }

    func testFamilyLabelsUseExplicitThenSuffixThenBaseNameThenFullName() throws {
        let family = try family(containing: SkinCatalogFixture.gbaFamilyRedID)
        XCTAssertEqual(family.name, "Fixture Pad")
        let labels = family.members.map(family.label(for:))
        XCTAssertEqual(labels, ["Red", "Green", "Ocean Blue"])

        // A member with nothing derivable shows its full name.
        let odd = SkinFamily.families(from: [
            make("1", name: "Pack — One", group: "g", order: 1),
            make("2", name: "Unrelated", group: "g", order: 2),
        ])
        XCTAssertEqual(odd.count, 1)
        XCTAssertEqual(odd[0].label(for: odd[0].members[1]), "Unrelated")
    }

    func testLabelsDoNotDependOnTheFilteredSlice() throws {
        let index = catalog.familyIndex
        // Only the third member is visible (a search hit): it still gets the whole family's label.
        let slice = [try entry(SkinCatalogFixture.gbaFamilyGreenID)]
        let families = index.families(from: slice)
        XCTAssertEqual(families.count, 1)
        XCTAssertEqual(families[0].label(for: slice[0]), "Green")
        XCTAssertEqual(families[0].name, "Fixture Pad Green", "a family of one shows the entry's own name")
        XCTAssertEqual(index.variantLabel(for: slice[0]), "Green")
        XCTAssertEqual(index.baseName(forGroup: SkinCatalogFixture.gbaFamilyGroupID), "Fixture Pad")
    }

    // MARK: - Grouping

    func testGroupsByGroupIdOrderedByGroupOrder() throws {
        let family = try family(containing: SkinCatalogFixture.gbaFamilyBlueID)
        XCTAssertEqual(family.id, "group:\(SkinCatalogFixture.gbaFamilyGroupID)")
        XCTAssertEqual(family.groupId, SkinCatalogFixture.gbaFamilyGroupID)
        XCTAssertEqual(family.members.map(\.id), [
            SkinCatalogFixture.gbaFamilyRedID, SkinCatalogFixture.gbaFamilyGreenID, SkinCatalogFixture.gbaFamilyBlueID,
        ], "groupOrder 1, 2, 3 although the feed lists 1, 3, 2")
        XCTAssertTrue(family.isMultiFile)
        XCTAssertTrue(family.hasVariants)
        XCTAssertEqual(family.totalDownloadCount, 60)
        XCTAssertEqual(family.authors, ["Alice", "Bob"], "each member keeps its own credit")
    }

    func testStandaloneEntriesAreFamiliesOfOne() throws {
        let dreamsicle = try family(containing: SkinCatalogFixture.dreamcastIDs[0])
        XCTAssertEqual(dreamsicle.id, "entry:\(SkinCatalogFixture.dreamcastIDs[0])")
        XCTAssertNil(dreamsicle.groupId)
        XCTAssertEqual(dreamsicle.members.count, 1)
        XCTAssertEqual(dreamsicle.name, "Dreamsicle")
        XCTAssertFalse(dreamsicle.hasVariants)
        XCTAssertEqual(dreamsicle.label(for: dreamsicle.primary), "Dreamsicle")
    }

    func testSingleFileSkinWithVariantsHasVariants() throws {
        let ds = try family(containing: SkinCatalogFixture.singleFileAltID)
        XCTAssertFalse(ds.isMultiFile)
        XCTAssertTrue(ds.hasVariants, "the Has variants predicate counts packed variants")
        XCTAssertEqual(ds.variantCount, 3)
    }

    func testMixedFamily() throws {
        let jaguar = try family(containing: SkinCatalogFixture.jaguarSingleID)
        XCTAssertEqual(jaguar.members.map(\.id), [SkinCatalogFixture.jaguarSplitID, SkinCatalogFixture.jaguarSingleID])
        XCTAssertEqual(jaguar.name, "Fixture Keypad")
        XCTAssertEqual(jaguar.members.map(jaguar.label(for:)), ["Base", "Games"])
        XCTAssertEqual(jaguar.variantCount, 5, "the split file, plus the single file and its three variants")
    }

    func testRealPackSpanningSystemsGroups() throws {
        let families = catalog.families
        let taco = try family(containing: SkinCatalogFixture.dreamcastIDs[2], in: families)
        XCTAssertEqual(taco.members.count, 2)
        XCTAssertEqual(taco.name, "POCKET TACO SEGA Pack for MANIC emu")
        XCTAssertEqual(taco.members.map(taco.label(for:)), ["Belmon T Taco CD Dark", "Belmon T Taco DC Dark"], "groupOrder, not feed order")
    }

    func testFamiliesKeepTheOrderOfTheirFirstMember() {
        let entries = [
            make("solo-a"),
            make("g-2", group: "g", order: 2),
            make("solo-b"),
            make("g-1", group: "g", order: 1),
            make("g-none", group: "g"),
        ]
        let families = SkinFamily.families(from: entries)
        XCTAssertEqual(families.map(\.id), ["entry:solo-a", "group:g", "entry:solo-b"])
        XCTAssertEqual(families[1].members.map(\.id), ["g-1", "g-2", "g-none"], "no groupOrder sorts last")
        XCTAssertEqual(families.flatMap(\.members).count, entries.count, "nothing lost")
    }

    func testCatalogGroupingLosesNoEntries() {
        XCTAssertEqual(catalog.families.flatMap(\.members).count, catalog.skins.count)
    }

    func testInstalledFamiliesGroupByStoredMembership() {
        struct Installed { let id: String; let name: String }
        let items = [
            Installed(id: "a", name: "Paw — Doom"),
            Installed(id: "b", name: "Standalone"),
            Installed(id: "c", name: "Paw — Wolf3D"),
            Installed(id: "d", name: "Lonely — One"),
        ]
        let memberships: [String: SkinFamilyMembership] = [
            "a": .init(groupId: "paw", groupOrder: 2),
            "c": .init(groupId: "paw", groupOrder: 1, variantLabel: "Wolfenstein"),
            "d": .init(groupId: "lonely", groupOrder: 1),
        ]
        let families = SkinInstalledFamily.families(items, key: \.id, name: \.name, membership: { memberships[$0.id] })
        XCTAssertEqual(families.map(\.id), ["group:paw", "item:b", "item:d"])
        XCTAssertEqual(families[0].members.map(\.id), ["c", "a"])
        XCTAssertEqual(families[0].labels, ["Wolfenstein", "Doom"])
        XCTAssertEqual(families[0].name, "Paw")
        XCTAssertFalse(families[2].isMultiMember, "one installed member of a family shows as a plain skin")
        XCTAssertEqual(families[2].labels, ["Lonely — One"])
    }

    // MARK: - Download plans

    func testDownloadPlanAllSomeAndOne() throws {
        let family = try family(containing: SkinCatalogFixture.gbaFamilyRedID)
        XCTAssertEqual(family.downloadPlan().urls.map(\.lastPathComponent), [
            "fixture-pad-red.deltaskin", "fixture-pad-green.deltaskin", "fixture-pad-blue.deltaskin",
        ])
        let some = family.downloadPlan(memberIds: [SkinCatalogFixture.gbaFamilyBlueID, SkinCatalogFixture.gbaFamilyRedID])
        XCTAssertEqual(some.entries.map(\.id), [SkinCatalogFixture.gbaFamilyRedID, SkinCatalogFixture.gbaFamilyBlueID], "family order")
        let one = family.downloadPlan(for: family.members[1])
        XCTAssertEqual(one.count, 1)
        XCTAssertEqual(one.urls, [family.members[1].downloadURL])
        XCTAssertTrue(family.downloadPlan(memberIds: []).isEmpty)
    }

    func testDownloadPlanOneURLPerFileForMixedFamilies() throws {
        let jaguar = try family(containing: SkinCatalogFixture.jaguarSplitID)
        XCTAssertEqual(jaguar.downloadPlan().count, 2, "the single-file member brings its own three variants")
        let ds = try family(containing: SkinCatalogFixture.singleFileAltID)
        XCTAssertEqual(ds.downloadPlan().count, 1)
    }

    func testDownloadPlanDedupesAndFiltersByPolicy() {
        let shared = "https://example.com/shared.deltaskin"
        let plan = SkinDownloadPlan(entries: [
            make("a", url: shared),
            make("b", url: shared),
            make("c", url: "https://example.com/c.zip"),
            make("d"),
        ])
        XCTAssertEqual(plan.entries.map(\.id), ["a", "c", "d"], "same URL downloads once")

        let policy = SkinStorePolicy(sections: [SkinStoreSection(id: "gba", title: "GBA", systemCodes: ["gba"])])
        let filtered = SkinDownloadPlan(entries: plan.entries, policy: policy)
        XCTAssertEqual(filtered.entries.map(\.id), ["a", "d"], "the policy can't install the .zip")
        XCTAssertEqual(filtered.excluding(installedIds: ["a"]).entries.map(\.id), ["d"])
    }

    // MARK: - Visibility: sample and mature

    func testSampleSkinsHiddenUnlessShowTestSkins() throws {
        for id in SkinCatalogFixture.sampleDreamcastIDs {
            var policy = SkinStorePolicy.iFly
            policy.visibility = .default
            XCTAssertNil(policy.section(for: try entry(id)), id)
            policy.showTestSkins = true
            XCTAssertEqual(policy.section(for: try entry(id)), .dreamcast, id)
        }
        for id in SkinCatalogFixture.sampleGameCubeIDs {
            var policy = SkinStorePolicy.iCube
            policy.visibility = .default
            XCTAssertNil(policy.section(for: try entry(id)), id)
            policy.showTestSkins = true
            XCTAssertEqual(policy.section(for: try entry(id)), .gameCube, id)
        }
        XCTAssertTrue(try entry(SkinCatalogFixture.sampleDreamcastIDs[1]).isTestSkin, "tag match is case-insensitive")
    }

    func testMatureSkinsHiddenUnlessShowMatureSkins() throws {
        let mature = try entry(SkinCatalogFixture.matureDreamcastID)
        XCTAssertTrue(mature.isMature)
        var policy = SkinStorePolicy.iFly
        policy.visibility = .default
        XCTAssertFalse(policy.showMatureSkins, "off by default")
        XCTAssertNil(policy.section(for: mature))
        policy.showMatureSkins = true
        XCTAssertEqual(policy.section(for: mature), .dreamcast)
        XCTAssertFalse(policy.showTestSkins, "the two flags are independent")
        XCTAssertNil(policy.section(for: try entry(SkinCatalogFixture.sampleDreamcastIDs[0])))
    }

    func testPresetsFollowTheAppWideSetting() throws {
        let previous = SkinContentVisibility.current
        defer { SkinContentVisibility.current = previous }

        let sample = try entry(SkinCatalogFixture.sampleGameCubeIDs[0])
        SkinContentVisibility.current = .default
        XCTAssertNil(SkinStorePolicy.iCube.section(for: sample))
        SkinContentVisibility.current = SkinContentVisibility(showTestSkins: true)
        XCTAssertEqual(SkinStorePolicy.iCube.section(for: sample), .gameCube, "no rebuild needed")

        var pinned = SkinStorePolicy.iCube
        pinned.visibility = .default
        XCTAssertNil(pinned.section(for: sample), "a pinned policy ignores the app-wide setting")
    }

    func testVisibilityFilter() throws {
        let all = catalog.skins
        XCTAssertEqual(SkinContentVisibility.default.filter(all).count, all.count - 5)
        XCTAssertEqual(SkinContentVisibility(showTestSkins: true).filter(all).count, all.count - 1)
        XCTAssertEqual(SkinContentVisibility(showTestSkins: true, showMatureSkins: true).filter(all).count, all.count)
    }

    func testFamilySectionsShowSampleFamilyAsOneCard() {
        var policy = SkinStorePolicy.iCube
        policy.visibility = SkinContentVisibility(showTestSkins: true)
        let shelves = policy.familySections(for: catalog.skins, index: catalog.familyIndex)
        let gameCube = shelves.first { $0.section == .gameCube }
        let sampleFamily = gameCube?.families.first { $0.groupId == "provenance-emu:sample-split-family-gc" }
        XCTAssertEqual(sampleFamily?.members.map(\.id), SkinCatalogFixture.sampleGameCubeIDs)
        XCTAssertEqual(sampleFamily.map { $0.members.map($0.label(for:)) }, ["One", "Two"])
        XCTAssertEqual(sampleFamily?.name, "Sample Split Family GC")

        policy.visibility = .default
        let hidden = policy.familySections(for: catalog.skins)
        XCTAssertFalse(hidden.flatMap(\.families).flatMap(\.members).contains(where: \.isTestSkin))
    }
}
