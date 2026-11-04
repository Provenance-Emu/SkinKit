import XCTest
@testable import SkinCatalogKit

/// Fetch order, cache and offline behaviour of `SkinCreatorDirectory` with an injected transport and
/// clock (no network).
final class SkinCreatorDirectoryTests: XCTestCase {
    private final class FakeServer: @unchecked Sendable {
        private let lock = NSLock()
        private var _requested: [URL] = []
        private var _statuses: [String: Int] = [:]
        private var _offline = false
        private var _body = SkinCreatorFixture.creatorsData

        var requested: [URL] {
            lock.withLock { _requested }
        }

        func set(status: Int, forHost host: String) {
            lock.withLock { _statuses[host] = status }
        }

        func set(offline: Bool) {
            lock.withLock { _offline = offline }
        }

        func set(body: Data) {
            lock.withLock { _body = body }
        }

        func respond(_ url: URL) throws -> (Data, URLResponse) {
            let (status, offline, body) = lock.withLock {
                _requested.append(url)
                return (_statuses[url.host ?? ""] ?? 200, _offline, _body)
            }
            if offline {
                throw URLError(.notConnectedToInternet)
            }
            return (body, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) ?? URLResponse())
        }
    }

    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var _now = Date(timeIntervalSince1970: 1_800_000_000)

        var now: Date {
            lock.withLock { _now }
        }

        func advance(_ seconds: TimeInterval) {
            lock.withLock { _now = _now.addingTimeInterval(seconds) }
        }
    }

    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SkinCreatorDirectoryTests-\(UUID().uuidString)", isDirectory: true)
    private let server = FakeServer()
    private let clock = Clock()

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var cacheURL: URL {
        directory.appendingPathComponent(SkinCreatorDirectory.cacheFileName)
    }

    private func makeDirectory(urls: [URL]? = nil) -> SkinCreatorDirectory {
        let server = server
        let clock = clock
        return SkinCreatorDirectory(
            directoryURLs: urls ?? SkinCreatorDirectory.defaultDirectoryURLs,
            cacheURL: cacheURL,
            now: { clock.now },
            log: SkinCatalogLog.silent,
            fetch: { try server.respond($0) }
        )
    }

    func testDefaultURLsAreEmuskinsThenRawGitHub() {
        XCTAssertEqual(SkinCreatorDirectory.defaultDirectoryURLs.map(\.absoluteString), [
            "https://emuskins.com/creators.json",
            "https://raw.githubusercontent.com/Provenance-Emu/skins/main/docs/creators.json",
        ])
        XCTAssertEqual(SkinCreatorDirectory.defaultCacheURL.lastPathComponent, "skin_store_creators.json")
        XCTAssertEqual(SkinCreatorDirectory.defaultTTL, SkinCatalogService.defaultTTL)
    }

    func testFetchesFromThePrimaryAndCachesTheBytes() async throws {
        let directory = makeDirectory()
        let index = try await directory.index()
        XCTAssertEqual(index.creators.count, SkinCreatorFixture.creatorCount)
        XCTAssertEqual(server.requested.map(\.host), ["emuskins.com"])
        XCTAssertEqual(try Data(contentsOf: cacheURL), SkinCreatorFixture.creatorsData, "verbatim")
    }

    func testFallsBackToGitHubWhenThePrimaryFails() async throws {
        server.set(status: 503, forHost: "emuskins.com")
        let index = try await makeDirectory().index()
        XCTAssertEqual(index.creators.count, SkinCreatorFixture.creatorCount)
        XCTAssertEqual(server.requested.map(\.host), ["emuskins.com", "raw.githubusercontent.com"])
    }

    func testFallsBackToGitHubWhenThePrimaryServesGarbage() async throws {
        // 200 with HTML (a captive portal, say) must not be accepted or cached.
        let garbage = Data("<html>nope</html>".utf8)
        let server = server
        let clock = clock
        let directory = SkinCreatorDirectory(
            cacheURL: cacheURL,
            now: { clock.now },
            log: SkinCatalogLog.silent,
            fetch: { url in
                if url.host == "emuskins.com" {
                    return (garbage, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) ?? URLResponse())
                }
                return try server.respond(url)
            }
        )
        let index = try await directory.index()
        XCTAssertEqual(index.creators.count, SkinCreatorFixture.creatorCount)
        XCTAssertEqual(try Data(contentsOf: cacheURL), SkinCreatorFixture.creatorsData)
    }

    func testFreshCacheSkipsTheNetworkAndStaleCacheRefetches() async throws {
        let directory = makeDirectory()
        _ = try await directory.index()
        _ = try await directory.index()
        XCTAssertEqual(server.requested.count, 1)

        clock.advance(SkinCreatorDirectory.defaultTTL - 60)
        _ = try await directory.index()
        XCTAssertEqual(server.requested.count, 1)

        clock.advance(120)
        _ = try await directory.index()
        XCTAssertEqual(server.requested.count, 2)
    }

    func testForceRefreshAlwaysFetches() async throws {
        let directory = makeDirectory()
        _ = try await directory.index()
        _ = try await directory.index(forceRefresh: true)
        XCTAssertEqual(server.requested.count, 2)
    }

    func testTTLHoldsAcrossLaunches() async throws {
        _ = try await makeDirectory().index()
        let secondLaunch = makeDirectory()
        _ = try await secondLaunch.index()
        XCTAssertEqual(server.requested.count, 1, "the cache file's mtime is the clock")
    }

    func testOfflineUsesMemoryThenDiskAtAnyAge() async throws {
        let first = makeDirectory()
        _ = try await first.index()
        server.set(offline: true)
        clock.advance(10 * SkinCreatorDirectory.defaultTTL)

        let fromMemory = try await first.index()
        XCTAssertEqual(fromMemory.creators.count, SkinCreatorFixture.creatorCount)

        let secondLaunch = makeDirectory()
        let fromDisk = try await secondLaunch.index()
        XCTAssertEqual(fromDisk.creators.count, SkinCreatorFixture.creatorCount)
    }

    func testNoNetworkAndNoCacheThrows() async {
        server.set(offline: true)
        do {
            _ = try await makeDirectory().index()
            XCTFail("expected a throw")
        } catch let error as SkinCatalogError {
            guard case .network = error else { return XCTFail("\(error)") }
        } catch {
            XCTFail("\(error)")
        }
    }

    func testHTTPErrorIsReportedWhenEveryURLFails() async {
        server.set(status: 404, forHost: "emuskins.com")
        server.set(status: 404, forHost: "raw.githubusercontent.com")
        do {
            _ = try await makeDirectory().index()
            XCTFail("expected a throw")
        } catch let error as SkinCatalogError {
            guard case .httpStatus(404) = error else { return XCTFail("\(error)") }
        } catch {
            XCTFail("\(error)")
        }
    }

    func testUnreadableDiskCacheIsDiscarded() async throws {
        try Data("not json".utf8).write(to: cacheURL)
        let directory = makeDirectory()
        let cached = await directory.cachedIndex()
        XCTAssertNil(cached)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    func testCachedIndexReadsDiskWithoutTheNetwork() async throws {
        _ = try await makeDirectory().index()
        let cached = await makeDirectory().cachedIndex()
        XCTAssertEqual(cached?.creators.count, SkinCreatorFixture.creatorCount)
        XCTAssertEqual(server.requested.count, 1)
    }

    func testInvalidateCacheForcesANewFetch() async throws {
        let directory = makeDirectory()
        _ = try await directory.index()
        await directory.invalidateCache()
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
        _ = try await directory.index()
        XCTAssertEqual(server.requested.count, 2)
    }

    // MARK: - Lookups

    func testLookupsUseTheFetchedDirectory() async throws {
        let directory = makeDirectory()
        let catalog = try SkinCatalog.decode(SkinCreatorFixture.catalogData)
        let clearDoom = try XCTUnwrap(catalog.skins.first { $0.id == "clear-doom" })

        let bySlug = await directory.creator(for: "janza")
        XCTAssertEqual(bySlug?.displayName, "JanZa")
        let missing = await directory.creator(for: "nobody")
        XCTAssertNil(missing)

        let creator = await directory.creator(for: clearDoom)
        XCTAssertEqual(creator?.slug, "nostromocrew01")

        let nostromo = try XCTUnwrap(creator)
        let skins = await directory.skins(by: nostromo, in: catalog)
        XCTAssertEqual(skins.map(\.id), ["clear-doom"])
    }

    func testLookupsStillResolveWithNoNetworkAndNoCache() async throws {
        server.set(offline: true)
        let directory = makeDirectory()
        let old = try SkinCatalog.decode(SkinCatalogFixture.data)
        for skin in old.skins {
            let creator = await directory.creator(for: skin)
            XCTAssertEqual(creator == nil, skin.author == nil, skin.id)
        }
        let first = try XCTUnwrap(old.skins.first)
        let resolved = await directory.creator(for: first)
        let profile = try XCTUnwrap(resolved)
        XCTAssertEqual(profile.slug, "starvingartist")
        XCTAssertFalse(profile.isClaimed)
        let skins = await directory.skins(by: profile, in: old)
        XCTAssertEqual(skins.count, 4)
    }
}
