import SwiftUI
import UniformTypeIdentifiers

/// Portable library backup and restore controls backed by the configured server.
struct OpenChordArchiveView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @State private var isImporting = false
    @State private var isWorking = false
    @State private var exportedArchive: URL?
    @State private var playlists: [OpenChordArchivePlaylist] = []
    @State private var message: String?
    @State private var errorMessage: String?

    private let client = OpenChordArchiveClient()

    var body: some View {
        List {
            Section {
                Button {
                    Task { await export() }
                } label: {
                    Label("Prepare Library Archive", systemImage: "arrow.down.doc.fill")
                }
                .disabled(isWorking)

                if let exportedArchive {
                    ShareLink(item: exportedArchive) {
                        Label("Save or Share Archive", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("shareOpenChordArchive")
                }
            } header: {
                Text("Entire library")
            } footer: {
                Text("Includes catalog metadata, artwork, playlists, and the server's current playable media.")
            }

            if !playlists.isEmpty {
                Section("Playlist") {
                    ForEach(playlists) { playlist in
                        Button {
                            Task { await export(playlistID: playlist.id) }
                        } label: {
                            HStack {
                                Label(playlist.name, systemImage: "music.note.list")
                                Spacer()
                                Text("\(playlist.tracks)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(isWorking)
                    }
                }
            }

            Section {
                Button {
                    isImporting = true
                } label: {
                    Label("Choose .openchord Archive", systemImage: "arrow.up.doc.fill")
                }
                .disabled(isWorking)
            } header: {
                Text("Restore")
            } footer: {
                Text("The server validates paths, sizes, and SHA-256 checksums before committing the archive.")
            }

            if isWorking {
                Section {
                    HStack {
                        ProgressView()
                        Text("Working with the server…")
                    }
                }
            }

            if let message {
                Section {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("OpenChord Archive")
        .task { await loadPlaylists() }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [UTType(filenameExtension: "openchord") ?? .zip, .zip],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let URLs) = result, let URL = URLs.first else {
                if case .failure(let error) = result {
                    errorMessage = error.localizedDescription
                }
                return
            }
            Task { await importArchive(URL) }
        }
    }

    private func loadPlaylists() async {
        do {
            playlists = try await client.playlists(from: catalog.serverURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func export(playlistID: UUID? = nil) async {
        isWorking = true
        message = nil
        errorMessage = nil
        defer { isWorking = false }
        do {
            exportedArchive = try await client.exportLibrary(
                from: catalog.serverURL,
                playlistID: playlistID
            )
            message = "Archive is ready to save or share."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importArchive(_ URL: URL) async {
        isWorking = true
        message = nil
        errorMessage = nil
        defer { isWorking = false }
        let accessed = URL.startAccessingSecurityScopedResource()
        defer {
            if accessed { URL.stopAccessingSecurityScopedResource() }
        }
        do {
            let result = try await client.importArchive(at: URL, to: catalog.serverURL)
            await catalog.reload()
            message =
                "Imported \(result.albums) albums, \(result.tracks) tracks, and \(result.playlists) playlists."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
