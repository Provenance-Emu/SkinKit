#if canImport(UIKit)
import Foundation
import SkinCatalogKit
import SkinKitCore
import SkinKitManager
import Testing
@testable import SkinKitUI

/// The system directory seam, and the catalog queries the browser views run on SkinCatalogKit's service.
extension UIKitSerial {
    @Suite("Systems and catalog queries", .serialized)
    struct CatalogAndSystemsTests {

        private static let genesisFamily: Set<String> = ["genesis", "segacd", "32x"]

        private func withDirectory<T>(_ body: () async throws -> T) async rethrows -> T {
            let previous = DeltaSkinSystemDirectory.current
            defer { DeltaSkinSystemDirectory.current = previous }
            DeltaSkinSystemDirectory.current = DeltaSkinSystemDirectory(
                systems: [
                    DeltaSkinSystem(id: SkinSystemID("GBA"), fullName: "Game Boy Advance", gameType: .gba,
                                    skinCatalogSystemCode: "gba", relatedSkinCatalogSystemCodes: ["gba"]),
                    DeltaSkinSystem(id: SkinSystemID("Genesis"), fullName: "Sega Genesis", gameType: .genesis,
                                    skinCatalogSystemCode: "genesis", relatedSkinCatalogSystemCodes: Self.genesisFamily),
                ],
                displayNameForCatalogCode: { $0 == "threeds" ? "Nintendo 3DS" : $0.uppercased() },
                relatedCatalogSystemCodes: { code in code == "genesis" || code == "32x" ? Self.genesisFamily : [code] },
                canonicalCatalogCode: { $0.lowercased() == "threeds" ? "3ds" : $0.lowercased() })
            return try await body()
        }

        private static func service() throws -> SkinCatalogService {
            let json = """
            {"version": 2, "skins": [
              {"id": "1", "name": "Alpha", "author": "ann", "systems": ["gba"], "downloadURL": "https://example.invalid/a.deltaskin",
               "tags": ["Dark"], "deviceSupport": ["iphone"], "downloadCount": 10, "rating": 4.0, "source": "deltastyles.com"},
              {"id": "2", "name": "Bravo", "author": "bob", "systems": ["32x"], "downloadURL": "https://example.invalid/b.deltaskin",
               "tags": ["light"], "deviceSupport": ["ipad-pro"], "downloadCount": 99, "rating": 3.0},
              {"id": "3", "name": "Charlie", "systems": ["Genesis", "unofficial"], "downloadURL": "https://example.invalid/c.deltaskin",
               "deviceSupport": [], "downloadCount": 50, "rating": 5.0},
              {"id": "4", "name": "Delta", "systems": ["threeDS"], "downloadURL": "https://example.invalid/d.deltaskin"}
            ]}
            """
            let data = Data(json.utf8)
            let cache = FileManager.default.temporaryDirectory.appendingPathComponent("catalog-\(UUID().uuidString).json")
            return SkinCatalogService(
                catalogURLs: [URL(string: "https://example.invalid/catalog.json")!],
                cacheURL: cache,
                fetch: { url in (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!) })
        }

        // MARK: Directory

        @Test("The default directory knows no systems and falls back to identifiers")
        func defaultDirectory() {
            let directory = DeltaSkinSystemDirectory()
            #expect(directory.systems.isEmpty)
            #expect(directory.displayNameForCatalogCode("gba") == "GBA")
            #expect(directory.relatedCatalogSystemCodes("GBA") == ["gba"])
            #expect(directory.systemForGameType(.gba) == nil)
        }

        @Test("A skin's game type shows the system's full name when the app knows it, else the identifier")
        func displayNames() async {
            await withDirectory {
                #expect(DeltaSkinSystemDirectory.displayName(for: .gba) == "Game Boy Advance")
                // Unknown to the directory: the Delta identifier.
                #expect(DeltaSkinSystemDirectory.displayName(for: .nes) == (DeltaSkinGameType.nes.deltaIdentifierString
                    ?? DeltaSkinGameType.nes.manicIdentifierString ?? String(describing: DeltaSkinGameType.nes)))
            }
        }

        @Test("Manager skins(for: DeltaSkinSystem) is empty for a system without a game type")
        @MainActor
        func systemWithoutGameType() async throws {
            let manager = PreviewlessManager.make()
            let system = DeltaSkinSystem(id: SkinSystemID("ARCADE"), fullName: "Arcade", gameType: nil, skinCatalogSystemCode: "arcade")
            let skins = try await manager.skins(for: system)
            #expect(skins.isEmpty)
        }

        // MARK: Catalog queries (ported: SkinCatalogSystemGroupingTests)

        @Test("Service filter matching uses related system group IDs")
        func serviceFilterMatchesRelatedGroupCodes() async {
            await withDirectory {
                let filterCodes = SkinCatalogService.resolvedSystemFilterCodes("genesis")
                #expect(filterCodes == Self.genesisFamily)
                let codes = filterCodes ?? []
                #expect(SkinCatalogService.matchesAnySystemCode(in: ["32x"], filterCodes: codes))
                #expect(SkinCatalogService.matchesAnySystemCode(in: ["SegaCD"], filterCodes: codes))
                #expect(!SkinCatalogService.matchesAnySystemCode(in: ["snes"], filterCodes: codes))
                #expect(SkinCatalogService.resolvedSystemFilterCodes(nil) == nil)
                #expect(SkinCatalogService.resolvedSystemFilterCodes("  ") == nil)
            }
        }

        @Test("Legacy placeholder system codes are hidden")
        func legacyCodes() {
            #expect(SkinCatalogService.isLegacySystemCode("Unofficial"))
            #expect(SkinCatalogService.isLegacySystemCode("unknown"))
            #expect(!SkinCatalogService.isLegacySystemCode("gba"))
        }

        @Test("availableSystems canonicalises, drops placeholders and sorts")
        func availableSystems() async throws {
            let service = try Self.service()
            let previous = DeltaSkinSystemDirectory.current
            defer { DeltaSkinSystemDirectory.current = previous }
            DeltaSkinSystemDirectory.current = DeltaSkinSystemDirectory(
                canonicalCatalogCode: { $0.lowercased() == "threeds" ? "3ds" : $0.lowercased() })
            let systems = try await service.availableSystems()
            #expect(systems == ["32x", "3ds", "gba", "genesis"])
        }

        @Test("availableTags lists every tag once")
        func availableTags() async throws {
            let tags = try await Self.service().availableTags()
            #expect(tags == ["Dark", "light"])
        }

        @Test("filterSkins by system expands the family, sorts, and filters device support by prefix")
        func filterSkins() async throws {
            let service = try Self.service()
            func ids(system: String? = nil, tags: [String]? = nil, device: [String]? = nil, sort: SkinSortOption) async throws -> [String] {
                try await service.filterSkins(system: system, tags: tags, deviceSupport: device, sortBy: sort).map(\.id)
            }
            let previous = DeltaSkinSystemDirectory.current
            defer { DeltaSkinSystemDirectory.current = previous }
            DeltaSkinSystemDirectory.current = DeltaSkinSystemDirectory(
                relatedCatalogSystemCodes: { code in code == "genesis" ? Self.genesisFamily : [code] })

            #expect(try await ids(system: "genesis", sort: .popular) == ["2", "3"]) // 32x and Genesis, most downloads first
            #expect(try await service.filterSkins(sortBy: .alphabetical).map(\.name) == ["Alpha", "Bravo", "Charlie", "Delta"])
            #expect(try await ids(sort: .rating).first == "3")
            // "ipad" matches "ipad-pro"; an entry without device info is unrestricted.
            #expect(try await ids(device: ["ipad"], sort: .alphabetical) == ["2", "3", "4"])
            #expect(try await ids(tags: ["dark"], sort: .popular) == ["1"])
        }

        @Test("searchSkins matches name, author, tags and source, optionally within a system")
        func searchSkins() async throws {
            let service = try Self.service()
            func ids(_ query: String, system: String? = nil) async throws -> [String] {
                try await service.searchSkins(query: query, system: system).map(\.id).sorted()
            }
            let previous = DeltaSkinSystemDirectory.current
            defer { DeltaSkinSystemDirectory.current = previous }
            DeltaSkinSystemDirectory.current = DeltaSkinSystemDirectory(
                relatedCatalogSystemCodes: { code in code == "genesis" ? Self.genesisFamily : [code] })

            #expect(try await ids("alp") == ["1"])
            #expect(try await ids("BOB") == ["2"])
            #expect(try await ids("light") == ["2"])
            #expect(try await ids("deltastyles") == ["1"])
            #expect(try await ids("", system: "genesis") == ["2", "3"])
            #expect(try await ids("charlie", system: "gba").isEmpty)
        }
    }
}

/// A manager over the bundled fixtures, in a scratch directory.
enum PreviewlessManager {
    @MainActor
    static func make(names: [String] = ["PocketTaco-GBA", "PocketTaco-NES"]) -> DeltaSkinManager {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("SkinKitUITests-\(UUID().uuidString)")
        let urls = names.compactMap { Bundle.module.url(forResource: "Fixtures/\($0).deltaskin", withExtension: nil) }
        let defaults = UserDefaults(suiteName: "SkinKitUITests-\(UUID().uuidString)")!
        let selection = DeltaSkinSelectionManager(preferences: DeltaSkinPreferences(defaults: defaults))
        return DeltaSkinManager(
            configuration: .init(skinsDirectory: scratch, bundledSkinLocations: { urls }),
            selectionManager: selection)
    }
}
#endif
