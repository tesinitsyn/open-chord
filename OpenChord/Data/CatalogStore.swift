import Combine
import Foundation

@MainActor
/// Owns the loaded catalog and the user's selected OpenChord server.
///
/// The store serializes reloads and preserves the last successful catalog when
/// a later request fails, allowing the UI to remain useful while offline.
final class CatalogStore: ObservableObject {
    /// Reachability derived from the most recent catalog request.
    enum ConnectionState: Equatable {
        case unknown
        case connecting
        case connected
        case unavailable
    }

    static let serverURLKey = "openchord.serverURL"
    static let defaultServerAddress = "http://localhost:8080"

    @Published private(set) var albums: [Album] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var serverURL: URL
    @Published private(set) var connectionState: ConnectionState = .unknown

    private let loader: any CatalogLoading
    private let playlistClient: any PlaylistMutating
    private let defaults: UserDefaults
    private var hasLoaded = false

    init(
        loader: any CatalogLoading = CatalogAPIClient(),
        playlistClient: any PlaylistMutating = CatalogAPIClient(),
        defaults: UserDefaults = .standard
    ) {
        self.loader = loader
        self.playlistClient = playlistClient
        self.defaults = defaults
        let storedAddress = defaults.string(forKey: Self.serverURLKey) ?? Self.defaultServerAddress
        serverURL =
            Self.normalizedURL(from: storedAddress)
            ?? URL(string: Self.defaultServerAddress)!
    }

    /// Loads the catalog once for the lifetime of this store.
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    /// Refreshes the catalog unless a request is already in progress.
    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        connectionState = .connecting
        errorMessage = nil
        defer { isLoading = false }

        do {
            let snapshot = try await loader.fetchCatalog(from: serverURL)
            albums = snapshot.albums
            playlists = snapshot.playlists
            hasLoaded = true
            connectionState = .connected
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
            connectionState = .unavailable
        }
    }

    /// Persists a new server address and immediately reloads from it.
    ///
    /// - Parameter address: An HTTP or HTTPS origin without a path.
    /// - Throws: ``ServerAddressError/invalid`` when `address` cannot be
    ///   normalized to an allowed server URL.
    func updateServerAddress(_ address: String) async throws {
        guard let url = Self.normalizedURL(from: address) else {
            throw ServerAddressError.invalid
        }
        serverURL = url
        defaults.set(url.absoluteString, forKey: Self.serverURLKey)
        hasLoaded = false
        albums = []
        playlists = []
        await reload()
    }

    /// Creates a server-backed playlist and inserts it at the top of the library.
    func createPlaylist(_ creation: PlaylistCreation) async throws {
        let playlist = try await playlistClient.createPlaylist(creation, at: serverURL)
        playlists.removeAll { $0.id == playlist.id }
        playlists.insert(playlist, at: 0)
    }

    /// Removes a playlist from the server before updating local presentation state.
    func deletePlaylist(_ playlist: Playlist) async throws {
        try await playlistClient.deletePlaylist(id: playlist.id, at: serverURL)
        playlists.removeAll { $0.id == playlist.id }
    }

    /// Renames a playlist while preserving its current ordered membership.
    func renamePlaylist(_ playlist: Playlist, to name: String) async throws {
        let updated = try await playlistClient.renamePlaylist(
            id: playlist.id,
            to: name,
            at: serverURL
        )
        replace(updated)
    }

    /// Adds a track idempotently and replaces the matching local playlist snapshot.
    func add(_ track: Track, to playlist: Playlist) async throws {
        let updated = try await playlistClient.add(
            trackID: track.id,
            to: playlist.id,
            at: serverURL
        )
        replace(updated)
    }

    /// Removes a track and replaces the matching local playlist snapshot.
    func remove(_ track: Track, from playlist: Playlist) async throws {
        let updated = try await playlistClient.remove(
            trackID: track.id,
            from: playlist.id,
            at: serverURL
        )
        replace(updated)
    }

    private func replace(_ playlist: Playlist) {
        var artworkByAlbum: [PlaylistArtworkKey: ArtworkStyle] = [:]
        for album in albums {
            artworkByAlbum[
                PlaylistArtworkKey(title: album.title, artistName: album.artist.name)
            ] = album.artwork
        }
        let decorated = Playlist(
            id: playlist.id,
            name: playlist.name,
            description: playlist.description,
            createdAt: playlist.createdAt,
            updatedAt: playlist.updatedAt,
            tracks: playlist.tracks.map { track in
                let key = PlaylistArtworkKey(
                    title: track.albumTitle,
                    artistName: track.artistName
                )
                guard let artwork = artworkByAlbum[key] else { return track }
                return track.using(artwork: artwork)
            },
            artwork: playlist.artwork
        )
        guard let index = playlists.firstIndex(where: { $0.id == decorated.id }) else {
            playlists.insert(decorated, at: 0)
            return
        }
        playlists[index] = decorated
    }

    /// Converts user input into an HTTP or HTTPS server origin.
    ///
    /// - Parameter address: The value entered in server settings.
    /// - Returns: A normalized URL with no query or fragment, or `nil` when the
    ///   input is not a valid server origin.
    static func normalizedURL(from address: String) -> URL? {
        var value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.contains("://") {
            value = "http://\(value)"
        }
        guard
            var components = URLComponents(string: value),
            components.scheme == "http" || components.scheme == "https",
            components.host != nil
        else { return nil }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard components.path.isEmpty else { return nil }
        return components.url
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
                return
                    "Cannot reach the OpenChord server. Check its address and make sure both devices are on the same network."
            case .timedOut:
                return "The OpenChord server did not respond in time."
            default:
                break
            }
        }
        return error.localizedDescription
    }
}

private struct PlaylistArtworkKey: Hashable {
    let title: String
    let artistName: String
}

/// Validation failures produced before changing the configured server origin.
enum ServerAddressError: LocalizedError {
    case invalid

    var errorDescription: String? {
        "Enter a valid HTTP or HTTPS server address without a path."
    }
}
