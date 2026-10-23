import XCTest
@testable import SkinCatalogKit

/// iFly's and iCube's store behaviour, reproduced from the two `SkinStorePolicy` presets against
/// the fixture feed, plus the rules both share and a hand-built config to show the policy is
/// really configuration.
final class SkinStorePolicyTests: XCTestCase {
    private var catalog: SkinCatalog!

    override func setUpWithError() throws {
        catalog = try SkinCatalog.decode(SkinCatalogFixture.data)
        // Guard against the lossy decoder making every "is hidden" test vacuous.
        XCTAssertEqual(catalog.skins.count, SkinCatalogFixture.entryCount)
    }

    private func section(_ id: String, _ policy: SkinStorePolicy) throws -> SkinStoreSection? {
        let entry = try XCTUnwrap(catalog.skins.first { $0.id == id }, "missing \(id)")
        return policy.section(for: entry)
    }

    private func entry(
        id: String = "x",
        systems: [String],
        gameType: String? = nil,
        url: String
    ) throws -> SkinCatalogEntry {
        try SkinCatalogEntry(
            id: id,
            name: id,
            systems: systems,
            gameTypeIdentifier: gameType,
            downloadURL: XCTUnwrap(URL(string: url))
        )
    }

    // MARK: - iFly, from the feed

    func testIFlyShowsAllThreeDreamcastSkins() throws {
        for id in SkinCatalogFixture.dreamcastIDs {
            XCTAssertEqual(try section(id, .iFly), .dreamcast, id)
        }
    }

    func testIFlyInstallableMameSkinsAreArcade() throws {
        // Mirror-hosted .manicskin, Mini Mame (.deltaskin), Mortal Kombat 1992.
        for id in [SkinCatalogFixture.mirrorMameID, SkinCatalogFixture.miniMameID, SkinCatalogFixture.mortalKombatID] {
            XCTAssertEqual(try section(id, .iFly), .arcade, id)
        }
    }

    func testIFlyHidesSharpX1DespiteMameCode() throws {
        XCTAssertNil(try section(SkinCatalogFixture.sharpX1ID, .iFly))
        XCTAssertNotNil(try section(SkinCatalogFixture.sharpX1ID, SkinStorePolicy(sections: [.arcade])))
    }

    func testIFlyRetargetSystemsAreOtherSystems() throws {
        let ids = [
            SkinCatalogFixture.saturnID,
            SkinCatalogFixture.n64SpaceURLID,
            SkinCatalogFixture.gameCubePocketID,
            SkinCatalogFixture.psxID,
            SkinCatalogFixture.genesisID,
        ]
        for id in ids {
            XCTAssertEqual(try section(id, .iFly), .otherSystems, id)
        }
    }

    func testIFlyHidesZipExtensionlessAndUnlistedSystems() throws {
        XCTAssertNil(try section(SkinCatalogFixture.n64ZipID, .iFly), "n64 .zip")
        XCTAssertNil(try section(SkinCatalogFixture.gbaZipID, .iFly), "gba .zip")
        XCTAssertNil(try section(SkinCatalogFixture.googleDriveID, .iFly), "Google Drive link")
        XCTAssertNil(try section(SkinCatalogFixture.gbaSpaceURLID, .iFly), "gba")
        XCTAssertNil(try section(SkinCatalogFixture.threeDSID, .iFly), "threeDS")
        XCTAssertNil(try section(SkinCatalogFixture.unofficialID, .iFly), "unofficial placeholder")
        XCTAssertNil(try SkinStorePolicy.iFly.section(for: entry(systems: ["dreamcast"], url: "https://example.com/skin")))
    }

    func testIFlyIgnoresGameTypeIdentifier() throws {
        // Declared Wii, no systems: iFly has no Wii shelf and doesn't read the identifier.
        XCTAssertNil(try section(SkinCatalogFixture.wiiGameTypeOnlyID, .iFly))
        XCTAssertNil(try SkinStorePolicy.iFly.section(for: entry(
            systems: [], gameType: "public.aoshuang.game.dc", url: "https://e.com/a.manicskin"
        )))
    }

    func testIFlyFixtureSections() {
        let grouped = SkinStorePolicy.iFly.sections(for: catalog.skins)
        XCTAssertEqual(grouped.map(\.section), [.dreamcast, .arcade, .otherSystems])
        XCTAssertEqual(grouped[0].entries.map(\.id), SkinCatalogFixture.dreamcastIDs)
        XCTAssertEqual(grouped[1].entries.map(\.id), [
            SkinCatalogFixture.mirrorMameID, SkinCatalogFixture.miniMameID, SkinCatalogFixture.mortalKombatID,
        ])
        XCTAssertEqual(grouped[2].entries.map(\.id), [
            SkinCatalogFixture.gameCubePocketID,
            SkinCatalogFixture.n64PackID, SkinCatalogFixture.n64PackSecondID,
            SkinCatalogFixture.n64DeltaTypeID, SkinCatalogFixture.n64SpaceURLID,
            SkinCatalogFixture.saturnID, SkinCatalogFixture.psxID,
            SkinCatalogFixture.genesisID, SkinCatalogFixture.genesisPackID,
            SkinCatalogFixture.mixedCaseGameCubeID, SkinCatalogFixture.oldFormatID,
        ], "feed order kept within a shelf")
    }

    func testIFlyRules() throws {
        XCTAssertEqual(
            try SkinStorePolicy.iFly.section(for: entry(systems: ["Dreamcast"], url: "https://example.com/A.DeltaSkin")),
            .dreamcast
        )
        XCTAssertEqual(
            try SkinStorePolicy.iFly.section(for: entry(systems: ["MAME"], url: "https://example.com/a.MANICSKIN")),
            .arcade
        )
        XCTAssertEqual(
            try SkinStorePolicy.iFly.section(for: entry(systems: ["unknown", "saturn"], url: "https://e.com/a.manicskin")),
            .otherSystems
        )
        // Dreamcast, then arcade, then a retarget system.
        XCTAssertEqual(
            try SkinStorePolicy.iFly.section(for: entry(systems: ["n64", "mame", "dreamcast"], url: "https://e.com/a.deltaskin")),
            .dreamcast
        )
        XCTAssertEqual(
            try SkinStorePolicy.iFly.section(for: entry(systems: ["n64", "mame"], url: "https://e.com/a.deltaskin")),
            .arcade
        )
        XCTAssertEqual(SkinStorePolicy.iFly.sections, [.dreamcast, .arcade, .otherSystems])
    }

    func testIFlyOrderedSectionsAndEmptySectionsOmitted() throws {
        let entries = try [
            entry(id: "o", systems: ["psx"], url: "https://e.com/o.manicskin"),
            entry(id: "d", systems: ["dreamcast"], url: "https://e.com/d.manicskin"),
        ]
        XCTAssertEqual(SkinStorePolicy.iFly.sections(for: entries).map(\.section), [.dreamcast, .otherSystems])
    }

    func testIFlyRetargetRouting() {
        let policy = SkinStorePolicy.iFly
        // Dreamcast: as-is when the skin already declares a type iFly shows, else the Dreamcast pad.
        XCTAssertNil(policy.retarget(for: .dreamcast, isSupportedGameType: true))
        XCTAssertEqual(policy.retarget(for: .dreamcast, isSupportedGameType: false), "dreamcast")
        // Arcade: always, whatever the skin declares.
        XCTAssertEqual(policy.retarget(for: .arcade, isSupportedGameType: true), "arcade")
        XCTAssertEqual(policy.retarget(for: .arcade, isSupportedGameType: false), "arcade")
        // Other systems: always the Dreamcast pad.
        XCTAssertEqual(policy.retarget(for: .otherSystems, isSupportedGameType: true), "dreamcast")
        XCTAssertEqual(policy.retarget(for: .otherSystems, isSupportedGameType: false), "dreamcast")
    }

    func testIFlySectionTitles() {
        XCTAssertEqual(SkinStorePolicy.iFly.sections.map(\.title), ["Dreamcast", "Arcade", "From Other Systems"])
    }

    // MARK: - iCube, from the feed

    func testICubeGameCubeAndWiiEntriesLandOnTheirShelves() throws {
        XCTAssertEqual(try section(SkinCatalogFixture.gameCubePocketID, .iCube), .gameCube)
        XCTAssertEqual(try section(SkinCatalogFixture.mixedCaseGameCubeID, .iCube), .gameCube, "codes compare lowercased")
        XCTAssertEqual(try section(SkinCatalogFixture.oldFormatID, .iCube), .gameCube)
        XCTAssertEqual(try section(SkinCatalogFixture.unknownFieldsID, .iCube), .wii)
    }

    func testICubeGameTypeSuffixPlacesAnEntryWithoutSystems() throws {
        XCTAssertEqual(try section(SkinCatalogFixture.wiiGameTypeOnlyID, .iCube), .wii)
        let cases: [(String, SkinStoreSection?)] = [
            ("public.aoshuang.game.ngc", .gameCube),
            ("public.aoshuang.game.gc", .gameCube),
            ("com.example.GameCube", .gameCube),
            ("com.rileytestut.delta.game.wii", .wii),
            ("com.rileytestut.delta.game.n64", .nintendo64),
            ("com.rileytestut.delta.game.gba", nil),
        ]
        for (gameType, expected) in cases {
            XCTAssertEqual(
                try SkinStorePolicy.iCube.section(for: entry(systems: [], gameType: gameType, url: "https://e.com/a.deltaskin")),
                expected,
                gameType
            )
        }
    }

    func testICubeN64SkinsLandOnTheN64Shelf() throws {
        XCTAssertEqual(try section(SkinCatalogFixture.n64PackID, .iCube), .nintendo64)
        XCTAssertEqual(try section(SkinCatalogFixture.n64SpaceURLID, .iCube), .nintendo64)
        XCTAssertEqual(try section(SkinCatalogFixture.n64DeltaTypeID, .iCube), .nintendo64)
    }

    func testICubeHidesZipExtensionlessAndOtherSystems() throws {
        XCTAssertNil(try section(SkinCatalogFixture.n64ZipID, .iCube), "an N64 .zip")
        XCTAssertNil(try section(SkinCatalogFixture.gbaZipID, .iCube))
        XCTAssertNil(try section(SkinCatalogFixture.googleDriveID, .iCube))
        XCTAssertNil(try section(SkinCatalogFixture.threeDSID, .iCube))
        XCTAssertNil(try section(SkinCatalogFixture.gbaSpaceURLID, .iCube))
        XCTAssertNil(try section(SkinCatalogFixture.unofficialID, .iCube))
        // iCube has no hidden-id list: Sharp X1 is just an unlisted system there.
        XCTAssertNil(try section(SkinCatalogFixture.sharpX1ID, .iCube))
        XCTAssertNil(try SkinStorePolicy.iCube.section(for: entry(systems: ["gamecube"], url: "https://example.com/skin")))
    }

    func testICubeFixtureSections() {
        let grouped = SkinStorePolicy.iCube.sections(for: catalog.skins)
        XCTAssertEqual(grouped.map(\.section), [.gameCube, .wii, .nintendo64])
        XCTAssertEqual(grouped[0].entries.map(\.id), [
            SkinCatalogFixture.gameCubePocketID, SkinCatalogFixture.mixedCaseGameCubeID, SkinCatalogFixture.oldFormatID,
        ], "feed order kept")
        XCTAssertEqual(grouped[1].entries.map(\.id), [SkinCatalogFixture.wiiGameTypeOnlyID, SkinCatalogFixture.unknownFieldsID])
        XCTAssertEqual(grouped[2].entries.map(\.id), [
            SkinCatalogFixture.n64PackID, SkinCatalogFixture.n64PackSecondID,
            SkinCatalogFixture.n64DeltaTypeID, SkinCatalogFixture.n64SpaceURLID,
        ])
    }

    func testICubeRules() throws {
        XCTAssertEqual(
            try SkinStorePolicy.iCube.section(for: entry(systems: ["GameCube"], url: "https://example.com/A.DeltaSkin")),
            .gameCube
        )
        XCTAssertEqual(
            try SkinStorePolicy.iCube.section(for: entry(systems: ["WII"], url: "https://example.com/a.MANICSKIN")),
            .wii
        )
        XCTAssertEqual(
            try SkinStorePolicy.iCube.section(for: entry(systems: ["unknown", "n64"], url: "https://e.com/a.manicskin")),
            .nintendo64
        )
        // GameCube, then Wii, then N64.
        XCTAssertEqual(
            try SkinStorePolicy.iCube.section(for: entry(systems: ["n64", "wii", "gamecube"], url: "https://e.com/a.deltaskin")),
            .gameCube
        )
        XCTAssertEqual(
            try SkinStorePolicy.iCube.section(for: entry(systems: ["n64", "wii"], url: "https://e.com/a.deltaskin")),
            .wii
        )
        XCTAssertEqual(SkinStorePolicy.iCube.sections, [.gameCube, .wii, .nintendo64])
    }

    func testICubeOrderedSectionsAndEmptySectionsOmitted() throws {
        let entries = try [
            entry(id: "n", systems: ["n64"], url: "https://e.com/n.deltaskin"),
            entry(id: "g", systems: ["gamecube"], url: "https://e.com/g.manicskin"),
        ]
        XCTAssertEqual(SkinStorePolicy.iCube.sections(for: entries).map(\.section), [.gameCube, .nintendo64])
    }

    func testICubeRetargetOnlyForTheN64Shelf() {
        let policy = SkinStorePolicy.iCube
        for supported in [true, false] {
            XCTAssertNil(policy.retarget(for: .gameCube, isSupportedGameType: supported))
            XCTAssertNil(policy.retarget(for: .wii, isSupportedGameType: supported))
            XCTAssertEqual(policy.retarget(for: .nintendo64, isSupportedGameType: supported), "gamecube")
        }
    }

    // MARK: - Shared rules

    func testDownloadFileNameUsesEntryIdAndURLExtension() throws {
        for policy in [SkinStorePolicy.iFly, .iCube] {
            let pocket = try XCTUnwrap(catalog.skins.first { $0.id == SkinCatalogFixture.gameCubePocketID })
            XCTAssertEqual(policy.downloadFileName(for: pocket), "ea60f2003d82ac9e.manicskin")
            let mini = try XCTUnwrap(catalog.skins.first { $0.id == SkinCatalogFixture.miniMameID })
            XCTAssertEqual(policy.downloadFileName(for: mini), "67d260708ffa7d09.deltaskin")
            XCTAssertEqual(
                try policy.downloadFileName(for: entry(id: "a/b:c", systems: [], url: "https://e.com/x.ManicSkin")),
                "a-b-c.manicskin"
            )
            XCTAssertEqual(
                try policy.downloadFileName(for: entry(id: " / ", systems: [], url: "https://e.com/x.deltaskin")),
                "skin.deltaskin"
            )
            XCTAssertNil(try policy.downloadFileName(for: entry(systems: [], url: "https://e.com/x.zip")))
        }
    }

    func testSectionEqualityIsByID() {
        var renamed = SkinStoreSection.dreamcast
        renamed.title = "Sega Dreamcast"
        XCTAssertEqual(renamed, .dreamcast)
        XCTAssertEqual(Set([renamed, .dreamcast]).count, 1)
        XCTAssertNotEqual(SkinStoreSection.gameCube, .wii)
    }

    // MARK: - Policy is configuration

    func testAppSuppliedPolicyNeedsNoChangeToTheKit() throws {
        let saturn = SkinStoreSection(
            id: "saturn",
            title: "Saturn",
            systemCodes: ["SATURN"],
            retarget: .unlessSupported("saturn")
        )
        let genesis = SkinStoreSection(id: "genesis", title: "Genesis", systemCodes: ["genesis", "psx"])
        let policy = SkinStorePolicy(
            sections: [genesis, saturn],
            placeholderSystemCodes: ["psx"],
            hiddenEntryIds: [SkinCatalogFixture.genesisPackID],
            installableExtensions: ["MANICSKIN"],
            gameTypeSuffixSystemCodes: ["sat": "saturn"]
        )
        XCTAssertEqual(saturn.systemCodes, ["saturn"], "codes are lowercased")
        let grouped = policy.sections(for: catalog.skins)
        XCTAssertEqual(grouped.map(\.section), [genesis, saturn])
        // psx is a placeholder here, genesisPack is hidden, .deltaskin is not installable.
        XCTAssertEqual(grouped[0].entries.map(\.id), [SkinCatalogFixture.genesisID])
        XCTAssertEqual(grouped[1].entries.map(\.id), [SkinCatalogFixture.saturnID])
        XCTAssertEqual(
            try policy.section(for: entry(systems: [], gameType: "x.y.SAT", url: "https://e.com/a.manicskin")),
            saturn
        )
        XCTAssertNil(try policy.section(for: entry(systems: ["saturn"], url: "https://e.com/a.deltaskin")))
        XCTAssertEqual(policy.retarget(for: saturn, isSupportedGameType: false), "saturn")
        XCTAssertNil(policy.retarget(for: saturn, isSupportedGameType: true))
    }

    func testDefaultsMatchBothApps() {
        XCTAssertEqual(SkinStorePolicy.defaultInstallableExtensions, ["deltaskin", "manicskin"])
        XCTAssertEqual(SkinStorePolicy.defaultPlaceholderSystemCodes, ["unofficial", "unsupported", "unknown"])
        XCTAssertEqual(SkinStorePolicy.iFly.installableExtensions, SkinStorePolicy.iCube.installableExtensions)
        XCTAssertEqual(SkinStorePolicy.iFly.placeholderSystemCodes, SkinStorePolicy.iCube.placeholderSystemCodes)
    }

    func testSystemCodesDropPlaceholdersAndAddGameTypeCode() throws {
        let skin = try entry(systems: ["Unknown", "N64"], gameType: "public.aoshuang.game.ngc", url: "https://e.com/a.deltaskin")
        XCTAssertEqual(SkinStorePolicy.iCube.systemCodes(for: skin), ["n64", "gamecube"])
        XCTAssertEqual(SkinStorePolicy.iFly.systemCodes(for: skin), ["n64"])
    }
}

// MARK: - Device filtering (iFly)

final class SkinStoreDeviceTests: XCTestCase {
    private func entry(_ name: String, tags: [String] = [], devices: [String] = []) -> SkinCatalogEntry {
        SkinCatalogEntry(
            id: name,
            name: name,
            systems: ["dreamcast"],
            downloadURL: URL(string: "https://example.com/\(name).deltaskin")!,
            tags: tags,
            deviceSupport: devices
        )
    }

    func testNameHintsFilterByDevice() {
        let phone = entry("Fightstick GBA Skin for iPhone")
        let pad = entry("328 Black GBA for iPad")
        let neutral = entry("Classic Pad")
        XCTAssertFalse(SkinStorePolicy.isCompatible(phone, with: .iPad))
        XCTAssertTrue(SkinStorePolicy.isCompatible(phone, with: .iPhone))
        XCTAssertFalse(SkinStorePolicy.isCompatible(pad, with: .iPhone))
        XCTAssertTrue(SkinStorePolicy.isCompatible(pad, with: .iPad))
        XCTAssertTrue(SkinStorePolicy.isCompatible(neutral, with: .iPad))
        XCTAssertTrue(SkinStorePolicy.isCompatible(neutral, with: .iPhone))
    }

    func testTagsAreHintsToo() {
        XCTAssertFalse(SkinStorePolicy.isCompatible(entry("Pad", tags: ["iPad"]), with: .iPhone))
        XCTAssertFalse(SkinStorePolicy.isCompatible(entry("Pad", tags: ["for-ipad"]), with: .iPhone))
        XCTAssertTrue(SkinStorePolicy.isCompatible(entry("Pad", tags: ["ipados"]), with: .iPhone), "whole word only")
    }

    func testNamingBothStaysVisible() {
        let both = entry("Pocket Taco for iPhone and iPad")
        XCTAssertTrue(SkinStorePolicy.isCompatible(both, with: .iPad))
        XCTAssertTrue(SkinStorePolicy.isCompatible(both, with: .iPhone))
    }

    func testDeclaredSupportWinsOverTheName() {
        let declared = entry("Skin for iPhone", devices: ["iPad"])
        XCTAssertTrue(SkinStorePolicy.isCompatible(declared, with: .iPad))
        XCTAssertFalse(SkinStorePolicy.isCompatible(declared, with: .iPhone))
        XCTAssertTrue(SkinStorePolicy.isCompatible(entry("Anything", devices: ["Universal"]), with: .iPhone))
    }

    func testNilDeviceKeepsEverything() {
        let list = [entry("for iPhone"), entry("for iPad")]
        XCTAssertEqual(SkinStorePolicy.filtered(list, for: nil).count, 2)
        XCTAssertEqual(SkinStorePolicy.filtered(list, for: .iPad).map(\.name), ["for iPad"])
    }
}
