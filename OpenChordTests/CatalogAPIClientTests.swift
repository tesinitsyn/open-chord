import Foundation
import Testing
@testable import OpenChord

@Suite("Catalog API client")
struct CatalogAPIClientTests {
    @Test("Decodes the catalog and anchors media URLs to the configured LAN server")
    func decodesCatalogAndAnchorsMediaURL() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CatalogURLProtocol.self]
        let client = CatalogAPIClient(session: URLSession(configuration: configuration))
        let serverURL = try #require(URL(string: "http://192.168.1.20:8080"))

        let albums = try await client.fetchAlbums(from: serverURL)
        let album = try #require(albums.first)
        let track = try #require(album.tracks.first)

        #expect(album.title == "Afterglow")
        #expect(track.lyrics.first?.text == "Streetlights drawing silver lines")
        #expect(track.duration == 96)
        #expect(track.audioSource.url()?.absoluteString == "http://192.168.1.20:8080/media/tracks/track")
        #expect(album.artwork.remoteURL?.absoluteString == "http://192.168.1.20:8080/media/artwork/cover")
    }

    @Test("Adds a track to a playlist through GraphQL")
    func addsTrackToPlaylist() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlaylistMutationURLProtocol.self]
        let client = CatalogAPIClient(session: URLSession(configuration: configuration))
        let serverURL = try #require(URL(string: "http://192.168.1.20:8080"))
        let playlistID = try #require(UUID(uuidString: "50000000-0000-0000-0000-000000000001"))
        let trackID = try #require(UUID(uuidString: "30000000-0000-0000-0000-000000000001"))

        let playlist = try await client.add(
            trackID: trackID,
            to: playlistID,
            at: serverURL
        )

        #expect(playlist.id == playlistID)
        #expect(playlist.tracks.map(\.id) == [trackID])
        #expect(PlaylistMutationURLProtocol.receivedBody?.contains("addTrackToPlaylist") == true)
        #expect(PlaylistMutationURLProtocol.receivedBody?.contains(trackID.uuidString) == true)
    }

    @Test(
        "Normalizes common local server addresses",
        arguments: [
            ("192.168.1.20:8080", "http://192.168.1.20:8080"),
            ("http://openchord.local:8080/", "http://openchord.local:8080"),
            ("https://music.example.com", "https://music.example.com"),
        ]
    )
    @MainActor
    func normalizesServerAddress(input: String, expected: String) {
        #expect(CatalogStore.normalizedURL(from: input)?.absoluteString == expected)
    }

    @Test("Successful catalog request marks the server connected")
    @MainActor
    func successfulRequestMarksServerConnected() async {
        let store = CatalogStore(
            loader: StubCatalogLoader(result: .success([])),
            defaults: UserDefaults(suiteName: #function)!
        )

        await store.reload()

        #expect(store.connectionState == .connected)
        #expect(store.errorMessage == nil)
    }

    @Test("Failed catalog request marks the server unavailable")
    @MainActor
    func failedRequestMarksServerUnavailable() async {
        let store = CatalogStore(
            loader: StubCatalogLoader(result: .failure(URLError(.cannotConnectToHost))),
            defaults: UserDefaults(suiteName: #function)!
        )

        await store.reload()

        #expect(store.connectionState == .unavailable)
        #expect(store.errorMessage != nil)
    }
}

private struct StubCatalogLoader: CatalogLoading {
    let result: Result<[Album], Error>

    func fetchAlbums(from serverURL: URL) async throws -> [Album] {
        try result.get()
    }
}

private final class CatalogURLProtocol: URLProtocol, @unchecked Sendable {
    private static let response = """
        {
          "data": {
            "albums": [{
              "id": "20000000-0000-0000-0000-000000000001",
              "title": "Afterglow",
              "year": 2026,
              "artworkUrl": "http://localhost:8080/media/artwork/cover",
              "artist": {
                "id": "10000000-0000-0000-0000-000000000001",
                "name": "Aurora Lines"
              },
              "tracks": [{
                "id": "30000000-0000-0000-0000-000000000001",
                "title": "Night Drive",
                "durationMs": 96000,
                "artistName": "Aurora Lines",
                "albumTitle": "Afterglow",
                "streamUrl": "http://localhost:8080/media/tracks/track",
                "lyrics": [{
                  "id": "40000000-0000-0000-0000-000000000001",
                  "text": "Streetlights drawing silver lines",
                  "startMs": 0,
                  "endMs": 8000
                }]
              }]
            }]
          }
        }
        """.data(using: .utf8)!

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.path == "/graphql"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.response)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class PlaylistMutationURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var receivedBody: String?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.path == "/graphql"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.receivedBody = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
        let data = """
            {
              "data": {
                "playlist": {
                  "id": "50000000-0000-0000-0000-000000000001",
                  "name": "Night drive",
                  "description": "",
                  "artworkUrl": null,
                  "tracks": [{
                    "id": "30000000-0000-0000-0000-000000000001",
                    "title": "Night Drive",
                    "durationMs": 96000,
                    "artistName": "Aurora Lines",
                    "albumTitle": "Afterglow",
                    "streamUrl": "http://localhost:8080/media/tracks/track",
                    "lyrics": []
                  }]
                }
              }
            }
            """.data(using: .utf8)!
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
