import Foundation
import Testing
@testable import OpenChord

@Suite("OpenChord archive client")
struct OpenChordArchiveClientTests {
    private func client() -> OpenChordArchiveClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ArchiveURLProtocol.self]
        return OpenChordArchiveClient(session: URLSession(configuration: configuration))
    }

    @Test("Exports the library to a shareable temporary file")
    func exportsLibrary() async throws {
        let server = try #require(URL(string: "https://music.example"))
        let archive = try await client().exportLibrary(from: server)
        defer { try? FileManager.default.removeItem(at: archive.deletingLastPathComponent()) }

        #expect(archive.lastPathComponent == "OpenChord Library.openchord")
        #expect(try Data(contentsOf: archive) == Data("archive-bytes".utf8))
    }

    @Test("Imports a disk-backed archive and decodes the server summary")
    func importsArchive() async throws {
        let server = try #require(URL(string: "https://music.example"))
        let archive = FileManager.default.temporaryDirectory
            .appending(path: "archive-client-test.openchord")
        try Data("archive-bytes".utf8).write(to: archive)
        defer { try? FileManager.default.removeItem(at: archive) }

        let result = try await client().importArchive(at: archive, to: server)

        #expect(result == OpenChordArchiveImportSummary(albums: 2, tracks: 18, playlists: 1, skippedAlbums: 0))
    }

    @Test("Loads playlist export choices")
    func loadsPlaylists() async throws {
        let server = try #require(URL(string: "https://music.example"))
        let playlists = try await client().playlists(from: server)

        #expect(
            playlists == [
                OpenChordArchivePlaylist(
                    id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                    name: "Night drive",
                    tracks: 12
                )
            ])
    }
}

private final class ArchiveURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.path.hasPrefix("/api/admin/openchord/") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let isImport = path.hasSuffix("/import")
        let data: Data
        if isImport {
            data = Data(#"{"albums":2,"tracks":18,"playlists":1,"skippedAlbums":0}"#.utf8)
        } else if path.hasSuffix("/playlists") {
            data = Data(#"[{"id":"10000000-0000-0000-0000-000000000001","name":"Night drive","tracks":12}]"#.utf8)
        } else {
            data = Data("archive-bytes".utf8)
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": isImport ? "application/json" : "application/zip"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
