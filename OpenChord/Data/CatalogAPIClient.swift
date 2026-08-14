import Foundation

/// Loads the catalog from an OpenChord server.
protocol CatalogLoading: Sendable {
    /// Fetches the server's current albums.
    ///
    /// - Parameter serverURL: The normalized base URL of the OpenChord server.
    /// - Returns: Albums in the order supplied by the catalog API.
    /// - Throws: A transport, decoding, or server-reported error.
    func fetchAlbums(from serverURL: URL) async throws -> [Album]
    func fetchPlaylists(from serverURL: URL) async throws -> [Playlist]
}

/// Playlist mutations used by track action menus.
protocol PlaylistMutating: Sendable {
    func add(trackID: UUID, to playlistID: UUID, at serverURL: URL) async throws -> Playlist
}

extension CatalogLoading {
    func fetchPlaylists(from serverURL: URL) async throws -> [Playlist] { [] }
}

/// A GraphQL-backed catalog loader.
struct CatalogAPIClient: CatalogLoading, PlaylistMutating {
    private let session: URLSession

    /// Creates a catalog client.
    ///
    /// - Parameter session: The session used for requests. Tests can supply an
    ///   isolated session with a custom protocol handler.
    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetches and maps the catalog from an OpenChord GraphQL endpoint.
    ///
    /// - Parameter serverURL: The normalized server base URL.
    /// - Returns: Domain albums with media URLs resolved against `serverURL`.
    /// - Throws: ``CatalogAPIError`` for invalid HTTP or GraphQL responses, or
    ///   an error produced by `URLSession` or `JSONDecoder`.
    func fetchAlbums(from serverURL: URL) async throws -> [Album] {
        let endpoint = serverURL.appending(path: "graphql")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 12
        request.httpBody = try JSONEncoder().encode(
            GraphQLRequest(
                query: """
                    query OpenChordCatalog {
                      albums {
                        id
                        title
                        year
                        artworkUrl
                        artist { id name }
                        tracks {
                          id
                          title
                          durationMs
                          artistName
                          albumTitle
                          streamUrl
                          lyrics { id text startMs endMs }
                        }
                      }
                    }
                    """
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CatalogAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CatalogAPIError.httpStatus(httpResponse.statusCode)
        }

        let envelope = try JSONDecoder().decode(GraphQLEnvelope<CatalogPayload>.self, from: data)
        if let message = envelope.errors?.first?.message {
            throw CatalogAPIError.graphQL(message)
        }
        guard let payload = envelope.data else {
            throw CatalogAPIError.invalidResponse
        }
        return payload.albums.map { $0.album(relativeTo: serverURL) }
    }

    func fetchPlaylists(from serverURL: URL) async throws -> [Playlist] {
        let endpoint = serverURL.appending(path: "graphql")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 12
        request.httpBody = try JSONEncoder().encode(
            GraphQLRequest(
                query: """
                    query OpenChordPlaylists {
                      playlists {
                        id name description artworkUrl
                        tracks { id title durationMs artistName albumTitle streamUrl lyrics { id text startMs endMs } }
                      }
                    }
                    """
            )
        )
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw CatalogAPIError.invalidResponse }
        guard (200..<300).contains(httpResponse.statusCode) else { throw CatalogAPIError.httpStatus(httpResponse.statusCode) }
        let envelope = try JSONDecoder().decode(GraphQLEnvelope<PlaylistPayload>.self, from: data)
        if let message = envelope.errors?.first?.message { throw CatalogAPIError.graphQL(message) }
        guard let payload = envelope.data else { throw CatalogAPIError.invalidResponse }
        return payload.playlists.map { $0.playlist(relativeTo: serverURL) }
    }

    func add(trackID: UUID, to playlistID: UUID, at serverURL: URL) async throws -> Playlist {
        let endpoint = serverURL.appending(path: "graphql")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 12
        request.httpBody = try JSONEncoder().encode(
            PlaylistMutationRequest(
                query: """
                    mutation AddTrackToPlaylist($playlistID: ID!, $trackID: ID!) {
                      playlist: addTrackToPlaylist(playlistId: $playlistID, trackId: $trackID) {
                        id name description artworkUrl
                        tracks { id title durationMs artistName albumTitle streamUrl lyrics { id text startMs endMs } }
                      }
                    }
                    """,
                variables: PlaylistMutationVariables(playlistID: playlistID, trackID: trackID)
            )
        )
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw CatalogAPIError.invalidResponse }
        guard (200..<300).contains(httpResponse.statusCode) else { throw CatalogAPIError.httpStatus(httpResponse.statusCode) }
        let envelope = try JSONDecoder().decode(GraphQLEnvelope<PlaylistMutationPayload>.self, from: data)
        if let message = envelope.errors?.first?.message { throw CatalogAPIError.graphQL(message) }
        guard let payload = envelope.data else { throw CatalogAPIError.invalidResponse }
        return payload.playlist.playlist(relativeTo: serverURL)
    }
}

/// Errors produced after a catalog request reaches the server.
enum CatalogAPIError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case graphQL(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The server returned an invalid response."
        case let .httpStatus(status):
            "The server returned HTTP \(status)."
        case let .graphQL(message):
            message
        }
    }
}

/// Minimal request body accepted by the catalog GraphQL endpoint.
private struct GraphQLRequest: Encodable {
    let query: String
}

private struct PlaylistMutationRequest: Encodable {
    let query: String
    let variables: PlaylistMutationVariables
}

private struct PlaylistMutationVariables: Encodable {
    let playlistID: UUID
    let trackID: UUID
}

/// GraphQL response wrapper that keeps transport errors separate from payload decoding.
private struct GraphQLEnvelope<Payload: Decodable>: Decodable {
    let data: Payload?
    let errors: [GraphQLError]?
}

/// Server-reported GraphQL error fields used by the client.
private struct GraphQLError: Decodable {
    let message: String
}

/// Root payload for the catalog query.
private struct CatalogPayload: Decodable {
    let albums: [AlbumDTO]
}

private struct PlaylistPayload: Decodable {
    let playlists: [PlaylistDTO]
}

private struct PlaylistMutationPayload: Decodable {
    let playlist: PlaylistDTO
}

private struct PlaylistDTO: Decodable {
    let id: UUID
    let name: String
    let description: String
    let artworkUrl: String?
    let tracks: [TrackDTO]

    func playlist(relativeTo serverURL: URL) -> Playlist {
        let artworkURL = artworkUrl.flatMap(URL.init(string:)).map { serverURL.replacingPath(with: $0) }
        let artwork = ArtworkStyle.forAlbum(id, remoteURL: artworkURL)
        return Playlist(
            id: id,
            name: name,
            description: description,
            artwork: artwork,
            tracks: tracks.map { $0.track(relativeTo: serverURL, artwork: artwork) }
        )
    }
}

/// Wire representation of an artist.
private struct ArtistDTO: Decodable {
    let id: UUID
    let name: String
}

/// Wire representation responsible for mapping an album aggregate to the domain.
private struct AlbumDTO: Decodable {
    let id: UUID
    let title: String
    let year: Int
    let artworkUrl: String?
    let artist: ArtistDTO
    let tracks: [TrackDTO]

    func album(relativeTo serverURL: URL) -> Album {
        let artworkURL =
            artworkUrl
            .flatMap(URL.init(string:))
            .map { serverURL.replacingPath(with: $0) }
        let style = ArtworkStyle.forAlbum(id, remoteURL: artworkURL)
        return Album(
            id: id,
            title: title,
            artist: Artist(id: artist.id, name: artist.name),
            year: year,
            artwork: style,
            tracks: tracks.map { $0.track(relativeTo: serverURL, artwork: style) }
        )
    }
}

/// Wire representation responsible for resolving a track's media URL.
private struct TrackDTO: Decodable {
    let id: UUID
    let title: String
    let durationMs: Int64
    let artistName: String
    let albumTitle: String
    let streamUrl: String
    let lyrics: [LyricLineDTO]

    func track(relativeTo serverURL: URL, artwork: ArtworkStyle) -> Track {
        let mediaURL =
            URL(string: streamUrl).map { serverURL.replacingPath(with: $0) }
            ?? serverURL.appending(path: "media/tracks/\(id.uuidString)")
        return Track(
            id: id,
            title: title,
            artistName: artistName,
            albumTitle: albumTitle,
            duration: TimeInterval(durationMs) / 1_000,
            audioSource: .remote(mediaURL),
            artwork: artwork,
            lyrics: lyrics.map(\.lyricLine)
        )
    }
}

/// Millisecond-based lyric interval returned by the backend.
private struct LyricLineDTO: Decodable {
    let id: UUID
    let text: String
    let startMs: Int64
    let endMs: Int64

    var lyricLine: LyricLine {
        LyricLine(
            id: id,
            text: text,
            startTime: TimeInterval(startMs) / 1_000,
            endTime: TimeInterval(endMs) / 1_000
        )
    }
}

private extension URL {
    func replacingPath(with remoteURL: URL) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return remoteURL
        }
        components.path = remoteURL.path
        components.query = remoteURL.query
        return components.url ?? remoteURL
    }
}

private extension ArtworkStyle {
    static func forAlbum(_ id: UUID, remoteURL: URL?) -> ArtworkStyle {
        let variants: [ArtworkStyle] = [
            ArtworkStyle(symbol: "sparkles", colors: [.violet, .pink, .orange]),
            ArtworkStyle(symbol: "moon.stars", colors: [.indigo, .blue, .cyan]),
            ArtworkStyle(symbol: "waveform", colors: [.red, .pink, .violet]),
            ArtworkStyle(symbol: "music.note", colors: [.blue, .cyan, .mint]),
        ]
        let index = id.uuidString.utf8.reduce(0) { $0 + Int($1) } % variants.count
        let fallback = variants[index]
        return ArtworkStyle(symbol: fallback.symbol, colors: fallback.colors, remoteURL: remoteURL)
    }
}
