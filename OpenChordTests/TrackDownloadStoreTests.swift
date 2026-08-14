import Foundation
import Testing
@testable import OpenChord

@Suite("Track downloads")
@MainActor
struct TrackDownloadStoreTests {
    @Test("Downloads a remote track and uses the local copy for playback")
    func downloadsAndResolvesLocalCopy() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DownloadURLProtocol.self]
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = TrackDownloadStore(
            session: URLSession(configuration: configuration),
            downloadsDirectory: directory
        )
        let track = makeTrack().using(
            audioSource: .remote(try #require(URL(string: "https://music.example.test/media/tracks/1")))
        )

        await store.download(track)

        #expect(store.state(for: track) == .downloaded)
        let localURL = try #require(store.playable(track).audioSource.url())
        #expect(localURL.isFileURL)
        #expect(localURL.pathExtension == "mp3")
        #expect(try Data(contentsOf: localURL) == DownloadURLProtocol.audio)
        #expect(store.downloadedTrackCount == 1)
        #expect(store.downloadedBytes == Int64(DownloadURLProtocol.audio.count))

        try store.removeDownload(for: track)

        #expect(store.state(for: track) == .idle)
        #expect(store.downloadedTrackCount == 0)
        #expect(store.downloadedBytes == 0)
    }
}

private final class DownloadURLProtocol: URLProtocol, @unchecked Sendable {
    static let audio = Data("openchord-audio".utf8)

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "music.example.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "audio/mpeg",
                "Content-Length": "\(Self.audio.count)",
            ]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.audio)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
