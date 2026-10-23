import XCTest
@testable import SkinCatalogKit

/// Decoding against the fixture slice of the live feed. The count assertion comes first
/// everywhere: the decoder is lossy by design, so a test that only checks "the .zip entry is
/// hidden" would also pass if that entry had silently failed to decode.
final class SkinCatalogDecodingTests: XCTestCase {
    private var catalog: SkinCatalog!

    override func setUpWithError() throws {
        catalog = try SkinCatalog.decode(SkinCatalogFixture.data)
    }

    private func entry(_ id: String) throws -> SkinCatalogEntry {
        try XCTUnwrap(catalog.skins.first { $0.id == id }, "missing \(id)")
    }

    private func utcDay(_ date: Date) -> [Int?] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return [parts.year, parts.month, parts.day]
    }

    func testEveryFixtureEntryDecodes() {
        XCTAssertEqual(catalog.skins.count, SkinCatalogFixture.entryCount)
        XCTAssertEqual(catalog.droppedEntryCount, 0)
    }

    func testRootFieldsAndUnknownRootKeyIgnored() throws {
        XCTAssertEqual(catalog.version, 2)
        XCTAssertEqual(catalog.totalSkins, 1270)
        let root = try XCTUnwrap(catalog.lastUpdated)
        XCTAssertEqual(root.timeIntervalSince1970, 1_792_714_429, accuracy: 1) // 2026-10-23T00:13:49Z
    }

    func testFeedOrderIsKept() {
        XCTAssertEqual(catalog.skins.first?.id, SkinCatalogFixture.dreamcastIDs[0])
        XCTAssertEqual(catalog.skins.last?.id, SkinCatalogFixture.unknownFieldsID)
    }

    // MARK: - Grouping

    func testGroupedEntries() throws {
        let first = try entry(SkinCatalogFixture.n64PackID)
        XCTAssertEqual(first.groupId, "deltastyles:551")
        XCTAssertEqual(first.groupOrder, 1)
        let second = try entry(SkinCatalogFixture.n64PackSecondID)
        XCTAssertEqual(second.groupId, "deltastyles:551")
        XCTAssertEqual(second.groupOrder, 2)
    }

    func testUngroupedEntriesHaveNilGroup() throws {
        // Null in the feed, and absent from the hand-written old-format entry.
        for id in [SkinCatalogFixture.gameCubePocketID, SkinCatalogFixture.oldFormatID] {
            let skin = try entry(id)
            XCTAssertNil(skin.groupId, id)
            XCTAssertNil(skin.groupOrder, id)
        }
    }

    // MARK: - Hosting and file types

    func testMirrorHostedEntries() throws {
        let mirrored = try entry(SkinCatalogFixture.mirrorMameID)
        XCTAssertEqual(
            mirrored.downloadURL.absoluteString,
            "https://github.com/Provenance-Emu/skins/releases/download/mirror/7e15d04188bfa40d.manicskin"
        )
        XCTAssertEqual(mirrored.downloadURL.pathExtension, "manicskin")
        // `source` still credits the original host; the mirror is only where the bytes live.
        XCTAssertEqual(mirrored.source, "deltastyles.com")
        XCTAssertEqual(mirrored.sourceHost, "deltastyles.com")

        let drive = try entry(SkinCatalogFixture.mirroredDriveID)
        XCTAssertEqual(drive.downloadURL.pathExtension, "deltaskin")
    }

    func testManicAndDeltaExtensions() throws {
        XCTAssertEqual(try entry(SkinCatalogFixture.gameCubePocketID).downloadURL.pathExtension, "manicskin")
        XCTAssertEqual(try entry(SkinCatalogFixture.miniMameID).downloadURL.pathExtension, "deltaskin")
    }

    func testURLWithRawSpacesDecodes() throws {
        let gba = try entry(SkinCatalogFixture.gbaSpaceURLID)
        // `lastPathComponent` is percent-decoded; the request string is what must carry the encoding.
        XCTAssertEqual(gba.downloadURL.lastPathComponent, "328 Black GBA.deltaskin")
        XCTAssertTrue(gba.downloadURL.absoluteString.hasSuffix("328%20Black%20GBA.deltaskin"), gba.downloadURL.absoluteString)
        let n64 = try entry(SkinCatalogFixture.n64SpaceURLID)
        XCTAssertEqual(n64.downloadURL.host, "deltastyles.com")
        XCTAssertEqual(n64.downloadURL.pathExtension, "deltaskin")
    }

    func testExtensionlessAndZipURLsDecode() throws {
        XCTAssertEqual(try entry(SkinCatalogFixture.googleDriveID).downloadURL.host, "drive.google.com")
        XCTAssertEqual(try entry(SkinCatalogFixture.gbaZipID).downloadURL.pathExtension, "zip")
    }

    // MARK: - Optional fields

    func testNullFieldsDecodeAsNil() throws {
        let pocket = try entry(SkinCatalogFixture.gameCubePocketID)
        XCTAssertEqual(pocket.name, "GameCube Pocket")
        XCTAssertEqual(pocket.author, "starvingartist")
        XCTAssertNil(pocket.version)
        XCTAssertNil(pocket.rating)
        XCTAssertNil(pocket.fileSize)
        XCTAssertEqual(pocket.screenshotURLs, [])
        XCTAssertEqual(pocket.deviceSupport, [])
    }

    func testOldFormatEntryWithOnlyRequiredKeys() throws {
        let old = try entry(SkinCatalogFixture.oldFormatID)
        XCTAssertEqual(old.systems, ["gamecube"])
        XCTAssertNil(old.author)
        XCTAssertNil(old.gameTypeIdentifier)
        XCTAssertNil(old.thumbnailURL)
        XCTAssertNil(old.description)
        XCTAssertNil(old.lastUpdated)
        XCTAssertEqual(old.tags, [])
        XCTAssertEqual(old.screenshotURLs, [])
    }

    func testUnknownAndMistypedFieldsAreIgnoredNotFatal() throws {
        let skin = try entry(SkinCatalogFixture.unknownFieldsID)
        XCTAssertNil(skin.rating, "a string where a number belongs drops the field")
        XCTAssertNil(skin.downloadCount)
        XCTAssertNil(skin.groupId, "a number where a string belongs drops the field")
        XCTAssertNil(skin.groupOrder)
        XCTAssertEqual(skin.systems, ["wii"])
        // Unknown keys on real entries too.
        XCTAssertEqual(try entry(SkinCatalogFixture.mirroredDriveID).name, "Anime Icons: Vegito Blue (Dragon Ball Super)")
    }

    func testDescriptionIsOptional() throws {
        XCTAssertNotNil(try entry(SkinCatalogFixture.dreamcastIDs[0]).description)
        XCTAssertNil(try entry(SkinCatalogFixture.gameCubePocketID).description)
    }

    // MARK: - Dates

    func testDateOnlyLastUpdatedParses() throws {
        let dreamsicle = try entry(SkinCatalogFixture.dreamcastIDs[0])
        XCTAssertEqual(utcDay(try XCTUnwrap(dreamsicle.lastUpdated)), [2025, 9, 23])
    }

    func testFullISOSubmittedAtParses() throws {
        let submitted = try XCTUnwrap(try entry(SkinCatalogFixture.n64DeltaTypeID).submittedAt)
        XCTAssertEqual(utcDay(submitted), [2026, 3, 15])
    }

    func testUnparseableDatesBecomeNil() {
        XCTAssertNil(SkinCatalogDates.parse("2025-13-45"))
        XCTAssertNil(SkinCatalogDates.parse("yesterday"))
        XCTAssertNil(SkinCatalogDates.parse(""))
        XCTAssertNil(SkinCatalogDates.parse(nil))
        XCTAssertNotNil(SkinCatalogDates.parse("2026-10-04T05:11:24.250Z"))
    }

    // MARK: - Systems, game type, source (the iCube additions)

    func testSystemsAreNormalisedForComparison() throws {
        let threeDS = try entry(SkinCatalogFixture.threeDSID)
        XCTAssertEqual(threeDS.systems, ["threeDS"])
        XCTAssertEqual(threeDS.normalizedSystems, ["threeds"])
        XCTAssertEqual(try entry(SkinCatalogFixture.mixedCaseGameCubeID).normalizedSystems, ["gamecube"])
    }

    func testGameTypeSuffix() throws {
        XCTAssertEqual(try entry(SkinCatalogFixture.gameCubePocketID).gameTypeSuffix, "ngc")
        XCTAssertEqual(try entry(SkinCatalogFixture.n64DeltaTypeID).gameTypeSuffix, "n64")
        XCTAssertNil(try entry(SkinCatalogFixture.dreamcastIDs[0]).gameTypeSuffix)
        let blank = SkinCatalogEntry(
            id: "b", name: "b", systems: [], gameTypeIdentifier: "  ", downloadURL: URL(string: "https://e.com/b.deltaskin")!
        )
        XCTAssertNil(blank.gameTypeSuffix)
    }

    func testSourceHost() throws {
        XCTAssertEqual(try entry(SkinCatalogFixture.gameCubePocketID).sourceHost, "deltastyles.com")
        // `owner/repo` is not a host: fall back to the download URL's host.
        XCTAssertEqual(try entry(SkinCatalogFixture.repoSourceID).source, "LitRitt/emuskins")
        XCTAssertEqual(try entry(SkinCatalogFixture.repoSourceID).sourceHost, "raw.githubusercontent.com")
        // ...with a leading `www.` dropped.
        XCTAssertEqual(try entry(SkinCatalogFixture.mixedCaseGameCubeID).sourceHost, "example.com")
    }

    // MARK: - Lossy decoding of malformed entries

    func testBadEntryIsDroppedNotFatal() throws {
        let json = #"""
        {
          "version": 2,
          "lastUpdated": "not a date",
          "skins": [
            { "id": "good", "name": "Good", "systems": ["gamecube"],
              "downloadURL": "https://example.com/good.manicskin", "rating": "five stars" },
            { "id": "no-url", "name": "No URL", "systems": ["gamecube"] },
            { "id": 42, "name": "Numeric id", "systems": ["gamecube"],
              "downloadURL": "https://example.com/x.manicskin" },
            { "id": "no-name", "systems": ["gamecube"], "downloadURL": "https://example.com/n.manicskin" },
            { "id": "blank-url", "name": "Blank URL", "downloadURL": "   " },
            "not even an object",
            null,
            { "id": "no-systems", "name": "No systems",
              "downloadURL": "https://example.com/y.deltaskin", "lastUpdated": "2025-13-45" }
          ]
        }
        """#
        let decoded = try SkinCatalog.decode(Data(json.utf8))
        XCTAssertEqual(decoded.skins.map(\.id), ["good", "no-systems"])
        XCTAssertEqual(decoded.droppedEntryCount, 6)
        XCTAssertNil(decoded.lastUpdated)
        XCTAssertNil(decoded.skins[0].rating, "a mistyped optional drops the field, not the entry")
        XCTAssertEqual(decoded.skins[1].systems, [])
        XCTAssertNil(decoded.skins[1].lastUpdated)
    }

    func testMissingSkinsKeyIsAnEmptyCatalog() throws {
        let decoded = try SkinCatalog.decode(Data(#"{"version": 2}"#.utf8))
        XCTAssertEqual(decoded.skins.count, 0)
        XCTAssertEqual(decoded.droppedEntryCount, 0)
    }

    func testNonCatalogJSONThrowsDecodingError() {
        for bad in ["[1, 2, 3]", "<html>", "", #"{"skins": "nope"}"#] {
            XCTAssertThrowsError(try SkinCatalog.decode(Data(bad.utf8)), bad) { error in
                guard case SkinCatalogError.decoding = error else {
                    return XCTFail("unexpected \(error) for \(bad)")
                }
            }
        }
    }

    func testServiceDecodeForwardsToCatalogDecode() throws {
        let viaService = try SkinCatalogService.decode(SkinCatalogFixture.data)
        XCTAssertEqual(viaService.skins.count, SkinCatalogFixture.entryCount)
    }

    func testErrorDescriptionsAndLocalizationHook() {
        XCTAssertEqual(
            SkinCatalogError.httpStatus(503).errorDescription,
            "The skin catalog server answered with HTTP 503."
        )
        XCTAssertEqual(
            SkinCatalogError.network("offline").errorDescription,
            "The skin catalog could not be downloaded: offline"
        )
        XCTAssertEqual(
            SkinCatalogError.decoding("bad").message(localizing: { $0.uppercased() }),
            "THE SKIN CATALOG COULD NOT BE READ: bad"
        )
        XCTAssertEqual(
            URLSessionSkinStoreDownloader.HTTPStatusError(statusCode: 404).errorDescription,
            "The skin's host answered with HTTP 404."
        )
    }
}
