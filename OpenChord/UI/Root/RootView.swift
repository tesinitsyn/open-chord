import SwiftUI

/// Root navigation shell coordinating the library, global sheets, and persistent mini-player.
struct RootView: View {
    private enum AppTab: Hashable {
        case home
        case library
        case settings
        case search
    }

    @Environment(PlaybackController.self) private var player
    @EnvironmentObject private var catalog: CatalogStore
    @State private var selectedTab: AppTab = .home

    @ViewBuilder
    var body: some View {
        @Bindable var player = player

        if #available(iOS 26.0, *) {
            modernTabShell
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory {
                    if let track = player.currentTrack {
                        AdaptiveMiniPlayer(track: track)
                    } else {
                        AdaptiveEmptyPlaybackAccessory()
                    }
                }
        } else if #available(iOS 18.0, *) {
            modernTabShell
                .safeAreaInset(edge: .bottom, spacing: 8) {
                    if let track = player.currentTrack {
                        LegacyMiniPlayer(track: track)
                            .padding(.horizontal, 10)
                    } else {
                        LegacyEmptyPlaybackAccessory()
                            .padding(.horizontal, 10)
                    }
                }
        } else {
            legacyTabShell
                .safeAreaInset(edge: .bottom, spacing: 8) {
                    if let track = player.currentTrack {
                        LegacyMiniPlayer(track: track)
                            .padding(.horizontal, 10)
                    } else {
                        LegacyEmptyPlaybackAccessory()
                            .padding(.horizontal, 10)
                    }
                }
        }
    }

    @available(iOS 18.0, *)
    private var modernTabShell: some View {
        @Bindable var player = player

        return TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                NavigationStack {
                    HomeView {
                        selectedTab = .library
                    }
                }
            }

            Tab("Library", systemImage: "square.stack.fill", value: AppTab.library) {
                NavigationStack {
                    LibraryView {
                        selectedTab = .settings
                    }
                }
            }

            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                NavigationStack {
                    SettingsView()
                }
            }

            Tab(value: AppTab.search, role: .search) {
                NavigationStack {
                    SearchView()
                }
            }
        }
        .sheet(isPresented: $player.isPlayerPresented) {
            PlayerView()
        }
        .tint(Color.primary)
        .task {
            await catalog.loadIfNeeded()
        }
    }

    private var legacyTabShell: some View {
        @Bindable var player = player

        return TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView {
                    selectedTab = .library
                }
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(AppTab.home)

            NavigationStack {
                LibraryView {
                    selectedTab = .settings
                }
            }
            .tabItem { Label("Library", systemImage: "square.stack.fill") }
            .tag(AppTab.library)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(AppTab.settings)

            NavigationStack {
                SearchView()
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(AppTab.search)
        }
        .sheet(isPresented: $player.isPlayerPresented) {
            PlayerView()
        }
        .tint(Color.primary)
        .task {
            await catalog.loadIfNeeded()
        }
    }
}

/// Stable accessory that follows the system's expanded or inline placement.
@available(iOS 26.0, *)
private struct AdaptiveEmptyPlaybackAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var accessoryPlacement

    var body: some View {
        EmptyPlaybackAccessoryContent(isCompact: accessoryPlacement == .inline)
    }
}

/// Stable fallback shown before the first track is selected.
private struct LegacyEmptyPlaybackAccessory: View {
    var body: some View {
        EmptyPlaybackAccessoryContent(isCompact: false)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
    }
}

/// Shared empty-playback presentation.
private struct EmptyPlaybackAccessoryContent: View {
    let isCompact: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(
                    width: isCompact ? 28 : 42,
                    height: isCompact ? 28 : 42
                )
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            Text("Nothing Playing")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, isCompact ? 3 : 6)
        .accessibilityElement(children: .combine)
    }
}

/// Playback summary that follows the system accessory's expanded or inline placement.
@available(iOS 26.0, *)
private struct AdaptiveMiniPlayer: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var accessoryPlacement
    let track: Track

    var body: some View {
        MiniPlayerContent(
            track: track,
            isCompact: accessoryPlacement == .inline,
            usesFallbackMaterial: false
        )
    }
}

/// Material-backed playback summary for systems without tab accessories.
private struct LegacyMiniPlayer: View {
    let track: Track

    var body: some View {
        MiniPlayerContent(track: track, isCompact: false, usesFallbackMaterial: true)
    }
}

/// Shared mini-player content independent of its system container.
private struct MiniPlayerContent: View {
    @Environment(PlaybackController.self) private var player
    let track: Track
    let isCompact: Bool
    let usesFallbackMaterial: Bool

    var body: some View {
        HStack(spacing: isCompact ? 8 : 12) {
            MiniPlayerArtwork(
                style: track.artwork,
                size: isCompact ? 24 : 44,
                cornerRadius: isCompact ? 5 : 9
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !isCompact {
                    Text(track.artistName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                player.togglePlayback()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 40, height: 40)
            }

            if !isCompact {
                Button {
                    player.playNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel("Next track")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, isCompact ? 3 : 6)
        .fallbackMiniPlayerGlass(isEnabled: usesFallbackMaterial)
        .contentShape(Rectangle())
        .onTapGesture { player.isPlayerPresented = true }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the full player")
    }
}

/// Fixed-size artwork that cannot inherit the large-card layout or shadow.
private struct MiniPlayerArtwork: View {
    let style: ArtworkStyle
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.quaternary)

            Image(systemName: style.symbol)
                .font(.system(size: size * 0.34, weight: .medium))
                .foregroundStyle(.secondary)

            if let remoteURL = style.remoteURL {
                AsyncImage(url: remoteURL) { phase in
                    if case let .success(image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}

private extension View {
    /// Adds a material container only on systems without TabView accessories.
    @ViewBuilder
    func fallbackMiniPlayerGlass(isEnabled: Bool) -> some View {
        if !isEnabled {
            self
        } else {
            background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
    }
}
