import Foundation
import Testing
@testable import OpenChord

@Suite("Artwork cache")
struct ArtworkDataCacheTests {
    @Test("Coalesces concurrent requests and reuses the disk cache")
    func coalescesRequestsAndPersistsData() async throws {
        ArtworkURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ArtworkURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = ArtworkDataCache(session: session, directory: directory)
        let url = try #require(URL(string: "https://music.test/media/artwork/1?access_token=first"))

        async let first = cache.data(for: url)
        async let second = cache.data(for: url)
        let values = await [first, second]

        #expect(values.allSatisfy { $0 == ArtworkURLProtocol.imageData })
        #expect(ArtworkURLProtocol.requestCount == 1)

        let restored = ArtworkDataCache(session: session, directory: directory)
        let rotatedTokenURL = try #require(URL(string: "https://music.test/media/artwork/1?access_token=second"))
        #expect(await restored.data(for: rotatedTokenURL) == ArtworkURLProtocol.imageData)
        #expect(ArtworkURLProtocol.requestCount == 1)
    }
}

private final class ArtworkURLProtocol: URLProtocol, @unchecked Sendable {
    static let imageData = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!
    private static let lock = NSLock()
    nonisolated(unsafe) private static var requests = 0

    static var requestCount: Int {
        lock.withLock { requests }
    }

    static func reset() {
        lock.withLock { requests = 0 }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.withLock { Self.requests += 1 }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.imageData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
