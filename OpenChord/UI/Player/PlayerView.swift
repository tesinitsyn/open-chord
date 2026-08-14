import SwiftUI

/// Full-screen player presentation with now-playing and synchronized-lyrics pages.
struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlaybackController.self) private var player
    @State private var page = PlayerPage.player

    /// Sections available within the full player presentation.
    private enum PlayerPage: String, CaseIterable {
        case player = "Now Playing"
        case lyrics = "Lyrics"
    }

    var body: some View {
        NavigationStack {
            Group {
                if let track = player.currentTrack {
                    VStack(spacing: 18) {
                        Picker("Player section", selection: $page) {
                            ForEach(PlayerPage.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)

                        switch page {
                        case .player: nowPlaying(track)
                        case .lyrics: LyricsView(track: track)
                        }
                    }
                } else {
                    ContentUnavailableView("Nothing Playing", systemImage: "music.note")
                }
            }
            .background(Color(uiColor: .systemBackground))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "chevron.down") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func nowPlaying(_ track: Track) -> some View {
        VStack(spacing: 24) {
            Spacer()

            ArtworkView(style: track.artwork)
                .frame(maxWidth: 340)
                .padding(.horizontal, 24)

            VStack(spacing: 5) {
                Text(track.title).font(.title2.bold())
                Text(track.artistName).foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { player.elapsed },
                        set: { newValue in player.seek(to: newValue) }
                    ),
                    in: 0...max(1, track.duration)
                )
                .tint(Color.primary)

                HStack {
                    Text(player.elapsed.playbackTime)
                    Spacer()
                    Text("-" + max(0, track.duration - player.elapsed).playbackTime)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)

            HStack(spacing: 44) {
                Button {
                    player.playPrevious()
                } label: {
                    Image(systemName: "backward.fill").font(.title)
                }
                Button {
                    player.togglePlayback()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 70))
                }
                Button {
                    player.playNext()
                } label: {
                    Image(systemName: "forward.fill").font(.title)
                }
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }
}
