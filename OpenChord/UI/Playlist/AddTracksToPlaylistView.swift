import SwiftUI

/// Focused playlist membership flows shared by album and playlist screens.
struct AddTrackToPlaylistView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @Environment(\.dismiss) private var dismiss

    let track: Track
    @State private var mutationError: String?
    @State private var updatingPlaylistID: UUID?

    var body: some View {
        NavigationStack {
            List {
                if catalog.playlists.isEmpty {
                    ContentUnavailableView(
                        "No Playlists",
                        systemImage: "music.note.list",
                        description: Text("Create a playlist from Library, then add this track.")
                    )
                } else {
                    ForEach(catalog.playlists) { playlist in
                        Button {
                            add(to: playlist)
                        } label: {
                            playlistRow(playlist)
                        }
                        .buttonStyle(.plain)
                        .disabled(containsTrack(playlist) || updatingPlaylistID != nil)
                    }
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(
                "Could Not Add Track",
                isPresented: Binding(
                    get: { mutationError != nil },
                    set: { if !$0 { mutationError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(mutationError ?? "")
            }
        }
    }

    private func playlistRow(_ playlist: Playlist) -> some View {
        HStack(spacing: 12) {
            ArtworkView(style: playlist.artwork, cornerRadius: 8)
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(playlist.tracks.count) tracks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if updatingPlaylistID == playlist.id {
                ProgressView()
            } else if containsTrack(playlist) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Already added")
            } else {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }

    private func containsTrack(_ playlist: Playlist) -> Bool {
        playlist.tracks.contains { $0.id == track.id }
    }

    private func add(to playlist: Playlist) {
        updatingPlaylistID = playlist.id
        Task {
            do {
                try await catalog.add(track, to: playlist)
                dismiss()
            } catch {
                updatingPlaylistID = nil
                mutationError = error.localizedDescription
            }
        }
    }
}

struct AddTracksToPlaylistView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @Environment(\.dismiss) private var dismiss

    let playlistID: UUID
    @State private var query = ""
    @State private var selectedTrackIDs: Set<UUID> = []
    @State private var isSaving = false
    @State private var mutationError: String?

    var body: some View {
        NavigationStack {
            Group {
                if availableTracks.isEmpty {
                    ContentUnavailableView(
                        query.isEmpty ? "All Music Added" : "No Results",
                        systemImage: query.isEmpty ? "checkmark.circle" : "magnifyingglass",
                        description: Text(
                            query.isEmpty
                                ? "Every track in your library is already in this playlist."
                                : "Try another title, artist, or album."
                        )
                    )
                } else {
                    List(availableTracks) { track in
                        Button {
                            toggle(track)
                        } label: {
                            trackRow(track)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Add Music")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Songs, artists, or albums")
            .disabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Adding…" : addButtonTitle) { save() }
                        .disabled(selectedTrackIDs.isEmpty || isSaving)
                }
            }
            .alert(
                "Could Not Add Music",
                isPresented: Binding(
                    get: { mutationError != nil },
                    set: { if !$0 { mutationError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(mutationError ?? "")
            }
        }
    }

    private var playlist: Playlist? {
        catalog.playlists.first { $0.id == playlistID }
    }

    private var availableTracks: [Track] {
        let existingIDs = Set(playlist?.tracks.map(\.id) ?? [])
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<UUID>()
        return catalog.albums
            .flatMap(\.tracks)
            .filter { seen.insert($0.id).inserted && !existingIDs.contains($0.id) }
            .filter { track in
                normalizedQuery.isEmpty
                    || track.title.localizedCaseInsensitiveContains(normalizedQuery)
                    || track.artistName.localizedCaseInsensitiveContains(normalizedQuery)
                    || track.albumTitle.localizedCaseInsensitiveContains(normalizedQuery)
            }
    }

    private var addButtonTitle: String {
        selectedTrackIDs.isEmpty ? "Add" : "Add \(selectedTrackIDs.count)"
    }

    private func trackRow(_ track: Track) -> some View {
        HStack(spacing: 12) {
            ArtworkView(style: track.artwork, cornerRadius: 7)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).foregroundStyle(.primary).lineLimit(1)
                Text("\(track.artistName) · \(track.albumTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: selectedTrackIDs.contains(track.id) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selectedTrackIDs.contains(track.id) ? Color.accentColor : .secondary)
                .font(.title3)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selectedTrackIDs.contains(track.id) ? .isSelected : [])
    }

    private func toggle(_ track: Track) {
        if !selectedTrackIDs.insert(track.id).inserted {
            selectedTrackIDs.remove(track.id)
        }
    }

    private func save() {
        guard let playlist else { return }
        let tracks = availableTracks.filter { selectedTrackIDs.contains($0.id) }
        isSaving = true
        Task {
            do {
                for track in tracks {
                    try await catalog.add(track, to: playlist)
                }
                dismiss()
            } catch {
                isSaving = false
                mutationError = error.localizedDescription
            }
        }
    }
}
