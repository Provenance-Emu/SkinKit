import Foundation

/// A trimmed slice of the live feed (`Provenance-Emu/skins` `catalog.json`, 2026-10-23, 1,270
/// skins) in `Fixtures/catalog.json`: 25 real entries plus 4 hand-written ones (ids start with
/// `test-`).
///
/// Real entries cover: the 3 Dreamcast skins; 4 `mame` (one mirror-hosted on the `mirror` release,
/// one Sharp X1 that iFly hides); the one `gamecube` skin; `n64` skins (a pack with `groupId`, a
/// `.zip`, a raw space in the URL, a Delta game type); saturn, psx and genesis (one in a pack);
/// a `.zip`, a Google Drive link and a raw-space URL on `gba`; a `threeDS`; two `unofficial`
/// placeholders; an `owner/repo` source; a mirrored Drive skin with `originalURL` (an unknown key).
/// The feed has no Wii skins and no entry that lacks keys, so the hand-written ones fill in:
/// a Wii skin declared only by `gameTypeIdentifier`, a mixed-case `GameCube` with a date-only
/// `lastUpdated`, an old-format entry with only the required keys, and one with unknown and
/// mistyped fields.
enum SkinCatalogFixture {
    static let entryCount = 29

    static let dreamcastIDs = ["3957312ad9e7c59e", "cc0d4148aecb1099", "161704562e4e93d8"]
    static let mirrorMameID = "7e15d04188bfa40d"
    static let miniMameID = "67d260708ffa7d09"
    static let mortalKombatID = "4ce9beceec67aa26"
    static let sharpX1ID = "b88c501e8689debb"
    static let gameCubePocketID = "ea60f2003d82ac9e"
    static let n64PackID = "15dd242edd355b11"
    static let n64PackSecondID = "42a0c7c1f0483353"
    static let n64ZipID = "91f17a221e5c6a87"
    static let n64DeltaTypeID = "abe5e9e4ee7b0195"
    static let n64SpaceURLID = "598c913900e17758"
    static let saturnID = "4ac93f2f33996634"
    static let psxID = "544a0da8e618620c"
    static let genesisID = "f179bce869082ecb"
    static let genesisPackID = "97d5ef6dc9341875"
    static let gbaSpaceURLID = "8e3871abb5910097"
    static let gbaZipID = "9bc4ccc88250907c"
    static let googleDriveID = "2a71bf5fa167d694"
    static let threeDSID = "a4aa8f9a0a9d560f"
    static let unofficialID = "e62e868cf559da9f"
    static let repoSourceID = "5439d0ea77b24af9"
    static let mirroredDriveID = "ec858d24014b5d1e"
    static let wiiGameTypeOnlyID = "test-wii-gametype-only"
    static let mixedCaseGameCubeID = "test-gamecube-mixed-case"
    static let oldFormatID = "test-old-format"
    static let unknownFieldsID = "test-unknown-fields"

    static var data: Data {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json", subdirectory: "Fixtures"),
              let data = try? Data(contentsOf: url)
        else {
            fatalError("Fixtures/catalog.json is missing from the test bundle")
        }
        return data
    }
}
