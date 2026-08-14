import SwiftUI

/// A task-focused landing page for resuming playback and finding fresh music.
struct HomeView: View {
    @Environment(PlaybackController.self) private var player
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var downloads: TrackDownloadStore

    let onOpenLibrary: () -> Void

    init(onOpenLibrary: @escaping () -> Void = {}) {
        self.onOpenLibrary = onOpenLibrary
    }

    var body: some View {
        Group {
            if catalog.isLoading && catalog.albums.isEmpty {
                ProgressView("Loading your music…")
            } else if catalog.albums.isEmpty {
                ContentUnavailableView(
                    "No Music Yet",
                    systemImage: "music.note.list",
                    description: Text("Connect to a server with music to start listening.")
                )
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: Album.self) { AlbumView(album: $0) }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if let continueTrack, let currentAlbum {
                    continueListening(currentAlbum, track: continueTrack)
                }

                albumShelf(
                    title: "Recently Added",
                    albums: recentlyAdded,
                    showsAllButton: true
                )

                if !downloadedAlbums.isEmpty {
                    albumShelf(
                        title: "Downloaded",
                        albums: downloadedAlbums,
                        showsAllButton: false
                    )
                }
            }
            .padding(.bottom, 20)
        }
        .refreshable { await catalog.reload() }
    }

    private func continueListening(_ album: Album, track: Track) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue Listening")
                .font(.title2.bold())
                .padding(.horizontal)

            NavigationLink(value: album) {
                HStack(spacing: 14) {
                    ArtworkView(style: album.artwork, cornerRadius: 14)
                        .frame(width: 92, height: 92)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(track.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(album.artist.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(album.title)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
        }
    }

    private func albumShelf(
        title: String,
        albums: [Album],
        showsAllButton: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title2.bold())

                Spacer()

                if showsAllButton {
                    Button("See All", action: onOpenLibrary)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .padding(.horizontal)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(albums) { album in
                        NavigationLink(value: album) {
                            HomeAlbumCard(album: album)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var currentAlbum: Album? {
        guard let trackID = continueTrack?.id else { return nil }
        return catalog.albums.first { album in
            album.tracks.contains(where: { $0.id == trackID })
        }
    }

    private var continueTrack: Track? {
        if let currentTrack = player.currentTrack {
            return currentTrack
        }
        guard let lastPlayedTrackID = player.lastPlayedTrackID else { return nil }
        return catalog.albums.lazy
            .flatMap(\.tracks)
            .first { $0.id == lastPlayedTrackID }
    }

    private var recentlyAdded: [Album] {
        catalog.albums.sorted {
            if $0.year != $1.year {
                return $0.year > $1.year
            }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private var downloadedAlbums: [Album] {
        catalog.albums.filter { album in
            !album.tracks.isEmpty
                && album.tracks.allSatisfy { downloads.state(for: $0) == .downloaded }
        }
    }
}

/// Compact artwork-led card used by the horizontal Home shelves.
private struct HomeAlbumCard: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ArtworkView(style: album.artwork, cornerRadius: 14)
                .frame(width: 154, height: 154)

            Text(album.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(album.artist.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 154, alignment: .leading)
    }
}
