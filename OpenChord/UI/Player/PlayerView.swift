import SwiftUI

/// Full-screen player whose artwork region can reveal synchronized lyrics.
struct PlayerView: View {
    @Environment(PlaybackController.self) private var player
    @State private var page = PlayerPage.player

    /// Sections available within the full player presentation.
    private enum PlayerPage: Hashable {
        case player
        case lyrics
        case queue
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let track = player.currentTrack {
                    Group {
                        if page == .queue {
                            queueView(track)
                        } else {
                            nowPlaying(track)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    playerNavigation
                } else {
                    ContentUnavailableView("Nothing Playing", systemImage: "music.note")
                }
            }
            .background(Color(uiColor: .systemBackground))
        }
        .presentationDragIndicator(.visible)
    }

    private func nowPlaying(_ track: Track) -> some View {
        GeometryReader { proxy in
            let contentHeight = max(230, min(390, proxy.size.height * 0.52))

            VStack(spacing: 18) {
                Spacer(minLength: 8)

                ZStack {
                    ArtworkView(style: track.artwork)
                        .frame(maxWidth: 340)
                        .padding(.horizontal, 24)
                        .opacity(page == .lyrics ? 0 : 1)
                        .scaleEffect(page == .lyrics ? 0.96 : 1)

                    LyricsView(track: track, verticalPadding: 24)
                        .opacity(page == .lyrics ? 1 : 0)
                        .allowsHitTesting(page == .lyrics)
                }
                .frame(height: contentHeight)
                .clipped()

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

                HStack(spacing: 25) {
                    Button {
                        player.toggleShuffle()
                    } label: {
                        Image(systemName: "shuffle")
                            .foregroundStyle(player.isShuffleEnabled ? Color.primary : .secondary)
                            .frame(width: 40, height: 44)
                    }
                    .accessibilityLabel(player.isShuffleEnabled ? "Turn Shuffle Off" : "Turn Shuffle On")
                    .accessibilityValue(player.isShuffleEnabled ? "On" : "Off")

                    Button { player.playPrevious() } label: {
                        Image(systemName: "backward.fill").font(.title2).frame(width: 40, height: 44)
                    }
                    Button { player.togglePlayback() } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 70))
                    }
                    Button { player.playNext() } label: {
                        Image(systemName: "forward.fill").font(.title2).frame(width: 40, height: 44)
                    }
                    Button { player.cycleRepeatMode() } label: {
                        Image(systemName: player.repeatMode.symbol)
                            .foregroundStyle(player.repeatMode == .off ? .secondary : Color.primary)
                            .frame(width: 40, height: 44)
                    }
                    .accessibilityLabel(repeatTitle)
                    .accessibilityValue(player.repeatMode == .off ? "Off" : "On")
                }
                .buttonStyle(.plain)
                Spacer(minLength: 4)
            }
        }
    }

    private func queueView(_ track: Track) -> some View {
        List {
            Section {
                HStack(spacing: 10) {
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
                    EditButton()
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 64, minHeight: 44)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
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
                        Button {
                            player.playQueued(queuedTrack)
                        } label: {
                            queueRow(queuedTrack, isCurrent: false)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: player.removeUpcomingTracks)
                    .onMove(perform: player.moveUpcomingTracks)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemBackground))
    }

    private var playerNavigation: some View {
        HStack(spacing: 30) {
            playerModeButton(page: .lyrics, title: "Lyrics", symbol: "quote.bubble")
            playerModeButton(page: .player, title: "Now Playing", symbol: "waveform")
            playerModeButton(page: .queue, title: "Queue", symbol: "list.bullet")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    private func playerModeButton(page destination: PlayerPage, title: String, symbol: String) -> some View {
        let isSelected = page == destination
        return Button(title, systemImage: symbol) {
            setPage(destination)
        }
        .labelStyle(.iconOnly)
        .font(.headline)
        .frame(width: 48, height: 48)
        .foregroundStyle(isSelected ? Color.primary : .secondary)
        .background(
            isSelected ? Color.primary.opacity(0.1) : Color.clear,
            in: Circle()
        )
        .openChordGlass(cornerRadius: 24)
        .contentTransition(.symbolEffect(.replace))
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                .foregroundStyle(
                    isActive ? Color(uiColor: .systemBackground) : Color.primary
                )
                .background(
                    isActive ? Color.primary : Color.secondary.opacity(0.12),
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

    private func setPage(_ destination: PlayerPage) {
        let resolvedPage: PlayerPage = page == destination && destination != .player ? .player : destination

        // Queue and Now Playing are full-screen layouts. Crossfading them renders both trees for
        // several frames, exposing the queue through artwork and lyrics during the transition.
        // Switch those layouts atomically; only artwork-to-lyrics changes animate in place.
        if page == .queue || resolvedPage == .queue {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                page = resolvedPage
            }
        } else {
            withAnimation(.smooth(duration: 0.38)) {
                page = resolvedPage
            }
        }
    }
}
