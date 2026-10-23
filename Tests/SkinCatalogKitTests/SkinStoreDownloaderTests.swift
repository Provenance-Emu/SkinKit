import XCTest
@testable import SkinCatalogKit

/// The moved downloader, driven through a mock `URLProtocol`.
final class SkinStoreDownloaderTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SkinStoreDownloaderTests-\(UUID().uuidString)", isDirectory: true)

    private final class ProgressLog: @unchecked Sendable {
        private let lock = NSLock()
        private var _values: [Double] = []

        var values: [Double] {
            lock.withLock { _values }
        }

        func append(_ value: Double) {
            lock.withLock { _values.append(value) }
        }
    }

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        MockURLProtocol.reset(nil)
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeDownloader() -> URLSessionSkinStoreDownloader {
        URLSessionSkinStoreDownloader(timeout: 5, makeConfiguration: { MockURLProtocol.makeConfiguration() })
    }

    func testDownloadWritesFileAndReportsCompletion() async throws {
        let body = Data("skin bytes".utf8)
        MockURLProtocol.reset { _ in .ok(body) }
        let destination = directory.appendingPathComponent("nested/a.manicskin")
        let progress = ProgressLog()
        try await makeDownloader().download(
            from: URL(string: "https://example.com/a.manicskin")!,
            to: destination,
            progress: { progress.append($0) }
        )
        XCTAssertEqual(try Data(contentsOf: destination), body)
        XCTAssertEqual(progress.values.last, 1)
    }

    func testDownloadOverwritesAnExistingFile() async throws {
        let destination = directory.appendingPathComponent("a.deltaskin")
        try Data("old".utf8).write(to: destination)
        MockURLProtocol.reset { _ in .ok(Data("new".utf8)) }
        try await makeDownloader().download(
            from: URL(string: "https://example.com/a.deltaskin")!,
            to: destination,
            progress: { _ in }
        )
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "new")
    }

    func testNon2xxThrowsHTTPStatusErrorAndLeavesNoFile() async throws {
        MockURLProtocol.reset { _ in .status(404) }
        let destination = directory.appendingPathComponent("a.deltaskin")
        do {
            try await makeDownloader().download(
                from: URL(string: "https://example.com/gone.deltaskin")!,
                to: destination,
                progress: { _ in }
            )
            XCTFail("expected a throw")
        } catch let error as URLSessionSkinStoreDownloader.HTTPStatusError {
            XCTAssertEqual(error.statusCode, 404)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testTransportFailureThrows() async throws {
        MockURLProtocol.reset { _ in .failure(.notConnectedToInternet) }
        do {
            try await makeDownloader().download(
                from: URL(string: "https://example.com/a.deltaskin")!,
                to: directory.appendingPathComponent("a.deltaskin"),
                progress: { _ in }
            )
            XCTFail("expected a throw")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        }
    }
}
