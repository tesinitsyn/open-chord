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

        let catalog = try await client.fetchCatalog(from: serverURL)
        let album = try #require(catalog.albums.first)
        let track = try #require(album.tracks.first)
        let playlist = try #require(catalog.playlists.first)

        #expect(album.title == "Afterglow")
        #expect(track.lyrics.first?.text == "Streetlights drawing silver lines")
        #expect(track.duration == 96)
        #expect(track.audioSource.url()?.absoluteString == "http://192.168.1.20:8080/media/tracks/track")
        #expect(album.artwork.remoteURL?.absoluteString == "http://192.168.1.20:8080/media/artwork/cover")
        #expect(playlist.name == "Night Drive")
        #expect(playlist.tracks.first?.id == track.id)
    }

    @Test("Falls back to albums when the server predates playlist support")
    func fallsBackToLegacyCatalogSchema() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LegacyCatalogURLProtocol.self]
        let client = CatalogAPIClient(session: URLSession(configuration: configuration))
        let serverURL = try #require(URL(string: "http://192.168.1.20:8080"))

        let catalog = try await client.fetchCatalog(from: serverURL)

        #expect(catalog.albums.map(\.title) == ["Afterglow"])
        #expect(catalog.playlists.isEmpty)
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
            loader: StubCatalogLoader(
                result: .success(CatalogSnapshot(albums: [], playlists: []))
            ),
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

    @Test("Creating a playlist updates the local library snapshot")
    @MainActor
    func creatingPlaylistUpdatesSnapshot() async throws {
        let playlist = Playlist(
            id: UUID(),
            name: "Night Drive",
            createdAt: .now,
            updatedAt: .now,
            tracks: []
        )
        let store = CatalogStore(
            loader: StubCatalogLoader(
                result: .success(CatalogSnapshot(albums: [], playlists: []))
            ),
            playlistClient: StubPlaylistClient(created: playlist),
            defaults: UserDefaults(suiteName: #function)!
        )

        try await store.createPlaylist(
            PlaylistCreation(name: playlist.name, description: "", artworkData: nil)
        )

        #expect(store.playlists == [playlist])
    }
}

private struct StubCatalogLoader: CatalogLoading {
    let result: Result<CatalogSnapshot, Error>

    func fetchCatalog(from serverURL: URL) async throws -> CatalogSnapshot {
        try result.get()
    }
}

private struct StubPlaylistClient: PlaylistMutating {
    let created: Playlist

    func createPlaylist(_ creation: PlaylistCreation, at serverURL: URL) async throws -> Playlist {
        created
    }

    func renamePlaylist(id: UUID, to name: String, at serverURL: URL) async throws -> Playlist {
        created
    }

    func deletePlaylist(id: UUID, at serverURL: URL) async throws {}

    func add(trackID: UUID, to playlistID: UUID, at serverURL: URL) async throws -> Playlist {
        created
    }

    func remove(trackID: UUID, from playlistID: UUID, at serverURL: URL) async throws -> Playlist {
        created
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
            }],
            "playlists": [{
              "id": "50000000-0000-0000-0000-000000000001",
              "name": "Night Drive",
              "description": "",
              "artworkUrl": null,
              "createdAt": "2026-07-27T12:00:00Z",
              "updatedAt": "2026-07-27T12:00:00Z",
              "tracks": [{
                "id": "30000000-0000-0000-0000-000000000001",
                "title": "Night Drive",
                "durationMs": 96000,
                "artistName": "Aurora Lines",
                "albumTitle": "Afterglow",
                "streamUrl": "http://localhost:8080/media/tracks/track",
                "lyrics": []
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

private final class LegacyCatalogURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.path == "/graphql"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let requestData = request.httpBody ?? request.httpBodyStream.flatMap(Self.read)
        let query =
            requestData
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["query"]
            as? String
        let body =
            if query?.contains("playlists") == true {
                """
                {
                  "errors": [{
                    "message": "Validation error (FieldUndefined@[playlists]) : Field 'playlists' in type 'Query' is undefined"
                  }]
                }
                """
            } else {
                """
                {
                  "data": {
                    "albums": [{
                      "id": "20000000-0000-0000-0000-000000000001",
                      "title": "Afterglow",
                      "year": 2026,
                      "artworkUrl": null,
                      "artist": {
                        "id": "10000000-0000-0000-0000-000000000001",
                        "name": "Aurora Lines"
                      },
                      "tracks": []
                    }]
                  }
                }
                """
            }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data? {
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
