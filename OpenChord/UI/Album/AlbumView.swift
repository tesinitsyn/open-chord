import SwiftUI

/// Album detail screen with ordered tracks and offline-download actions.
struct AlbumView: View {
    @Environment(PlaybackController.self) private var player
    @EnvironmentObject private var downloads: TrackDownloadStore
    let album: Album

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ArtworkView(style: album.artwork)
                    .frame(maxWidth: 310)
                    .padding(.top, 12)

                VStack(spacing: 6) {
                    Text(album.title).font(.largeTitle.bold())
                    Text(album.artist.name).font(.title3).foregroundStyle(.secondary)
                    Text("\(album.year) · \(album.durationText)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Button {
                    guard let first = album.tracks.first else { return }
                    player.play(
                        track: downloads.playable(first),
                        in: downloads.playable(album.tracks)
                    )
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)

                Button {
                    Task { await downloads.download(album.tracks) }
                } label: {
                    Label(downloadAlbumTitle, systemImage: downloadAlbumSymbol)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(album.tracks.isEmpty || isDownloadingAlbum)

                LazyVStack(spacing: 0) {
                    ForEach(Array(album.tracks.enumerated()), id: \.element.id) { index, track in
                        TrackRow(number: index + 1, track: track) {
                            player.play(
                                track: downloads.playable(track),
                                in: downloads.playable(album.tracks)
                            )
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Download failed",
            isPresented: Binding(
                get: { downloads.errorMessage != nil },
                set: { if !$0 { downloads.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(downloads.errorMessage ?? "")
        }
    }

    private var isDownloadingAlbum: Bool {
        album.tracks.contains { downloads.state(for: $0) == .downloading }
    }

    private var isAlbumDownloaded: Bool {
        !album.tracks.isEmpty && album.tracks.allSatisfy { downloads.state(for: $0) == .downloaded }
    }

    private var downloadAlbumTitle: String {
        isAlbumDownloaded ? "Downloaded" : isDownloadingAlbum ? "Downloading…" : "Download Album"
    }

    private var downloadAlbumSymbol: String {
        isAlbumDownloaded ? "checkmark.circle.fill" : "arrow.down.circle"
    }
}

/// A track action row that reflects playback and download state.
struct TrackRow: View {
    @EnvironmentObject private var downloads: TrackDownloadStore
    let number: Int
    let track: Track
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: action) {
                HStack(spacing: 14) {
                    Text("\(number)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title).foregroundStyle(.primary)
                        Text(track.artistName).font(.caption).foregroundStyle(.secondary)
                    }

                    Spacer()
                    Text(track.duration.playbackTime)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            downloadButton
        }
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var downloadButton: some View {
        switch downloads.state(for: track) {
        case .downloading:
            ProgressView()
                .controlSize(.small)
                .frame(width: 36, height: 36)
                .accessibilityLabel("Downloading \(track.title)")
        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 36, height: 36)
                .accessibilityLabel("\(track.title) downloaded")
        case .idle, .failed:
            Button("Download \(track.title)", systemImage: "arrow.down.circle") {
                Task { await downloads.download(track) }
            }
            .labelStyle(.iconOnly)
            .frame(width: 36, height: 36)
        }
    }
}
