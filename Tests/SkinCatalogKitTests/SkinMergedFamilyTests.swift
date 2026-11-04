import XCTest
@testable import SkinCatalogKit

/// Merged-variant entries (SkinKit#79, skin editing tools spec §3): the catalog publishes one extra
/// entry per family that packs the split members into a single file, with `mergedFrom` naming them.
/// A download plan must never fetch the merged file together with the members it came from.
final class SkinMergedFamilyTests: XCTestCase {
    private func make(
        _ id: String,
        group: String? = "g:pad",
        order: Int? = nil,
        label: String? = nil,
        url: String? = nil,
        mergedFrom: [String] = []
    ) -> SkinCatalogEntry {
        SkinCatalogEntry(
            id: id,
            name: "Pad — \(id)",
            systems: ["gba"],
            downloadURL: URL(string: url ?? "https://example.com/\(id).deltaskin")!,
            groupId: group,
            groupOrder: order,
            variantLabel: label,
            mergedFrom: mergedFrom
        )
    }

    /// Three split members, plus the merged file at `groupOrder` 0 ("so it sits first in the family").
    private func mergedFamilyEntries() -> [SkinCatalogEntry] {
        [
            make("red", order: 1),
            make("green", order: 2),
            make("blue", order: 3),
            make("all", order: 0, label: "All variants", mergedFrom: ["red", "green", "blue"]),
        ]
    }

    private func family(_ entries: [SkinCatalogEntry]) throws -> SkinFamily {
        let families = SkinFamily.families(from: entries)
        XCTAssertEqual(families.count, 1)
        return try XCTUnwrap(families.first)
    }

    // MARK: - Decoding

    private func decode(_ extra: String) throws -> SkinCatalogEntry {
        let json = #"{"id":"x","name":"X","downloadURL":"https://example.com/x.deltaskin"\#(extra)}"#
        return try JSONDecoder().decode(SkinCatalogEntry.self, from: Data(json.utf8))
    }

    func testDecodesMergedFrom() throws {
        let merged = try decode(#","mergedFrom":["a","b","c"]"#)
        XCTAssertEqual(merged.mergedFrom, ["a", "b", "c"], "base first, as the feed writes it")
        XCTAssertTrue(merged.isMerged)
    }

    func testAbsentEmptyAndMistypedMergedFromMeanNotMerged() throws {
        for extra in ["", #","mergedFrom":null"#, #","mergedFrom":[]"#, #","mergedFrom":"a,b""#, #","mergedFrom":[1,2]"#] {
            let entry = try decode(extra)
            XCTAssertEqual(entry.mergedFrom, [], extra)
            XCTAssertFalse(entry.isMerged, extra)
        }
    }

    func testBlankMergedFromIdsAreDropped() throws {
        XCTAssertEqual(try decode(#","mergedFrom":["a","","b"]"#).mergedFrom, ["a", "b"])
    }

    func testUnknownMergedHashIsIgnored() throws {
        // `mergedHash` ships beside `mergedFrom`; the apps do not need it.
        XCTAssertEqual(try decode(#","mergedFrom":["a"],"mergedHash":"abc123""#).mergedFrom, ["a"])
    }

    func testMergedEntryDoesNotLoseTheRestOfTheFeed() throws {
        let json = """
        {"version":3,"skins":[
          {"id":"a","name":"A","downloadURL":"https://example.com/a.deltaskin","groupId":"g","groupOrder":1},
          {"id":"b","name":"B","downloadURL":"https://example.com/b.deltaskin","groupId":"g","groupOrder":2},
          {"id":"all","name":"Pad (All variants)","downloadURL":"https://example.com/all.deltaskin",
           "groupId":"g","groupOrder":0,"variantLabel":"All variants","mergedFrom":["a","b"],"mergedHash":"h"}
        ]}
        """
        let catalog = try SkinCatalog.decode(Data(json.utf8))
        XCTAssertEqual(catalog.skins.count, 3)
        XCTAssertEqual(catalog.droppedEntryCount, 0)
        XCTAssertEqual(catalog.families.count, 1)
        let family = catalog.families[0]
        XCTAssertEqual(family.members.map(\.id), ["all", "a", "b"])
        XCTAssertEqual(family.downloadPlan().urls.map(\.lastPathComponent), ["a.deltaskin", "b.deltaskin"])
    }

    func testOrdinaryEntriesAreNotMerged() {
        XCTAssertFalse(make("plain").isMerged)
        XCTAssertEqual(make("plain").mergedFrom, [])
    }

    // MARK: - Family

    func testMergedMemberSitsFirstAndIsListedSeparately() throws {
        let family = try family(mergedFamilyEntries())
        XCTAssertEqual(family.members.map(\.id), ["all", "red", "green", "blue"])
        XCTAssertEqual(family.mergedMembers.map(\.id), ["all"])
        XCTAssertEqual(family.splitMembers.map(\.id), ["red", "green", "blue"])
        XCTAssertEqual(family.label(for: family.members[0]), "All variants")
    }

    func testFamilyWithoutAMergedMemberHasNone() throws {
        let family = try family(mergedFamilyEntries().filter { !$0.isMerged })
        XCTAssertTrue(family.mergedMembers.isEmpty)
        XCTAssertEqual(family.splitMembers.count, 3)
    }

    // MARK: - Download all

    func testDownloadAllFetchesTheSplitFilesNeverNPlusOne() throws {
        let family = try family(mergedFamilyEntries())
        let plan = family.downloadPlan()
        XCTAssertEqual(plan.count, 3, "N files, not N+1")
        XCTAssertEqual(plan.entries.map(\.id), ["red", "green", "blue"])
        XCTAssertEqual(plan.urls.map(\.lastPathComponent), ["red.deltaskin", "green.deltaskin", "blue.deltaskin"])
        XCTAssertFalse(plan.entries.contains(where: \.isMerged))
    }

    func testPickingTheMergedFileInstallsOnlyIt() throws {
        let family = try family(mergedFamilyEntries())
        let merged = try XCTUnwrap(family.mergedMembers.first)
        let plan = family.downloadPlan(for: merged)
        XCTAssertEqual(plan.entries.map(\.id), ["all"])
        XCTAssertEqual(family.downloadPlan(memberIds: ["all"]).entries.map(\.id), ["all"])
    }

    func testPickingASplitMemberInstallsOnlyIt() throws {
        let family = try family(mergedFamilyEntries())
        XCTAssertEqual(family.downloadPlan(for: family.members[2]).entries.map(\.id), ["green"])
    }

    func testChoosingTheMergedFileAndItsSourcesKeepsTheSources() throws {
        // What an "install everything not installed yet" button hands over: every uninstalled id.
        let family = try family(mergedFamilyEntries())
        let all = Set(family.members.map(\.id))
        XCTAssertEqual(family.downloadPlan(memberIds: all).entries.map(\.id), ["red", "green", "blue"])
        // Even one source in the set is enough to make the merged file redundant.
        XCTAssertEqual(family.downloadPlan(memberIds: ["all", "blue"]).entries.map(\.id), ["blue"])
    }

    func testAMergedFileIsKeptBesideMembersItWasNotMergedFrom() throws {
        var entries = mergedFamilyEntries()
        entries.append(make("extra", order: 4))
        let family = try family(entries)
        XCTAssertEqual(family.downloadPlan(memberIds: ["all", "extra"]).entries.map(\.id), ["all", "extra"])
        XCTAssertEqual(family.downloadPlan().entries.map(\.id), ["red", "green", "blue", "extra"])
    }

    func testTheMergedFileIsTheOnlyChoiceWhenNoSourceIsInTheFamily() throws {
        // The split members were hidden or removed; the merged file is all that is left.
        let only = [make("all", order: 0, mergedFrom: ["red", "green"])]
        let family = try family(only)
        XCTAssertEqual(family.downloadPlan().entries.map(\.id), ["all"])
    }

    func testTheMergedFileIsTheOnlyChoiceWhenThePolicyCannotInstallTheSources() throws {
        // iCube-style: `.zip` members are not installable, the mirrored merged file is.
        let entries = [
            make("red", order: 1, url: "https://example.com/red.zip"),
            make("green", order: 2, url: "https://example.com/green.zip"),
            make("all", order: 0, url: "https://mirror.example.com/all.deltaskin", mergedFrom: ["red", "green"]),
        ]
        let policy = SkinStorePolicy(sections: [SkinStoreSection(id: "gba", title: "GBA", systemCodes: ["gba"])])
        let family = try family(entries)
        XCTAssertEqual(family.downloadPlan(policy: policy).entries.map(\.id), ["all"])
        XCTAssertEqual(family.downloadPlan().entries.map(\.id), ["red", "green"], "Provenance imports zips")
    }

    func testPolicyKeepsTheSourcesWhenTheyAreInstallable() throws {
        let policy = SkinStorePolicy(sections: [SkinStoreSection(id: "gba", title: "GBA", systemCodes: ["gba"])])
        let family = try family(mergedFamilyEntries())
        XCTAssertEqual(family.downloadPlan(policy: policy).entries.map(\.id), ["red", "green", "blue"])
    }

    func testPlanBuiltFromEntriesFollowsTheSameRule() {
        let entries = mergedFamilyEntries()
        let all = entries[3]
        XCTAssertEqual(SkinDownloadPlan(entries: [all, entries[0]]).entries.map(\.id), ["red"])
        XCTAssertEqual(SkinDownloadPlan(entries: [entries[0], all]).entries.map(\.id), ["red"], "order does not matter")
        XCTAssertEqual(SkinDownloadPlan(entries: [all]).entries.map(\.id), ["all"])
        XCTAssertEqual(SkinDownloadPlan(entries: entries).count, 3)
    }

    func testMergedFileNamingItselfAsASourceIsStillInstallable() {
        let odd = make("all", mergedFrom: ["all", "red"])
        XCTAssertEqual(SkinDownloadPlan(entries: [odd]).entries.map(\.id), ["all"])
    }

    func testExcludingInstalledNeverBringsTheMergedFileBack() throws {
        let family = try family(mergedFamilyEntries())
        let remaining = family.downloadPlan().excluding(installedIds: ["red", "green"])
        XCTAssertEqual(remaining.entries.map(\.id), ["blue"])
        XCTAssertTrue(family.downloadPlan().excluding(installedIds: ["red", "green", "blue"]).isEmpty)
    }

    func testFamilyOfOnlySplitMembersIsUnchanged() throws {
        let entries = mergedFamilyEntries().filter { !$0.isMerged }
        let family = try family(entries)
        XCTAssertEqual(family.downloadPlan().count, 3)
        XCTAssertEqual(family.downloadPlan(memberIds: ["red", "blue"]).entries.map(\.id), ["red", "blue"])
    }
}
