//
//  DeltaSkinArcadeGameTypeTests.swift
//  SkinKitCoreTests
//
//  The NAOMI, NAOMI 2 and Atomiswave game types iFly's Dreamcast-derived arcade skins declare.
//  Arcade skins already installed on devices carry these exact strings, so they have to keep parsing.
//

import Foundation
import Testing
@testable import SkinKitCore

@Suite("Arcade game types")
struct DeltaSkinArcadeGameTypeTests {

    @Test("Manic arcade ids and aliases parse", arguments: [
        ("public.aoshuang.game.naomi", DeltaSkinGameType.naomi),
        ("naomi", .naomi),
        ("Naomi", .naomi),
        ("public.aoshuang.game.naomi2", .naomi2),
        ("naomi2", .naomi2),
        ("naomi-2", .naomi2),
        ("public.aoshuang.game.aw", .atomiswave),
        ("aw", .atomiswave),
        ("atomiswave", .atomiswave),
        ("Atomiswave", .atomiswave),
    ])
    func parses(raw: String, expected: DeltaSkinGameType) {
        #expect(DeltaSkinGameType.fromAnyString(raw) == expected)
    }

    @Test("Manic identifier strings are the ones iFly writes")
    func manicIdentifierStrings() {
        #expect(DeltaSkinGameType.naomi.manicIdentifierString == "public.aoshuang.game.naomi")
        #expect(DeltaSkinGameType.naomi2.manicIdentifierString == "public.aoshuang.game.naomi2")
        #expect(DeltaSkinGameType.atomiswave.manicIdentifierString == "public.aoshuang.game.aw")
        for type in [DeltaSkinGameType.naomi, .naomi2, .atomiswave] {
            #expect(type.deltaIdentifierString == nil)
        }
    }

    @Test("Every arcade id round-trips through its own manicIdentifierString and Codable")
    func roundTrip() throws {
        for type in [DeltaSkinGameType.naomi, .naomi2, .atomiswave] {
            let id = try #require(type.manicIdentifierString)
            #expect(DeltaSkinGameType.fromAnyString(id) == type)
            let encoded = try JSONEncoder().encode(type)
            #expect(try JSONDecoder().decode(DeltaSkinGameType.self, from: encoded) == type)
        }
    }

    @Test("matchesIdentifier accepts the slugs")
    func matches() {
        #expect(DeltaSkinGameType.naomi.matchesIdentifier("naomi"))
        #expect(DeltaSkinGameType.naomi2.matchesIdentifier("naomi2"))
        #expect(DeltaSkinGameType.atomiswave.matchesIdentifier("aw"))
        #expect(DeltaSkinGameType.atomiswave.matchesIdentifier("atomiswave"))
        #expect(!DeltaSkinGameType.naomi.matchesIdentifier("naomi2"))
    }

    @Test("They sort right after the Dreamcast")
    func ordering() {
        #expect(DeltaSkinGameType.dreamcast < .naomi)
        #expect(DeltaSkinGameType.naomi < .naomi2)
        #expect(DeltaSkinGameType.naomi2 < .atomiswave)
        #expect(DeltaSkinGameType.atomiswave < .genesis)
    }

    @Test("An arcade skin decodes with its game type")
    func skinInfoDecodes() throws {
        let json = Data(#"{"identifier":"x","name":"x","gameTypeIdentifier":"public.aoshuang.game.naomi"}"#.utf8)
        struct Wrapper: Decodable { let gameTypeIdentifier: DeltaSkinGameType }
        #expect(try JSONDecoder().decode(Wrapper.self, from: json).gameTypeIdentifier == .naomi)
    }
}
