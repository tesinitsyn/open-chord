import SwiftUI

/// Full-screen player presentation with now-playing and synchronized-lyrics pages.
struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlaybackController.self) private var player
    @State private var path: [PlayerPage] = []

    /// Sections available within the full player presentation.
    private enum PlayerPage: Hashable {
        case lyrics
        case queue
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let track = player.currentTrack {
                    nowPlaying(track)
                        .toolbar { closeToolbar }
                } else {
                    ContentUnavailableView("Nothing Playing", systemImage: "music.note")
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationDestination(for: PlayerPage.self) { destination in
                if let track = player.currentTrack {
                    switch destination {
                    case .lyrics: lyricsView(track)
                    case .queue: queueView(track)
                    }
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

            HStack(spacing: 86) {
                Button {
                    path.append(.lyrics)
                } label: {
                    Image(systemName: "quote.bubble")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Show Lyrics")

                Button {
                    path.append(.queue)
                } label: {
                    Image(systemName: "list.bullet")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Show Queue")
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    private func lyricsView(_ track: Track) -> some View {
        LyricsView(track: track)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))
            .overlay(alignment: .bottom) {
                HStack(spacing: 18) {
                    Button("Now Playing", systemImage: "waveform") {
                        path.removeAll()
                    }
                    .labelStyle(.iconOnly)
                    .frame(width: 48, height: 48)
                    .openChordGlassButton()

                    Button("Show Queue", systemImage: "list.bullet") {
                        path.append(.queue)
                    }
                    .labelStyle(.iconOnly)
                    .frame(width: 48, height: 48)
                    .openChordGlassButton()
                }
                .padding(.bottom, 14)
            }
            .navigationTitle("Lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { closeToolbar }
    }

    private func queueView(_ track: Track) -> some View {
        List {
            Section {
                HStack(spacing: 12) {
                    playbackModeButton(
                        title: "Shuffle",
                        symbol: "shuffle",
                        isActive: player.isShuffleEnabled
                    ) {
                        player.toggleShuffle()
                    }
                    playbackModeButton(
                        title: repeatTitle,
                        symbol: player.repeatMode.symbol,
                        isActive: player.repeatMode != .off
                    ) {
                        player.cycleRepeatMode()
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section("Now Playing") {
                queueRow(track, isCurrent: true)
            }
            Section("Playing Next") {
                if player.upcomingTracks.isEmpty {
                    Text("The queue ends after this track.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(player.upcomingTracks) { queuedTrack in
                        queueRow(queuedTrack, isCurrent: false)
                    }
                    .onDelete(perform: player.removeUpcomingTracks)
                    .onMove(perform: player.moveUpcomingTracks)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Queue")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                EditButton()
                Button("Close", systemImage: "chevron.down") { dismiss() }
            }
        }
    }

    private func playbackModeButton(
        title: String,
        symbol: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .background(
                    isActive ? Color.accentColor : Color.secondary.opacity(0.12),
                    in: Capsule()
                )
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityValue(isActive ? "On" : "Off")
    }

    private func queueRow(_ track: Track, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            ArtworkView(style: track.artwork, cornerRadius: 6)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).lineLimit(1)
                Text(track.artistName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if isCurrent {
                Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var repeatTitle: String {
        switch player.repeatMode {
        case .off: "Repeat"
        case .all: "Repeat All"
        case .one: "Repeat One"
        }
    }

    @ToolbarContentBuilder
    private var closeToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Close", systemImage: "chevron.down") {
                dismiss()
            }
        }
    }
}
