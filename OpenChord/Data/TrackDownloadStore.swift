import Combine
import Foundation

@MainActor
/// Stores offline track copies and resolves them for playback.
///
/// Downloads are keyed by the server track identifier. A completed download is
/// discovered from disk rather than relying on transient in-memory state.
final class TrackDownloadStore: ObservableObject {
    /// Presentation state for a track's offline copy.
    enum State: Equatable {
        case idle
        case downloading
        case downloaded
        case failed
    }

    @Published private(set) var states: [UUID: State] = [:]
    @Published private(set) var downloadedTrackCount = 0
    @Published private(set) var downloadedBytes: Int64 = 0
    @Published var errorMessage: String?

    private let session: URLSession
    private let downloadsDirectory: URL

    init(
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        downloadsDirectory: URL? = nil
    ) {
        self.session = session
        let baseDirectory =
            downloadsDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "OpenChord/Downloads", directoryHint: .isDirectory)
        self.downloadsDirectory = baseDirectory
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        refreshStorageSummary()
    }

    func state(for track: Track) -> State {
        if localURL(for: track) != nil {
            return .downloaded
        }
        return states[track.id] ?? .idle
    }

    /// Downloads a track when it has a remote source and no local copy.
    ///
    /// The method coalesces repeated requests for the same track. Failures are
    /// reflected in ``states`` and ``errorMessage`` for presentation by the UI.
    ///
    /// - Parameter track: The catalog track to persist for offline playback.
    func download(_ track: Track) async {
        guard state(for: track) != .downloading, localURL(for: track) == nil else { return }
        guard case let .remote(remoteURL) = track.audioSource else { return }

        states[track.id] = .downloading
        do {
            let (temporaryURL, response) = try await session.download(from: remoteURL)
            guard
                let httpResponse = response as? HTTPURLResponse,
                (200..<300).contains(httpResponse.statusCode)
            else {
                throw DownloadError.invalidResponse
            }

            let destination = destinationURL(for: track, response: httpResponse)
            if FileManager.default.fileExists(atPath: destination.path()) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            states[track.id] = .downloaded
            refreshStorageSummary()
        } catch {
            states[track.id] = .failed
            errorMessage = "Couldn’t download “\(track.title)”. \(error.localizedDescription)"
        }
    }

    /// Downloads tracks sequentially to avoid saturating a self-hosted server.
    ///
    /// - Parameter tracks: Tracks to make available offline.
    func download(_ tracks: [Track]) async {
        for track in tracks where state(for: track) != .downloaded {
            await download(track)
        }
    }

    func removeDownload(for track: Track) throws {
        guard let url = localURL(for: track) else { return }
        try FileManager.default.removeItem(at: url)
        states[track.id] = .idle
        refreshStorageSummary()
    }

    func removeDownloads(for tracks: [Track]) throws {
        for track in tracks {
            try removeDownload(for: track)
        }
    }

    func removeAllDownloads() throws {
        for url in downloadedFiles() {
            try FileManager.default.removeItem(at: url)
        }
        states.removeAll()
        refreshStorageSummary()
    }

    /// Resolves a track to its local copy when one exists.
    ///
    /// - Parameter track: The catalog track requested for playback.
    /// - Returns: A copy whose audio source points at the downloaded file, or
    ///   the original track when it has not been downloaded.
    func playable(_ track: Track) -> Track {
        guard let localURL = localURL(for: track) else { return track }
        return track.using(audioSource: .remote(localURL))
    }

    func playable(_ tracks: [Track]) -> [Track] {
        tracks.map(playable)
    }

    private func localURL(for track: Track) -> URL? {
        let prefix = track.id.uuidString.lowercased() + "."
        return try? FileManager.default
            .contentsOfDirectory(at: downloadsDirectory, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.lowercased().hasPrefix(prefix) }
    }

    private func downloadedFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: downloadsDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private func refreshStorageSummary() {
        let files = downloadedFiles()
        downloadedTrackCount = files.count
        downloadedBytes = files.reduce(into: 0) { result, url in
            result += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    private func destinationURL(for track: Track, response: HTTPURLResponse) -> URL {
        let responseExtension = response.url?.pathExtension
        let sourceExtension = track.audioSource.url()?.pathExtension
        let fileExtension =
            [responseExtension, sourceExtension, fileExtension(for: response.mimeType)]
            .compactMap { $0 }
            .first { !$0.isEmpty } ?? "m4a"
        return downloadsDirectory.appending(path: "\(track.id.uuidString.lowercased()).\(fileExtension)")
    }

    private func fileExtension(for mimeType: String?) -> String? {
        switch mimeType?.lowercased() {
        case "audio/mpeg": "mp3"
        case "audio/mp4", "audio/x-m4a": "m4a"
        case "audio/aac": "aac"
        case "audio/ogg": "ogg"
        case "audio/opus": "opus"
        case "audio/flac": "flac"
        case "audio/wav", "audio/x-wav": "wav"
        default: nil
        }
    }
}

/// Internal validation failures for completed download responses.
private enum DownloadError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        "The server returned an invalid response."
    }
}
