import XCTest
@testable import SkinCatalogKit

/// Cache/TTL behaviour with an injected fetch and clock (no network), and primary → fallback URL
/// behaviour through a mock `URLProtocol` on an injected `URLSession`.
final class SkinCatalogServiceTests: XCTestCase {
    /// Counts fetches and serves a scripted response. Thread-safe because the fetch closure is
    /// `@Sendable` and runs off the test's actor.
    private final class FakeServer: @unchecked Sendable {
        private let lock = NSLock()
        private var _fetches = 0
        private var _status = 200
        private var _offline = false

        var fetches: Int {
            lock.withLock { _fetches }
        }

        func set(status: Int) {
            lock.withLock { _status = status }
        }

        func set(offline: Bool) {
            lock.withLock { _offline = offline }
        }

        func respond(_ url: URL) throws -> (Data, URLResponse) {
            let (status, offline) = lock.withLock {
                _fetches += 1
                return (_status, _offline)
            }
            if offline {
                throw URLError(.notConnectedToInternet)
            }
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
            return (SkinCatalogFixture.data, response ?? URLResponse())
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

    private final class LogSink: @unchecked Sendable {
        private let lock = NSLock()
        private var _lines: [(SkinCatalogLogLevel, String)] = []

        var lines: [(SkinCatalogLogLevel, String)] {
            lock.withLock { _lines }
        }

        func append(_ level: SkinCatalogLogLevel, _ message: String) {
            lock.withLock { _lines.append((level, message)) }
        }
    }

    /// XCTest builds a fresh instance per test, so these are per-test too.
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SkinCatalogServiceTests-\(UUID().uuidString)", isDirectory: true)
    private let server = FakeServer()
    private let clock = Clock()
    private let logs = LogSink()

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        MockURLProtocol.reset(nil)
    }

    override func tearDownWithError() throws {
        MockURLProtocol.reset(nil)
        try? FileManager.default.removeItem(at: directory)
    }

    private var cacheURL: URL {
        directory.appendingPathComponent(SkinCatalogService.cacheFileName)
    }

    private func makeService(urls: [URL]? = nil) -> SkinCatalogService {
        let server = server
        let clock = clock
        let logs = logs
        return SkinCatalogService(
            catalogURLs: urls ?? [URL(fileURLWithPath: "/catalog.json")],
            cacheURL: cacheURL,
            ttl: 24 * 60 * 60,
            now: { clock.now },
            log: { logs.append($0, $1) },
            fetch: { url in try server.respond(url) }
        )
    }

    /// A service on the real default URLs whose session is the mock.
    private func makeMockedService() -> SkinCatalogService {
        let clock = clock
        return SkinCatalogService(
            cacheURL: cacheURL,
            now: { clock.now },
            session: MockURLProtocol.makeSession(),
            log: SkinCatalogLog.silent
        )
    }

    // MARK: - Cache and TTL

    func testFirstFetchHitsNetworkAndWritesCache() async throws {
        let catalog = try await makeService().catalog()
        XCTAssertEqual(catalog.skins.count, SkinCatalogFixture.entryCount)
        XCTAssertEqual(server.fetches, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    func testCacheIsTheServersBytesVerbatim() async throws {
        _ = try await makeService().catalog()
        XCTAssertEqual(try Data(contentsOf: cacheURL), SkinCatalogFixture.data)
    }

    func testWithinTTLServesMemoryWithoutFetching() async throws {
        let service = makeService()
        _ = try await service.catalog()
        clock.advance(60 * 60)
        _ = try await service.catalog()
        XCTAssertEqual(server.fetches, 1)
    }

    /// A fresh process (new service instance) must honour the disk cache's age rather than
    /// refetching on every launch.
    func testFreshDiskCacheIsUsedAcrossInstances() async throws {
        _ = try await makeService().catalog()
        clock.advance(23 * 60 * 60)
        let catalog = try await makeService().catalog()
        XCTAssertEqual(catalog.skins.count, SkinCatalogFixture.entryCount)
        XCTAssertEqual(server.fetches, 1)
    }

    func testExpiredCacheRefetches() async throws {
        let service = makeService()
        _ = try await service.catalog()
        clock.advance(25 * 60 * 60)
        _ = try await service.catalog()
        XCTAssertEqual(server.fetches, 2)
    }

    func testForceRefreshAlwaysFetches() async throws {
        let service = makeService()
        _ = try await service.catalog()
        _ = try await service.catalog(forceRefresh: true)
        XCTAssertEqual(server.fetches, 2)
    }

    func testOfflineFallsBackToStaleDiskCache() async throws {
        _ = try await makeService().catalog()
        clock.advance(30 * 24 * 60 * 60)
        server.set(offline: true)
        let load = try await makeService().load()
        XCTAssertEqual(load.catalog.skins.count, SkinCatalogFixture.entryCount)
        XCTAssertTrue(load.isFallback)
        XCTAssertNotNil(load.networkError)
    }

    func testHTTPErrorFallsBackToCacheOrThrows() async throws {
        server.set(status: 503)
        do {
            _ = try await makeService().catalog()
            XCTFail("expected a throw with no cache")
        } catch let error as SkinCatalogError {
            guard case .httpStatus(503) = error else {
                return XCTFail("unexpected \(error)")
            }
        }

        server.set(status: 200)
        let service = makeService()
        _ = try await service.catalog()
        server.set(status: 500)
        let fallback = try await service.catalog(forceRefresh: true)
        XCTAssertEqual(fallback.skins.count, SkinCatalogFixture.entryCount)
    }

    func testFreshLoadIsNotAFallback() async throws {
        let load = try await makeService().load()
        XCTAssertFalse(load.isFallback)
        XCTAssertNil(load.networkError)
    }

    func testCachedCatalogNeverTouchesNetwork() async throws {
        let empty = await makeService().cachedCatalog()
        XCTAssertNil(empty)
        _ = try await makeService().catalog()
        let cached = await makeService().cachedCatalog()
        XCTAssertEqual(cached?.skins.count, SkinCatalogFixture.entryCount)
        XCTAssertEqual(server.fetches, 1)
    }

    func testInvalidateCacheDropsMemoryAndDisk() async throws {
        let service = makeService()
        _ = try await service.catalog()
        await service.invalidateCache()
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
        let cached = await service.cachedCatalog()
        XCTAssertNil(cached)
        _ = try await service.catalog()
        XCTAssertEqual(server.fetches, 2)
    }

    func testUnreadableDiskCacheIsDiscarded() async throws {
        try Data("<html>".utf8).write(to: cacheURL)
        let cached = await makeService().cachedCatalog()
        XCTAssertNil(cached)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    func testLoggerReceivesFetchLines() async throws {
        _ = try await makeService().catalog()
        let lines = logs.lines
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.0, .info)
        XCTAssertTrue(lines.first?.1.contains("\(SkinCatalogFixture.entryCount) skins") ?? false)
    }

    func testGlobalLoggerHookIsUsedWhenNoLogIsGiven() async throws {
        let sink = LogSink()
        let server = server
        let clock = clock
        let service = SkinCatalogService(
            catalogURLs: [URL(fileURLWithPath: "/catalog.json")],
            cacheURL: cacheURL,
            now: { clock.now },
            fetch: { url in try server.respond(url) }
        )
        // Set after the service exists: the hook is looked up per line, so `shared` follows it too.
        let previous = SkinCatalogLog.logger
        SkinCatalogLog.logger = { sink.append($0, $1) }
        defer { SkinCatalogLog.logger = previous }

        _ = try await service.catalog()

        XCTAssertEqual(sink.lines.count, 1)
        XCTAssertEqual(sink.lines.first?.0, .info)
        XCTAssertTrue(sink.lines.first?.1.contains("\(SkinCatalogFixture.entryCount) skins") ?? false)
    }

    func testServiceLogParameterWinsOverTheGlobalHook() async throws {
        let globalSink = LogSink()
        let previous = SkinCatalogLog.logger
        SkinCatalogLog.logger = { globalSink.append($0, $1) }
        defer { SkinCatalogLog.logger = previous }

        _ = try await makeService().catalog()

        XCTAssertEqual(logs.lines.count, 1)
        XCTAssertTrue(globalSink.lines.isEmpty)
    }

    // MARK: - Primary → fallback

    func testDefaultURLsAreEmuskinsThenRawGitHub() {
        XCTAssertEqual(SkinCatalogService.defaultCatalogURLs.map(\.absoluteString), [
            "https://emuskins.com/catalog.json",
            "https://raw.githubusercontent.com/Provenance-Emu/skins/main/catalog.json",
        ])
        XCTAssertFalse(SkinCatalogService.defaultCatalogURLs.contains { $0.host?.contains("provenance-emu.com") == true },
                       "the old provenance-emu.com URL only redirects")
    }

    func testSecondURLIsTriedWhenFirstFails() async throws {
        let failing = URL(fileURLWithPath: "/down.json")
        let working = URL(fileURLWithPath: "/catalog.json")
        let server = server
        let service = SkinCatalogService(
            catalogURLs: [failing, working],
            cacheURL: cacheURL,
            log: SkinCatalogLog.silent,
            fetch: { url in
                if url == failing {
                    throw URLError(.cannotFindHost)
                }
                return try server.respond(url)
            }
        )
        let catalog = try await service.catalog()
        XCTAssertEqual(catalog.skins.count, SkinCatalogFixture.entryCount)
    }

    func testPrimarySuccessNeverHitsTheFallback() async throws {
        MockURLProtocol.reset { _ in .ok(SkinCatalogFixture.data) }
        let catalog = try await makeMockedService().catalog()
        XCTAssertEqual(catalog.skins.count, SkinCatalogFixture.entryCount)
        XCTAssertEqual(MockURLProtocol.requests, [SkinCatalogService.defaultCatalogURLs[0]])
    }

    func testPrimaryHTTPErrorFallsBackToRawGitHub() async throws {
        let primary = SkinCatalogService.defaultCatalogURLs[0]
        MockURLProtocol.reset { url in url == primary ? .status(503) : .ok(SkinCatalogFixture.data) }
        let load = try await makeMockedService().load()
        XCTAssertEqual(load.catalog.skins.count, SkinCatalogFixture.entryCount)
        XCTAssertFalse(load.isFallback, "a mirror answering is a fresh fetch, not a stale cache")
        XCTAssertEqual(MockURLProtocol.requests, SkinCatalogService.defaultCatalogURLs)
    }

    func testPrimaryTransportFailureFallsBackToRawGitHub() async throws {
        let primary = SkinCatalogService.defaultCatalogURLs[0]
        MockURLProtocol.reset { url in url == primary ? .failure(.cannotConnectToHost) : .ok(SkinCatalogFixture.data) }
        let catalog = try await makeMockedService().catalog()
        XCTAssertEqual(catalog.skins.count, SkinCatalogFixture.entryCount)
        XCTAssertEqual(MockURLProtocol.requests, SkinCatalogService.defaultCatalogURLs)
    }

    func testPrimaryServingNonCatalogBytesFallsBack() async throws {
        let primary = SkinCatalogService.defaultCatalogURLs[0]
        MockURLProtocol.reset { url in url == primary ? .ok(Data("<html>captive portal</html>".utf8)) : .ok(SkinCatalogFixture.data) }
        let catalog = try await makeMockedService().catalog()
        XCTAssertEqual(catalog.skins.count, SkinCatalogFixture.entryCount)
        XCTAssertEqual(MockURLProtocol.requests.count, 2)
        // The bad primary bytes must not have been cached.
        XCTAssertEqual(try Data(contentsOf: cacheURL), SkinCatalogFixture.data)
    }

    func testBothURLsFailingThrowsTheLastError() async throws {
        MockURLProtocol.reset { url in url == SkinCatalogService.defaultCatalogURLs[0] ? .status(503) : .status(404) }
        do {
            _ = try await makeMockedService().catalog()
            XCTFail("expected a throw")
        } catch let error as SkinCatalogError {
            guard case .httpStatus(404) = error else {
                return XCTFail("unexpected \(error)")
            }
        }
        XCTAssertEqual(MockURLProtocol.requests, SkinCatalogService.defaultCatalogURLs)
    }

    func testBothURLsOfflineThrowsNetworkError() async throws {
        MockURLProtocol.reset { _ in .failure(.notConnectedToInternet) }
        do {
            _ = try await makeMockedService().catalog()
            XCTFail("expected a throw")
        } catch let error as SkinCatalogError {
            guard case .network = error else {
                return XCTFail("unexpected \(error)")
            }
        }
    }

    func testInjectedURLsReplaceTheDefaults() async throws {
        let custom = [URL(string: "https://staging.example.com/a.json")!, URL(string: "https://staging.example.com/b.json")!]
        MockURLProtocol.reset { url in url == custom[0] ? .status(500) : .ok(SkinCatalogFixture.data) }
        let clock = clock
        let service = SkinCatalogService(
            catalogURLs: custom,
            cacheURL: cacheURL,
            now: { clock.now },
            session: MockURLProtocol.makeSession(),
            log: SkinCatalogLog.silent
        )
        _ = try await service.catalog()
        XCTAssertEqual(MockURLProtocol.requests, custom)
    }

    func testNoURLsConfiguredThrows() async throws {
        let service = SkinCatalogService(catalogURLs: [], cacheURL: cacheURL, log: SkinCatalogLog.silent)
        do {
            _ = try await service.catalog()
            XCTFail("expected a throw")
        } catch let error as SkinCatalogError {
            guard case .network = error else {
                return XCTFail("unexpected \(error)")
            }
        }
    }

    func testFallbackFetchFailureAfterPrimaryCacheStillServesDisk() async throws {
        // Warm the cache from the primary, expire it, then fail both URLs: the stale copy wins.
        MockURLProtocol.reset { _ in .ok(SkinCatalogFixture.data) }
        _ = try await makeMockedService().catalog()
        clock.advance(48 * 60 * 60)
        MockURLProtocol.reset { _ in .status(500) }
        let load = try await makeMockedService().load()
        XCTAssertEqual(load.catalog.skins.count, SkinCatalogFixture.entryCount)
        XCTAssertTrue(load.isFallback)
        XCTAssertEqual(MockURLProtocol.requests, SkinCatalogService.defaultCatalogURLs)
    }
}
