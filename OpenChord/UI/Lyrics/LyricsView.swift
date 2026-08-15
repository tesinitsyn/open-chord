import SwiftUI

/// Synchronized lyrics view that follows playback and supports tap-to-seek.
///
/// Automatic scrolling occurs only when the active lyric changes, avoiding
/// timer-driven movement that would fight manual scrolling.
struct LyricsView: View {
    @Environment(PlaybackController.self) private var player
    @State private var followsPlayback = true
    let track: Track

    var body: some View {
        if track.lyrics.isEmpty {
            ContentUnavailableView(
                "No Lyrics Yet",
                systemImage: "quote.bubble",
                description: Text("This track has not been synchronized.")
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(track.lyrics) { line in
                            lyricButton(line)
                                .id(line.id)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 80)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { _ in followsPlayback = false }
                )
                .task(id: track.id) {
                    await Task.yield()
                    guard let activeID = activeLine?.id else { return }
                    proxy.scrollTo(activeID, anchor: .center)
                }
                .onChange(of: activeLine?.id) { _, newID in
                    guard followsPlayback, let newID else { return }
                    withAnimation(.smooth(duration: 0.28)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !followsPlayback {
                        Button("Follow Lyrics", systemImage: "quote.bubble.fill") {
                            followsPlayback = true
                            guard let activeID = activeLine?.id else { return }
                            withAnimation(.smooth) {
                                proxy.scrollTo(activeID, anchor: .center)
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(.regularMaterial, in: Capsule())
                        .padding(20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.smooth, value: followsPlayback)
            }
        }
    }

    private var activeLine: LyricLine? {
        track.lyrics.last(where: { $0.startTime <= player.elapsed })
    }

    private func lyricButton(_ line: LyricLine) -> some View {
        let isActive = activeLine?.id == line.id

        return Button {
            followsPlayback = true
            player.seek(to: line.startTime)
        } label: {
            Text(line.text)
                .font(isActive ? .title.bold() : .title2.bold())
                .fontDesign(.rounded)
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .opacity(isActive ? 1 : 0.62)
                .scaleEffect(isActive ? 1 : 0.97, anchor: .leading)
                .animation(.easeOut(duration: 0.12), value: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(line.text), \(line.startTime.playbackTime)")
        .accessibilityHint("Seeks playback to this lyric")
    }
}
