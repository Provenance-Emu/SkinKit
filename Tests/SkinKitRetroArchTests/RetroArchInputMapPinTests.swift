import CryptoKit
import Foundation
import Testing
@testable import SkinKitRetroArch

/// The bundled input map is pinned by hash, and the skins repo pins the same hash for its copy
/// (`tests/test_retroarch_map.py`, which also checks the site's `docs/js/skin/retroarch-input-map.json` is
/// byte-identical to SkinKit's). Editing either copy alone fails a test: change the map here, copy it to skins,
/// and update `pinnedSHA256` in both repos.
@Suite("RetroArch input map pin")
struct RetroArchInputMapPinTests {

    static let pinnedSHA256 = "dc0b9da4826e13c215a3008f4c4e6c5179b4ef5311ebd93b113cb91d7078e613"

    @Test("The bundled input map matches the hash the skins repo pins")
    func bundledMapMatchesPin() throws {
        let url = try #require(RetroArchInputMap.bundledURL)
        let digest = SHA256.hash(data: try Data(contentsOf: url))
        #expect(digest.map { String(format: "%02x", $0) }.joined() == Self.pinnedSHA256)
    }
}
