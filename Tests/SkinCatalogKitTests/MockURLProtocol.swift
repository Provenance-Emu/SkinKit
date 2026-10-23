import Foundation

/// Serves scripted responses to any `URLSession` whose configuration lists it in
/// `protocolClasses`, and records every request URL in order.
final class MockURLProtocol: URLProtocol {
    struct Response {
        var status: Int
        var body: Data
        /// Throw this instead of answering.
        var error: URLError?

        static func ok(_ body: Data) -> Response {
            Response(status: 200, body: body, error: nil)
        }

        static func status(_ code: Int, body: Data = Data("<html>error</html>".utf8)) -> Response {
            Response(status: code, body: body, error: nil)
        }

        static func failure(_ code: URLError.Code) -> Response {
            Response(status: 0, body: Data(), error: URLError(code))
        }
    }

    private static let lock = NSLock()
    private static var responder: (@Sendable (URL) -> Response)?
    private static var seen: [URL] = []

    /// Request URLs in the order they arrived.
    static var requests: [URL] {
        lock.withLock { seen }
    }

    /// Install `responder` and clear the request log.
    static func reset(_ responder: (@Sendable (URL) -> Response)?) {
        lock.withLock {
            Self.responder = responder
            seen = []
        }
    }

    /// A session that routes everything here.
    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return configuration
    }

    static func makeSession() -> URLSession {
        URLSession(configuration: makeConfiguration())
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let responder = Self.lock.withLock {
            Self.seen.append(url)
            return Self.responder
        }
        guard let response = responder?(url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        if let error = response.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: nil, headerFields: nil)
        if let http {
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
