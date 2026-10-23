//
//  DeltaSkinGameTypeIdentifierTests.swift
//  SkinKitCoreTests
//
//  Ported from Provenance's DeltaSkinNintendoHomeConsoleTests: the game-type identifier parsing
//  half. The SystemIdentifier mapping test, the skin-token -> Dolphin button tables and the
//  thumbstick-side tests depend on PVCoreBridge and stay in Provenance.
//

import Foundation
import Testing
@testable import SkinKitCore

@Suite("Manic GameCube / Wii identifiers")
struct ManicGameCubeWiiIdentifierTests {

    @Test("Manic GameCube id parses to .gamecube", arguments: [
        "public.aoshuang.game.ngc",
        "PUBLIC.AOSHUANG.GAME.NGC",
        "ngc", "gc", "gcn", "gamecube", "GameCube", "game-cube", "nintendo gamecube"
    ])
    func gameCubeParses(raw: String) {
        #expect(DeltaSkinGameType.fromAnyString(raw) == .gamecube)
    }

    @Test("Manic Wii id parses to .wii", arguments: [
        "public.aoshuang.game.wii", "wii", "Wii"
    ])
    func wiiParses(raw: String) {
        #expect(DeltaSkinGameType.fromAnyString(raw) == .wii)
    }

    @Test("Manic identifier strings use Manic's real slugs")
    func manicIdentifierStrings() {
        #expect(DeltaSkinGameType.gamecube.manicIdentifierString == "public.aoshuang.game.ngc")
        #expect(DeltaSkinGameType.wii.manicIdentifierString == "public.aoshuang.game.wii")
        #expect(DeltaSkinGameType.gamecube.deltaIdentifierString == nil)
        #expect(DeltaSkinGameType.wii.deltaIdentifierString == nil)
    }

    @Test("Every Manic id round-trips through its own manicIdentifierString")
    func manicRoundTrip() {
        for type in [DeltaSkinGameType.gamecube, .wii] {
            let id = type.manicIdentifierString
            #expect(id != nil)
            #expect(DeltaSkinGameType.fromAnyString(id ?? "") == type)
        }
    }

    @Test("Codable decodes the Manic id and re-encodes to it")
    func codableRoundTrip() throws {
        let json = Data(#""public.aoshuang.game.ngc""#.utf8)
        let decoded = try JSONDecoder().decode(DeltaSkinGameType.self, from: json)
        #expect(decoded == .gamecube)
        let reencoded = try JSONDecoder().decode(DeltaSkinGameType.self, from: JSONEncoder().encode(decoded))
        #expect(reencoded == .gamecube)
    }

    @Test("matchesIdentifier accepts the Manic slug")
    func matchesSlug() {
        #expect(DeltaSkinGameType.gamecube.matchesIdentifier("ngc"))
        #expect(DeltaSkinGameType.gamecube.matchesIdentifier("gamecube"))
        #expect(DeltaSkinGameType.wii.matchesIdentifier("wii"))
        #expect(!DeltaSkinGameType.wii.matchesIdentifier("ngc"))
    }

    @Test("Existing short codes still resolve (no regression)")
    func noRegression() {
        #expect(DeltaSkinGameType.fromAnyString("public.aoshuang.game.ps1") == .psx)
        #expect(DeltaSkinGameType.fromAnyString("ng") == .neogeo)
        #expect(DeltaSkinGameType.fromAnyString("ngp") == .ngp)
    }
}
