import Foundation

/// Result returned after the server commits a portable archive import.
struct OpenChordArchiveImportSummary: Decodable, Equatable {
    let albums: Int
    let tracks: Int
    let playlists: Int
    let skippedAlbums: Int
}

struct OpenChordArchivePlaylist: Decodable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let tracks: Int
}

/// Streams `.openchord` archives between the Files system and an OpenChord server.
struct OpenChordArchiveClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func playlists(from serverURL: URL) async throws -> [OpenChordArchivePlaylist] {
        let URL = serverURL.appending(path: "api/admin/openchord/playlists")
        let (data, response) = try await session.data(from: URL)
        try Self.requireSuccess(response)
        return try JSONDecoder().decode([OpenChordArchivePlaylist].self, from: data)
    }

    /// Downloads an archive to a stable temporary URL suitable for `ShareLink`.
    func exportLibrary(from serverURL: URL, playlistID: UUID? = nil) async throws -> URL {
        var components = URLComponents(
            url: serverURL.appending(path: "api/admin/openchord/export"),
            resolvingAgainstBaseURL: false
        )!
        if let playlistID {
            components.queryItems = [
                URLQueryItem(name: "scope", value: "playlist"),
                URLQueryItem(name: "playlistId", value: playlistID.uuidString),
            ]
        } else {
            components.queryItems = [URLQueryItem(name: "scope", value: "library")]
        }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 60 * 60
        let (download, response) = try await session.download(for: request)
        try Self.requireSuccess(response)

        let name =
            playlistID == nil
            ? "OpenChord Library.openchord"
            : "OpenChord Playlist.openchord"
        let destination = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .appending(path: name)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: download, to: destination)
        return destination
    }

    /// Uploads an archive with a disk-backed multipart body.
    func importArchive(at archiveURL: URL, to serverURL: URL) async throws
        -> OpenChordArchiveImportSummary
    {
        let boundary = "OpenChord-\(UUID().uuidString)"
        let bodyURL = try Self.makeMultipartBody(archiveURL: archiveURL, boundary: boundary)
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        var request = URLRequest(url: serverURL.appending(path: "api/admin/openchord/import"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60 * 60
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        let (data, response) = try await session.upload(for: request, fromFile: bodyURL)
        try Self.requireSuccess(response)
        return try JSONDecoder().decode(OpenChordArchiveImportSummary.self, from: data)
    }

    private static func makeMultipartBody(archiveURL: URL, boundary: String) throws -> URL {
        let bodyURL = FileManager.default.temporaryDirectory
            .appending(path: "openchord-upload-\(UUID().uuidString).body")
        FileManager.default.createFile(atPath: bodyURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: bodyURL)
        defer { try? output.close() }
        try output.write(
            contentsOf: Data(
                """
                --\(boundary)\r
                Content-Disposition: form-data; name="archive"; filename="library.openchord"\r
                Content-Type: application/vnd.openchord.archive+zip\r
                \r

                """.utf8
            )
        )

        let input = try FileHandle(forReadingFrom: archiveURL)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
        try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
        return bodyURL
    }

    private static func requireSuccess(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else {
            throw OpenChordArchiveError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw OpenChordArchiveError.httpStatus(response.statusCode)
        }
    }
}

enum OpenChordArchiveError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The server returned an invalid archive response."
        case .httpStatus(let status):
            "The archive operation failed with HTTP \(status)."
        }
    }
}
