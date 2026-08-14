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

    /// Adds a track idempotently and updates the matching local playlist.
    func add(_ track: Track, to playlist: Playlist) async throws {
        let updated = try await playlistClient.add(
            trackID: track.id,
            to: playlist.id,
            at: serverURL
        )
        guard let index = playlists.firstIndex(where: { $0.id == updated.id }) else {
            playlists.insert(updated, at: 0)
            return
        }
        playlists[index] = updated
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
            albums = try await loader.fetchAlbums(from: serverURL)
            playlists = try await loader.fetchPlaylists(from: serverURL)
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

/// Validation failures produced before changing the configured server origin.
enum ServerAddressError: LocalizedError {
    case invalid

    var errorDescription: String? {
        "Enter a valid HTTP or HTTPS server address without a path."
    }
}
