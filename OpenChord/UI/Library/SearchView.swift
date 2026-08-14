import SwiftUI

/// Dedicated catalog search presented by the system search tab.
struct SearchView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var downloads: TrackDownloadStore
    @State private var query = ""

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        Group {
            if matchingAlbums.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                        ForEach(matchingAlbums) { album in
                            NavigationLink(value: album) {
                                AlbumCard(
                                    album: album,
                                    isDownloaded: isDownloaded(album)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("Search")
        .navigationDestination(for: Album.self) { AlbumView(album: $0) }
        .searchable(text: $query, prompt: "Albums or artists")
    }

    private var matchingAlbums: [Album] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return catalog.albums
            .filter { album in
                normalizedQuery.isEmpty
                    || album.title.localizedCaseInsensitiveContains(normalizedQuery)
                    || album.artist.name.localizedCaseInsensitiveContains(normalizedQuery)
            }
            .sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    private func isDownloaded(_ album: Album) -> Bool {
        !album.tracks.isEmpty
            && album.tracks.allSatisfy { downloads.state(for: $0) == .downloaded }
    }
}
