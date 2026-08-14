import SwiftUI

/// Searchable, filterable entry point for the user's album collection.
struct LibraryView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case albums = "Albums"
        case artists = "Artists"
        case playlists = "Playlists"
        case downloaded = "Downloaded"

        var id: Self { self }
    }

    private enum SortOrder: String, CaseIterable, Identifiable {
        case recentlyAdded = "Recently Added"
        case album = "Album"
        case artist = "Artist"

        var id: Self { self }
    }

    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var downloads: TrackDownloadStore
    @State private var section: Section = .albums
    @State private var sortOrder: SortOrder = .recentlyAdded

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]
    let onOpenServerSettings: () -> Void

    init(onOpenServerSettings: @escaping () -> Void = {}) {
        self.onOpenServerSettings = onOpenServerSettings
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                if catalog.isLoading && catalog.albums.isEmpty {
                    ProgressView("Loading your library…")
                        .frame(maxHeight: .infinity)
                } else if let error = catalog.errorMessage, catalog.albums.isEmpty {
                    unavailableContent(error)
                        .frame(maxHeight: .infinity)
                } else if catalog.albums.isEmpty {
                    ContentUnavailableView(
                        "Library Empty",
                        systemImage: "square.stack",
                        description: Text("The connected server has no albums.")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    libraryContent
                }
            }
        }
        .background(Color.black)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: Album.self) { AlbumView(album: $0) }
        .navigationDestination(for: Artist.self) { artist in
            ArtistView(
                artist: artist,
                albums: catalog.albums.filter { $0.artist.id == artist.id }
            )
        }
        .navigationDestination(for: Playlist.self) { PlaylistView(playlist: $0) }
    }

    private var header: some View {
        Text("Library")
            .font(.largeTitle.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 16)
    }

    private var libraryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                controls

                if section == .artists {
                    artistList
                } else if section == .playlists {
                    playlistList
                } else if visibleAlbums.isEmpty {
                    ContentUnavailableView(
                        "No Downloaded Albums",
                        systemImage: "arrow.down.circle",
                        description: Text("Download an album to make it available offline.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                        ForEach(visibleAlbums) { album in
                            NavigationLink(value: album) {
                                AlbumCard(
                                    album: album,
                                    isDownloaded: isDownloaded(album)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .refreshable { await catalog.reload() }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Section.allCases) { item in
                        Button {
                            section = item
                        } label: {
                            Text(item.rawValue)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 16)
                                .frame(height: 36)
                                .background(
                                    section == item ? Color.white : Color.white.opacity(0.12),
                                    in: Capsule()
                                )
                                .foregroundStyle(section == item ? .black : .white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollIndicators(.hidden)

            HStack {
                Text(section == .artists ? "\(artists.count) artists" : section == .playlists ? "\(catalog.playlists.count) playlists" : "\(visibleAlbums.count) albums")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                if section != .artists && section != .playlists {
                    Menu {
                        Picker("Sort albums", selection: $sortOrder) {
                            ForEach(SortOrder.allCases) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityLabel("Sort albums")
                }
            }
        }
    }

    private var visibleAlbums: [Album] {
        let filtered = catalog.albums.filter { album in
            section != .downloaded || isDownloaded(album)
        }

        return filtered.sorted { first, second in
            switch sortOrder {
            case .recentlyAdded:
                if first.year != second.year {
                    return first.year > second.year
                }
                return first.title.localizedStandardCompare(second.title) == .orderedAscending
            case .album:
                return first.title.localizedStandardCompare(second.title) == .orderedAscending
            case .artist:
                let artistOrder = first.artist.name.localizedStandardCompare(second.artist.name)
                if artistOrder != .orderedSame {
                    return artistOrder == .orderedAscending
                }
                return first.title.localizedStandardCompare(second.title) == .orderedAscending
            }
        }
    }

    private var artists: [(artist: Artist, albums: [Album])] {
        let groups = Dictionary(grouping: catalog.albums, by: \.artist)
        return groups.map { (artist: $0.key, albums: $0.value) }
            .sorted {
                $0.artist.name.localizedStandardCompare($1.artist.name) == .orderedAscending
            }
    }

    private var artistList: some View {
        LazyVStack(spacing: 0) {
            ForEach(artists, id: \.artist.id) { item in
                NavigationLink(value: item.artist) {
                    HStack(spacing: 14) {
                        ArtworkView(
                            style: item.albums[0].artwork,
                            cornerRadius: 12,
                            showsShadow: false
                        )
                        .frame(width: 64, height: 64)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.artist.name)
                                .font(.headline)
                                .lineLimit(1)
                            Text("\(item.albums.count) \(item.albums.count == 1 ? "album" : "albums")")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.leading, 78)
            }
        }
    }

    private var playlistList: some View {
        LazyVStack(spacing: 0) {
            ForEach(catalog.playlists) { playlist in
                NavigationLink(value: playlist) {
                    HStack(spacing: 14) {
                        ArtworkView(style: playlist.artwork, cornerRadius: 12, showsShadow: false)
                            .frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(playlist.name).font(.headline).lineLimit(1)
                            Text("\(playlist.tracks.count) tracks").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 78)
            }
        }
    }

    private func isDownloaded(_ album: Album) -> Bool {
        !album.tracks.isEmpty
            && album.tracks.allSatisfy { downloads.state(for: $0) == .downloaded }
    }

    private func unavailableContent(_ error: String) -> some View {
        ContentUnavailableView {
            Label("Server Unavailable", systemImage: "wifi.exclamationmark")
        } description: {
            Text(error)
        } actions: {
            Button("Server Settings", systemImage: "server.rack") {
                onOpenServerSettings()
            }
            .buttonStyle(.borderedProminent)

            Button("Try Again") {
                Task { await catalog.reload() }
            }
            .buttonStyle(.bordered)
        }
    }
}

/// Albums grouped under one artist, reached from the Library artist filter.
private struct ArtistView: View {
    let artist: Artist
    let albums: [Album]

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(albums) { album in
                    NavigationLink(value: album) {
                        AlbumCard(album: album, isDownloaded: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(Color.black)
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.large)
    }
}

/// Compact album grid card with an unobtrusive offline-availability badge.
struct AlbumCard: View {
    let album: Album
    let isDownloaded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkView(style: album.artwork, cornerRadius: 16)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    if isDownloaded {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.65))
                            .padding(8)
                    }
                }

            Text(album.title)
                .font(.headline)
                .lineLimit(1)
            Text(album.artist.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
