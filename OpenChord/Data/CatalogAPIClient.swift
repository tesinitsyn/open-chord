import Foundation

/// Loads the catalog from an OpenChord server.
protocol CatalogLoading: Sendable {
    /// Fetches the server's current catalog and user playlists.
    ///
    /// - Parameter serverURL: The normalized base URL of the OpenChord server.
    /// - Returns: One consistent catalog snapshot.
    /// - Throws: A transport, decoding, or server-reported error.
    func fetchCatalog(from serverURL: URL) async throws -> CatalogSnapshot
}

/// Atomically loaded public catalog state.
struct CatalogSnapshot {
    let albums: [Album]
    let playlists: [Playlist]
}

/// Playlist mutations supported by the server.
protocol PlaylistMutating: Sendable {
    func createPlaylist(_ creation: PlaylistCreation, at serverURL: URL) async throws -> Playlist
    func renamePlaylist(id: UUID, to name: String, at serverURL: URL) async throws -> Playlist
    func deletePlaylist(id: UUID, at serverURL: URL) async throws
    func add(trackID: UUID, to playlistID: UUID, at serverURL: URL) async throws -> Playlist
    func remove(trackID: UUID, from playlistID: UUID, at serverURL: URL) async throws -> Playlist
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
    func fetchCatalog(from serverURL: URL) async throws -> CatalogSnapshot {
        do {
            let payload: CatalogPayload = try await execute(
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
                      playlists {
                        id
                        name
                        description
                        artworkUrl
                        createdAt
                        updatedAt
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
                    """,
                variables: EmptyVariables(),
                at: serverURL
            )
            return makeSnapshot(
                albums: payload.albums,
                playlists: payload.playlists,
                relativeTo: serverURL
            )
        } catch CatalogAPIError.graphQL(let message)
            where Self.isMissingPlaylistsField(message)
        {
            // Keep the catalog usable during a rolling deployment where the
            // client reaches a server that predates playlist support.
            let payload: LegacyCatalogPayload = try await execute(
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
                    """,
                variables: EmptyVariables(),
                at: serverURL
            )
            return makeSnapshot(albums: payload.albums, playlists: [], relativeTo: serverURL)
        }
    }

    private func makeSnapshot(
        albums albumDTOs: [AlbumDTO],
        playlists playlistDTOs: [PlaylistDTO],
        relativeTo serverURL: URL
    ) -> CatalogSnapshot {
        let albums = albumDTOs.map { $0.album(relativeTo: serverURL) }
        var artworkByAlbum: [AlbumArtworkKey: ArtworkStyle] = [:]
        for album in albums {
            artworkByAlbum[
                AlbumArtworkKey(title: album.title, artistName: album.artist.name)
            ] = album.artwork
        }
        return CatalogSnapshot(
            albums: albums,
            playlists: playlistDTOs.map {
                $0.playlist(relativeTo: serverURL, artworkByAlbum: artworkByAlbum)
            }
        )
    }

    private static func isMissingPlaylistsField(_ message: String) -> Bool {
        message.contains("Field 'playlists'") && message.contains("undefined")
    }

    func createPlaylist(_ creation: PlaylistCreation, at serverURL: URL) async throws -> Playlist {
        let boundary = "OpenChord-\(UUID().uuidString)"
        var request = URLRequest(url: serverURL.appending(path: "api/playlists"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = Self.multipartBody(for: creation, boundary: boundary)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw CatalogAPIError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw CatalogAPIError.httpStatus(response.statusCode)
        }
        let decoder = Self.decoder()
        let payload = try decoder.decode(PlaylistDTO.self, from: data)
        return payload.playlist(relativeTo: serverURL, artworkByAlbum: [:])
    }

    func renamePlaylist(id: UUID, to name: String, at serverURL: URL) async throws -> Playlist {
        let payload: PlaylistMutationPayload = try await execute(
            query: """
                mutation RenamePlaylist($id: ID!, $name: String!) {
                  playlist: renamePlaylist(id: $id, name: $name) { \(Self.playlistFields) }
                }
                """,
            variables: RenameVariables(id: id, name: name),
            at: serverURL
        )
        return payload.playlist.playlist(relativeTo: serverURL, artworkByAlbum: [:])
    }

    func deletePlaylist(id: UUID, at serverURL: URL) async throws {
        let _: DeletePlaylistPayload = try await execute(
            query: """
                mutation DeletePlaylist($id: ID!) {
                  deleted: deletePlaylist(id: $id)
                }
                """,
            variables: IDVariables(id: id),
            at: serverURL
        )
    }

    func add(trackID: UUID, to playlistID: UUID, at serverURL: URL) async throws -> Playlist {
        try await mutateMembership(
            operation: "addTrackToPlaylist",
            trackID: trackID,
            playlistID: playlistID,
            serverURL: serverURL
        )
    }

    func remove(trackID: UUID, from playlistID: UUID, at serverURL: URL) async throws -> Playlist {
        try await mutateMembership(
            operation: "removeTrackFromPlaylist",
            trackID: trackID,
            playlistID: playlistID,
            serverURL: serverURL
        )
    }

    private func mutateMembership(
        operation: String,
        trackID: UUID,
        playlistID: UUID,
        serverURL: URL
    ) async throws -> Playlist {
        let payload: PlaylistMutationPayload = try await execute(
            query: """
                mutation UpdatePlaylist($playlistId: ID!, $trackId: ID!) {
                  playlist: \(operation)(playlistId: $playlistId, trackId: $trackId) {
                    \(Self.playlistFields)
                  }
                }
                """,
            variables: MembershipVariables(playlistId: playlistID, trackId: trackID),
            at: serverURL
        )
        return payload.playlist.playlist(relativeTo: serverURL, artworkByAlbum: [:])
    }

    private func execute<Variables: Encodable, Payload: Decodable>(
        query: String,
        variables: Variables,
        at serverURL: URL
    ) async throws -> Payload {
        var request = URLRequest(url: serverURL.appending(path: "graphql"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 12
        request.httpBody = try JSONEncoder().encode(
            GraphQLRequest(query: query, variables: variables)
        )
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CatalogAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CatalogAPIError.httpStatus(httpResponse.statusCode)
        }

        let decoder = Self.decoder()
        let envelope = try decoder.decode(GraphQLEnvelope<Payload>.self, from: data)
        if let message = envelope.errors?.first?.message {
            throw CatalogAPIError.graphQL(message)
        }
        guard let payload = envelope.data else {
            throw CatalogAPIError.invalidResponse
        }
        return payload
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value)
                ?? ISO8601DateFormatter().date(from: value)
            {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Invalid ISO-8601 timestamp: \(value)"
            )
        }
        return decoder
    }

    private static func multipartBody(
        for creation: PlaylistCreation,
        boundary: String
    ) -> Data {
        var body = Data()
        func append(_ value: String) {
            body.append(Data(value.utf8))
        }
        for (name, value) in [
            ("name", creation.name),
            ("description", creation.description),
        ] {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        if let artwork = creation.artworkData {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"artwork\"; filename=\"artwork.jpg\"\r\n")
            append("Content-Type: image/jpeg\r\n\r\n")
            body.append(artwork)
            append("\r\n")
        }
        append("--\(boundary)--\r\n")
        return body
    }

    private static let playlistFields = """
        id name description artworkUrl createdAt updatedAt
        tracks {
          id title durationMs artistName albumTitle streamUrl
          lyrics { id text startMs endMs }
        }
        """
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
private struct GraphQLRequest<Variables: Encodable>: Encodable {
    let query: String
    let variables: Variables
}

private struct EmptyVariables: Encodable {}
private struct IDVariables: Encodable { let id: UUID }
private struct RenameVariables: Encodable {
    let id: UUID
    let name: String
}
private struct MembershipVariables: Encodable {
    let playlistId: UUID
    let trackId: UUID
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
    let playlists: [PlaylistDTO]
}

/// Catalog shape exposed by servers deployed before playlist support.
private struct LegacyCatalogPayload: Decodable {
    let albums: [AlbumDTO]
}

private struct PlaylistMutationPayload: Decodable {
    let playlist: PlaylistDTO
}

private struct DeletePlaylistPayload: Decodable {
    let deleted: Bool
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

private struct PlaylistDTO: Decodable {
    let id: UUID
    let name: String
    let description: String
    let artworkUrl: String?
    let createdAt: Date
    let updatedAt: Date
    let tracks: [TrackDTO]

    func playlist(
        relativeTo serverURL: URL,
        artworkByAlbum: [AlbumArtworkKey: ArtworkStyle]
    ) -> Playlist {
        Playlist(
            id: id,
            name: name,
            description: description,
            createdAt: createdAt,
            updatedAt: updatedAt,
            tracks: tracks.map {
                $0.track(
                    relativeTo: serverURL,
                    artwork: artworkByAlbum[
                        AlbumArtworkKey(title: $0.albumTitle, artistName: $0.artistName)
                    ]
                        ?? ArtworkStyle(symbol: "music.note", colors: [.indigo, .violet])
                )
            },
            artwork:
                artworkUrl
                .flatMap(URL.init(string:))
                .map { serverURL.replacingPath(with: $0) }
                .map {
                    ArtworkStyle(
                        symbol: "music.note.list",
                        colors: [.indigo, .violet],
                        remoteURL: $0
                    )
                }
        )
    }
}

private struct AlbumArtworkKey: Hashable {
    let title: String
    let artistName: String
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
