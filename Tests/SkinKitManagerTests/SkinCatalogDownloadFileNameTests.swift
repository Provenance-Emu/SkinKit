import Foundation
import SkinCatalogKit
import SkinKitCore
import Testing
@testable import SkinKitManager

@Suite("Skin catalog download file naming")
struct SkinCatalogDownloadFileNameTests {

    @Test("Preferred filename uses sanitized id and .deltaskin suffix")
    func preferredNameSanitizesId() throws {
        let downloadURL = try #require(URL(string: "https://github.com/x/y/releases/download/v1/download"))
        let entry = SkinCatalogEntry(
            id: "com.author/my-skin",
            name: "Cool Skin",
            systems: ["gba"],
            downloadURL: downloadURL
        )
        #expect(entry.preferredLocalDownloadFileName() == "com.author-my-skin.deltaskin")
    }

    @Test("Generic download URL path does not change local filename")
    func genericURLStillGetsStableName() throws {
        let downloadURL = try #require(URL(string: "https://cdn.example.com/files/latest?token=abc"))
        let entry = SkinCatalogEntry(
            id: "com.example.delta",
            name: "Example",
            systems: ["nes"],
            downloadURL: downloadURL
        )
        #expect(entry.preferredLocalDownloadFileName() == "com.example.delta.deltaskin")
    }

    @Test("Empty id after sanitization falls back to skin stem")
    func emptyIdFallback() throws {
        let downloadURL = try #require(URL(string: "https://example.com/a.deltaskin"))
        let entry = SkinCatalogEntry(
            id: "   ",
            name: "X",
            systems: ["gba"],
            downloadURL: downloadURL
        )
        #expect(entry.preferredLocalDownloadFileName() == "skin.deltaskin")
    }

    @Test("A .manicskin download is still saved as .deltaskin (Provenance), while the store policy keeps the extension")
    func provenanceNamingDiffersFromTheStorePolicy() throws {
        let entry = try TestSupport.entry(id: "abc123", systems: ["gamecube"], url: "https://deltastyles.com/files/skins/1/x.manicskin")
        #expect(entry.preferredLocalDownloadFileName() == "abc123.deltaskin")
        #expect(SkinStorePolicy.iCube.downloadFileName(for: entry) == "abc123.manicskin")
    }
}

@Suite("matchingInstalledSkin")
struct MatchingInstalledSkinTests {
    private func skin(_ id: String, name: String = "Some Skin", file: String) -> StubSkin {
        StubSkin(identifier: id, name: name, gameType: .gba, fileURL: URL(fileURLWithPath: "/skins/\(file)"))
    }

    private func entry(id: String = "catalog-id", name: String = "Catalog Name", url: String = "https://example.com/files/download-name.deltaskin") throws -> SkinCatalogEntry {
        try TestSupport.entry(id: id, name: name, systems: ["gba"], url: url)
    }

    @Test("1. catalog id equals the skin's identifier")
    func byIdentifier() throws {
        let skins = [skin("other", file: "a.deltaskin"), skin("catalog-id", file: "b.deltaskin")]
        #expect(matchingInstalledSkin(for: try entry(), in: skins)?.fileURL.lastPathComponent == "b.deltaskin")
    }

    @Test("2. the file stem is the preferred download name")
    func byPreferredStem() throws {
        let skins = [skin("x", file: "unrelated.deltaskin"), skin("y", file: "Catalog-Id.deltaskin")]
        #expect(matchingInstalledSkin(for: try entry(), in: skins)?.identifier == "y")
    }

    @Test("3. the file stem is the download URL's stem")
    func byDownloadStem() throws {
        let skins = [skin("x", file: "unrelated.deltaskin"), skin("y", file: "download-name.manicskin")]
        #expect(matchingInstalledSkin(for: try entry(), in: skins)?.identifier == "y")
    }

    @Test("4. the name matches, ignoring case")
    func byName() throws {
        let skins = [skin("x", name: "nope", file: "a.deltaskin"), skin("y", name: "catalog NAME", file: "b.deltaskin")]
        #expect(matchingInstalledSkin(for: try entry(), in: skins)?.identifier == "y")
    }

    @Test("Identifier beats stem beats name, and nothing matches nothing")
    func priorityAndMiss() throws {
        let byName = skin("n", name: "Catalog Name", file: "z.deltaskin")
        let byStem = skin("s", file: "catalog-id.deltaskin")
        #expect(matchingInstalledSkin(for: try entry(), in: [byName, byStem])?.identifier == "s")
        #expect(matchingInstalledSkin(for: try entry(), in: [skin("q", file: "q.deltaskin")]) == nil)
        #expect(matchingInstalledSkin(for: try entry(), in: []) == nil)
        #expect(!isCatalogSkinInstalled(try entry(), in: []))
        #expect(isCatalogSkinInstalled(try entry(), in: [byName]))
    }
}
