import SwiftUI

/// Playlist detail with ordered queue playback.
struct PlaylistView: View {
    @Environment(PlaybackController.self) private var player
    @EnvironmentObject private var downloads: TrackDownloadStore
    let playlist: Playlist

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                ArtworkView(style: playlist.artwork).frame(maxWidth: 310).padding(.top, 12)
                VStack(spacing: 6) {
                    Text(playlist.name).font(.largeTitle.bold())
                    if !playlist.description.isEmpty { Text(playlist.description).foregroundStyle(.secondary) }
                    Text("\(playlist.tracks.count) tracks").font(.caption).foregroundStyle(.tertiary)
                }
                Button {
                    guard let first = playlist.tracks.first else { return }
                    player.play(track: downloads.playable(first), in: downloads.playable(playlist.tracks))
                } label: {
                    Label("Play", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                LazyVStack(spacing: 0) {
                    ForEach(Array(playlist.tracks.enumerated()), id: \.element.id) { index, track in
                        TrackRow(number: index + 1, track: track) {
                            player.play(track: downloads.playable(track), in: downloads.playable(playlist.tracks))
                        }
                    }
                }
            }
            .padding(.horizontal).padding(.bottom, 40)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
