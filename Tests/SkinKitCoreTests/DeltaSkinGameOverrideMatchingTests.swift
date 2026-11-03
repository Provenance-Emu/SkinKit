import CoreGraphics
import Foundation
import Testing
@testable import SkinKitCore

/// `gameOverrides` keys are matched against an ordered list of candidates: MD5, CRC, ROM filename, then title.
/// The fixture's overrides each have a different `mappingSize`, so the size says which entry matched.
@Suite("gameOverrides matching")
struct DeltaSkinGameOverrideMatchingTests {

    private static let baseSize = CGSize(width: 375, height: 812)
    private static let titleSize = CGSize(width: 400, height: 800)
    private static let md5Size = CGSize(width: 500, height: 900)
    private static let crcSize = CGSize(width: 520, height: 920)
    private static let fileNameSize = CGSize(width: 600, height: 1000)

    private static let md5 = "0123456789abcdef0123456789abcdef"   // the fixture stores it upper-case
    private static let md5IPadOnly = "ffffffffffffffffffffffffffffffff"

    private static func skin() throws -> DeltaSkin {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/Jaguar-GameOverrides", withExtension: "manicskin"))
        return try DeltaSkin(fileURL: url)
    }

    private static func size(_ skin: DeltaSkin, _ keys: [String], device: DeltaSkinDevice = .iphone) -> CGSize? {
        skin.mappingSize(for: DeltaSkinTraits(device: device, displayType: .standard, orientation: .portrait, gameIdentifiers: keys))
    }

    // MARK: - Precedence

    @Test("MD5 beats title when both are candidates and both have overrides")
    func md5BeatsTitle() throws {
        let skin = try Self.skin()
        #expect(Self.size(skin, [Self.md5, "Tempest 2000"]) == Self.md5Size)
        #expect(Self.size(skin, ["Tempest 2000", Self.md5]) == Self.titleSize)   // order is the caller's contract
    }

    @Test("The full ordered list resolves md5, then crc, then filename, then title")
    func fullOrder() throws {
        let skin = try Self.skin()
        func keys(md5: String?, crc: String?, file: String?, title: String?) -> [String] {
            DeltaSkinTraits.gameOverrideKeys(md5: md5, crc: crc, romFileName: file, title: title)
        }
        // Everything present: md5 wins.
        #expect(Self.size(skin, keys(md5: Self.md5, crc: "deadbeef", file: "Alien vs Predator.j64", title: "Tempest 2000")) == Self.md5Size)
        // md5 unknown: crc wins.
        #expect(Self.size(skin, keys(md5: "00000000000000000000000000000000", crc: "deadbeef", file: "Alien vs Predator.j64", title: "Tempest 2000")) == Self.crcSize)
        // md5 and crc unknown: the filename wins over the title.
        #expect(Self.size(skin, keys(md5: nil, crc: "12345678", file: "Alien vs Predator.j64", title: "Tempest 2000")) == Self.fileNameSize)
        // Only the title is known.
        #expect(Self.size(skin, keys(md5: nil, crc: nil, file: "Other.j64", title: "Tempest 2000")) == Self.titleSize)
    }

    // MARK: - Single matches

    @Test("A title-only match still works, and the single-key initializer is unchanged")
    func titleOnly() throws {
        let skin = try Self.skin()
        let single = DeltaSkinTraits(device: .iphone, displayType: .standard, orientation: .portrait, gameIdentifier: "Tempest 2000")
        #expect(skin.mappingSize(for: single) == Self.titleSize)
        #expect(single.gameIdentifier == "Tempest 2000")
        #expect(single.gameIdentifiers == ["Tempest 2000"])
        #expect(Self.size(skin, ["Tempest 2000"]) == Self.titleSize)
    }

    @Test("An md5-only match works")
    func md5Only() throws {
        #expect(Self.size(try Self.skin(), [Self.md5]) == Self.md5Size)
    }

    @Test("Matching is case-insensitive, and the exact spelling is not required")
    func caseInsensitive() throws {
        let skin = try Self.skin()
        #expect(Self.size(skin, ["TEMPEST 2000"]) == Self.titleSize)
        #expect(Self.size(skin, ["tempest 2000"]) == Self.titleSize)
        #expect(Self.size(skin, [Self.md5.uppercased()]) == Self.md5Size)
        #expect(Self.size(skin, [Self.md5]) == Self.md5Size)
        #expect(Self.size(skin, ["DeadBeef"]) == Self.crcSize)
    }

    @Test("A ROM filename matches with its extension or, for a key without one, by its stem")
    func fileName() throws {
        let skin = try Self.skin()
        let keys = DeltaSkinTraits.gameOverrideKeys(romFileName: "Alien vs Predator.j64")
        #expect(keys == ["Alien vs Predator.j64", "Alien vs Predator"])
        #expect(Self.size(skin, keys) == Self.fileNameSize)
        #expect(Self.size(skin, ["Alien vs Predator.J64"]) == Self.fileNameSize)
    }

    // MARK: - Fallbacks

    @Test("No match falls back to the base representation")
    func noMatch() throws {
        let skin = try Self.skin()
        #expect(Self.size(skin, ["Unknown Game", "00000000000000000000000000000000"]) == Self.baseSize)
        #expect(Self.size(skin, []) == Self.baseSize)
        let plain = DeltaSkinTraits(device: .iphone, displayType: .standard, orientation: .portrait)
        #expect(skin.mappingSize(for: plain) == Self.baseSize)
        #expect(skin.representation(for: plain)?.items?.count == 1)
    }

    @Test("A candidate with no override for this device is skipped, and the next candidate is tried")
    func candidateForOtherDeviceIsSkipped() throws {
        let skin = try Self.skin()
        // Both keys exist in the fixture, but only for iPad: an iPhone lookup passes over them.
        #expect(Self.size(skin, [Self.md5IPadOnly, "Tempest 2000"]) == Self.titleSize)
        #expect(Self.size(skin, [Self.md5IPadOnly, "Cybermorph"]) == Self.baseSize)
        // On iPad the same list resolves to the iPad override.
        #expect(Self.size(skin, [Self.md5IPadOnly, "Tempest 2000"], device: .ipad) == CGSize(width: 710, height: 1010))
    }

    @Test("An override replaces the representation as a whole")
    func overrideReplacesItems() throws {
        let skin = try Self.skin()
        let traits = DeltaSkinTraits(device: .iphone, displayType: .standard, orientation: .portrait, gameIdentifiers: ["Tempest 2000"])
        #expect(skin.representation(for: traits)?.items?.count == 2)
    }

    @Test("The representation cache keeps different candidate lists apart")
    func cacheKeyCoversTheList() throws {
        let skin = try Self.skin()
        DeltaSkin.clearRepresentationCache()
        #expect(Self.size(skin, ["Tempest 2000"]) == Self.titleSize)
        #expect(Self.size(skin, [Self.md5, "Tempest 2000"]) == Self.md5Size)
        #expect(Self.size(skin, ["Tempest 2000"]) == Self.titleSize)
        #expect(Self.size(skin, ["Nope"]) == Self.baseSize)
        DeltaSkin.clearRepresentationCache()
    }

    @Test("A key that contains a separator character cannot collide with a two-key list in the cache")
    func cacheKeyIsUnambiguous() throws {
        let skin = try Self.skin()
        DeltaSkin.clearRepresentationCache()
        // Two keys, the first with an override.
        #expect(Self.size(skin, ["Tempest 2000", "Nope"]) == Self.titleSize)
        // One key whose text embeds the old separator and the second key: matches nothing, so it is the base layout.
        #expect(Self.size(skin, ["Tempest 2000\u{1F}Nope"]) == Self.baseSize)
        #expect(Self.size(skin, ["Tempest 2000\u{1F}Nope"]) == Self.baseSize)
        // Length-prefix lookalikes.
        #expect(Self.size(skin, ["Tempest 2000", "1:x"]) == Self.titleSize)
        #expect(Self.size(skin, ["Tempest 2000" + "12:Tempest 2000"]) == Self.baseSize)
        DeltaSkin.clearRepresentationCache()
    }

    // MARK: - Building and coding the list

    @Test("gameOverrideKeys orders md5, crc, filename, title and drops empty and repeated values")
    func keyOrdering() {
        #expect(DeltaSkinTraits.gameOverrideKeys(md5: "AA", crc: "BB", romFileName: "Game.bin", title: "Game")
                == ["AA", "BB", "Game.bin", "Game"])
        #expect(DeltaSkinTraits.gameOverrideKeys(md5: "", crc: nil, romFileName: "  ", title: "T") == ["T"])
        #expect(DeltaSkinTraits.gameOverrideKeys(md5: nil, crc: nil, romFileName: nil, title: nil).isEmpty)
        // A filename with no extension, or one equal to the title, is not listed twice.
        #expect(DeltaSkinTraits.gameOverrideKeys(romFileName: "Game", title: "Game") == ["Game"])
    }

    @Test("Traits keep both initializer forms, compare by the list and round-trip through Codable")
    func traitsValue() throws {
        let both = DeltaSkinTraits(gameIdentifier: "first", gameIdentifiers: ["second", "first", " "])
        #expect(both.gameIdentifiers == ["first", "second"])
        var mutable = DeltaSkinTraits()
        #expect(mutable.gameIdentifier == nil)
        mutable.gameIdentifier = "x"
        #expect(mutable.gameIdentifiers == ["x"])
        mutable.gameIdentifier = nil
        #expect(mutable.gameIdentifiers.isEmpty)
        #expect(DeltaSkinTraits(gameIdentifier: "a") == DeltaSkinTraits(gameIdentifiers: ["a"]))
        #expect(DeltaSkinTraits(gameIdentifiers: ["a", "b"]) != DeltaSkinTraits(gameIdentifiers: ["b", "a"]))

        let encoded = try JSONEncoder().encode(DeltaSkinTraits(gameIdentifiers: ["m", "t"]))
        #expect(try JSONDecoder().decode(DeltaSkinTraits.self, from: encoded).gameIdentifiers == ["m", "t"])
        // Traits encoded before the list existed carry one `gameIdentifier`.
        let legacy = Data(#"{"device":"iphone","displayType":"standard","orientation":"portrait","externalDisplay":"none","gameIdentifier":"old"}"#.utf8)
        #expect(try JSONDecoder().decode(DeltaSkinTraits.self, from: legacy).gameIdentifiers == ["old"])
    }
}
