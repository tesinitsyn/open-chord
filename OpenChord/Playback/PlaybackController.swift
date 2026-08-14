import Combine
import Foundation
import MediaPlayer
import Observation
import SwiftUI
import UIKit

/// Commands exposed by the system's Lock Screen and Control Center surfaces.
@MainActor
struct NowPlayingCommandHandlers {
    let play: () -> Void
    let pause: () -> Void
    let next: () -> Void
    let previous: () -> Void
    let seek: (TimeInterval) -> Void
}

/// Publishes playback metadata and connects system media commands to the app.
@MainActor
protocol NowPlayingManaging: AnyObject {
    func install(_ handlers: NowPlayingCommandHandlers)
    func publish(track: Track, queueIndex: Int, queueCount: Int)
    func update(elapsed: TimeInterval, isPlaying: Bool)
}

/// MediaPlayer-backed implementation used on physical devices.
@MainActor
final class SystemNowPlayingManager: NowPlayingManaging {
    private let infoCenter: MPNowPlayingInfoCenter
    private let commandCenter: MPRemoteCommandCenter
    private let session: URLSession
    private var commandTargets: [(MPRemoteCommand, Any)] = []
    private var artworkTask: Task<Void, Never>?
    private var publishedTrackID: UUID?

    init(
        infoCenter: MPNowPlayingInfoCenter = .default(),
        commandCenter: MPRemoteCommandCenter = .shared(),
        session: URLSession = .shared
    ) {
        self.infoCenter = infoCenter
        self.commandCenter = commandCenter
        self.session = session
    }

    isolated deinit {
        artworkTask?.cancel()
        for (command, target) in commandTargets {
            command.removeTarget(target)
        }
    }

    func install(_ handlers: NowPlayingCommandHandlers) {
        commandTargets.append(
            (
                commandCenter.playCommand,
                commandCenter.playCommand.addTarget { _ in
                    Task { @MainActor in handlers.play() }
                    return .success
                }
            )
        )
        commandTargets.append(
            (
                commandCenter.pauseCommand,
                commandCenter.pauseCommand.addTarget { _ in
                    Task { @MainActor in handlers.pause() }
                    return .success
                }
            )
        )
        commandTargets.append(
            (
                commandCenter.nextTrackCommand,
                commandCenter.nextTrackCommand.addTarget { _ in
                    Task { @MainActor in handlers.next() }
                    return .success
                }
            )
        )
        commandTargets.append(
            (
                commandCenter.previousTrackCommand,
                commandCenter.previousTrackCommand.addTarget { _ in
                    Task { @MainActor in handlers.previous() }
                    return .success
                }
            )
        )
        commandTargets.append(
            (
                commandCenter.changePlaybackPositionCommand,
                commandCenter.changePlaybackPositionCommand.addTarget { event in
                    guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                        return .commandFailed
                    }
                    Task { @MainActor in handlers.seek(positionEvent.positionTime) }
                    return .success
                }
            )
        )
    }

    func publish(track: Track, queueIndex: Int, queueCount: Int) {
        publishedTrackID = track.id
        artworkTask?.cancel()
        infoCenter.nowPlayingInfo = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artistName,
            MPMediaItemPropertyAlbumTitle: track.albumTitle,
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0,
            MPNowPlayingInfoPropertyPlaybackRate: 1,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: queueIndex,
            MPNowPlayingInfoPropertyPlaybackQueueCount: queueCount,
        ]
        loadArtwork(for: track)
    }

    func update(elapsed: TimeInterval, isPlaying: Bool) {
        guard var information = infoCenter.nowPlayingInfo else { return }
        information[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        information[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1 : 0
        infoCenter.nowPlayingInfo = information
    }

    private func loadArtwork(for track: Track) {
        guard let artworkURL = track.artwork.remoteURL else { return }
        artworkTask = Task { [weak self] in
            guard
                let self,
                let (data, response) = try? await session.data(from: artworkURL),
                !Task.isCancelled,
                let httpResponse = response as? HTTPURLResponse,
                (200..<300).contains(httpResponse.statusCode),
                let image = UIImage(data: data),
                publishedTrackID == track.id,
                var information = infoCenter.nowPlayingInfo
            else { return }

            information[MPMediaItemPropertyArtwork] = Self.makeArtwork(from: image)
            infoCenter.nowPlayingInfo = information
        }
    }

    /// Builds MediaPlayer's artwork callback outside the manager's main-actor
    /// isolation. MediaPlayer invokes this callback on an internal background
    /// queue, so an actor-inherited closure traps in Swift's runtime executor
    /// check on physical devices.
    nonisolated static func makeArtwork(from image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(
            boundsSize: image.size,
            requestHandler: artworkImageProvider(for: image)
        )
    }

    nonisolated static func artworkImageProvider(
        for image: UIImage
    ) -> @Sendable (CGSize) -> UIImage {
        { @Sendable _ in image }
    }
}

@MainActor
/// Coordinates the playback queue and exposes presentation-ready player state.
///
/// The controller owns queue semantics while the injected ``PlaybackEngine``
/// owns media playback. Keeping those responsibilities separate makes queue
/// behavior deterministic in tests. Observation tracks each property
/// independently so playback ticks do not invalidate unrelated catalog views.
@Observable
final class PlaybackController {
    enum RepeatMode: String, CaseIterable {
        case off
        case all
        case one

        var symbol: String { self == .one ? "repeat.1" : "repeat" }
    }

    static let lastPlayedTrackIDKey = "openchord.lastPlayedTrackID"

    private(set) var currentTrack: Track?
    private(set) var lastPlayedTrackID: UUID?
    private(set) var queue: [Track] = []
    private(set) var isPlaying = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var isShuffleEnabled = false
    private(set) var repeatMode: RepeatMode = .off
    var isPlayerPresented = false

    @ObservationIgnored
    private let engine: any PlaybackEngine
    @ObservationIgnored
    private let nowPlaying: any NowPlayingManaging
    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private var subscriptions = Set<AnyCancellable>()
    @ObservationIgnored
    private var originalQueue: [Track] = []

    init(
        engine: any PlaybackEngine = AVPlayerPlaybackEngine(),
        nowPlaying: any NowPlayingManaging = SystemNowPlayingManager(),
        defaults: UserDefaults = .standard
    ) {
        self.engine = engine
        self.nowPlaying = nowPlaying
        self.defaults = defaults
        lastPlayedTrackID = defaults.string(forKey: Self.lastPlayedTrackIDKey)
            .flatMap(UUID.init(uuidString:))

        engine.state
            .sink { [weak self] state in
                self?.apply(state)
            }
            .store(in: &subscriptions)

        engine.events
            .sink { [weak self] event in
                guard event == .finished else {
                    return
                }

                if Thread.isMainThread {
                    self?.advanceAfterCompletion()
                } else {
                    DispatchQueue.main.async { [weak self] in
                        self?.advanceAfterCompletion()
                    }
                }
            }
            .store(in: &subscriptions)

        nowPlaying.install(
            NowPlayingCommandHandlers(
                play: { [weak self] in self?.resume() },
                pause: { [weak self] in self?.pause() },
                next: { [weak self] in self?.playNext() },
                previous: { [weak self] in self?.playPrevious() },
                seek: { [weak self] time in self?.seek(to: time) }
            )
        )
    }

    /// Selects a track and establishes the queue used by next and previous.
    ///
    /// Selecting the current track resumes playback without reloading it.
    ///
    /// - Parameters:
    ///   - track: The track to play.
    ///   - tracks: The queue containing `track`.
    func play(track: Track, in tracks: [Track]) {
        if currentTrack?.id != track.id {
            currentTrack = track
            queue = tracks
            originalQueue = tracks
            isShuffleEnabled = false
            remember(track)
            publishNowPlaying()
            engine.load(track, autoplay: true)
            prepareUpcomingTrack()
        } else {
            resume()
        }
    }

    func playShuffled(_ tracks: [Track]) {
        let shuffled = tracks.shuffled()
        guard let first = shuffled.first else { return }
        currentTrack = first
        queue = shuffled
        originalQueue = tracks
        isShuffleEnabled = true
        remember(first)
        publishNowPlaying()
        engine.load(first, autoplay: true)
        prepareUpcomingTrack()
    }

    func togglePlayback() {
        guard currentTrack != nil else { return }
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func seek(to time: TimeInterval) {
        guard currentTrack != nil else { return }
        engine.seek(to: time)
        nowPlaying.update(elapsed: elapsed, isPlaying: isPlaying)
    }

    func playNext() {
        moveQueue(by: 1, wraps: repeatMode == .all)
    }

    func playPrevious() {
        // Match system music-player semantics: after meaningful progress,
        // previous restarts the current item instead of changing the queue.
        if elapsed > 4 {
            seek(to: 0)
        } else {
            moveQueue(by: -1, wraps: repeatMode == .all)
        }
    }

    func toggleShuffle() {
        guard let currentTrack, queue.count > 1 else { return }
        if isShuffleEnabled {
            queue = originalQueue
            if !queue.contains(where: { $0.id == currentTrack.id }) {
                queue.insert(currentTrack, at: 0)
            }
        } else {
            let upcoming = queue.filter { $0.id != currentTrack.id }.shuffled()
            queue = [currentTrack] + upcoming
        }
        isShuffleEnabled.toggle()
        publishNowPlaying()
        prepareUpcomingTrack()
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        prepareUpcomingTrack()
    }

    func playNext(_ track: Track) {
        guard let currentTrack else {
            play(track: track, in: [track])
            return
        }
        guard track.id != currentTrack.id else { return }
        queue.removeAll { $0.id == track.id }
        let index = queue.firstIndex { $0.id == currentTrack.id } ?? 0
        queue.insert(track, at: min(index + 1, queue.endIndex))
        appendToOriginalQueueIfNeeded(track)
        publishNowPlaying()
        prepareUpcomingTrack()
    }

    func addToQueue(_ track: Track) {
        guard currentTrack != nil else {
            play(track: track, in: [track])
            return
        }
        guard !queue.contains(where: { $0.id == track.id }) else { return }
        queue.append(track)
        appendToOriginalQueueIfNeeded(track)
        publishNowPlaying()
        prepareUpcomingTrack()
    }

    func playQueued(_ track: Track) {
        guard queue.contains(where: { $0.id == track.id }) else { return }
        currentTrack = track
        remember(track)
        publishNowPlaying()
        engine.load(track, autoplay: true)
        prepareUpcomingTrack()
    }

    func removeFromQueue(at offsets: IndexSet) {
        guard let currentTrack else { return }
        let removable = offsets.filter { queue[$0].id != currentTrack.id }
        let removedIDs = Set(removable.map { queue[$0].id })
        queue.remove(atOffsets: IndexSet(removable))
        originalQueue.removeAll { removedIDs.contains($0.id) }
        publishNowPlaying()
        prepareUpcomingTrack()
    }

    func moveQueueItems(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
        if !isShuffleEnabled { originalQueue = queue }
        publishNowPlaying()
        prepareUpcomingTrack()
    }

    var progress: Double {
        guard let duration = currentTrack?.duration, duration > 0 else { return 0 }
        return elapsed / duration
    }

    var upcomingTracks: [Track] {
        guard
            let currentTrack,
            let index = queue.firstIndex(where: { $0.id == currentTrack.id }),
            queue.indices.contains(index + 1)
        else { return [] }
        return Array(queue[(index + 1)...])
    }

    func removeUpcomingTracks(at offsets: IndexSet) {
        guard
            let currentTrack,
            let currentIndex = queue.firstIndex(where: { $0.id == currentTrack.id })
        else { return }
        removeFromQueue(at: IndexSet(offsets.map { currentIndex + 1 + $0 }))
    }

    func moveUpcomingTracks(from source: IndexSet, to destination: Int) {
        guard
            let currentTrack,
            let currentIndex = queue.firstIndex(where: { $0.id == currentTrack.id })
        else { return }
        var upcoming = upcomingTracks
        upcoming.move(fromOffsets: source, toOffset: destination)
        queue = Array(queue[...currentIndex]) + upcoming
        if !isShuffleEnabled { originalQueue = queue }
        publishNowPlaying()
        prepareUpcomingTrack()
    }

    private func moveQueue(by offset: Int, wraps: Bool) {
        guard
            let currentTrack,
            let currentIndex = queue.firstIndex(where: { $0.id == currentTrack.id }),
            !queue.isEmpty
        else { return }

        let proposedIndex = currentIndex + offset
        guard wraps || queue.indices.contains(proposedIndex) else { return }
        let newIndex = (proposedIndex + queue.count) % queue.count
        let nextTrack = queue[newIndex]
        self.currentTrack = nextTrack
        remember(nextTrack)
        publishNowPlaying()
        engine.load(nextTrack, autoplay: true)
        prepareUpcomingTrack()
    }

    private func advanceAfterCompletion() {
        guard let currentTrack else { return }
        if repeatMode == .one {
            remember(currentTrack)
            publishNowPlaying()
            prepareUpcomingTrack()
            return
        }
        guard let index = queue.firstIndex(where: { $0.id == currentTrack.id }) else { return }
        let nextIndex = index + 1
        if queue.indices.contains(nextIndex) {
            self.currentTrack = queue[nextIndex]
        } else if repeatMode == .all, let first = queue.first {
            self.currentTrack = first
        } else {
            engine.prepareNext(nil)
            return
        }
        guard let nextTrack = self.currentTrack else { return }
        remember(nextTrack)
        publishNowPlaying()
        prepareUpcomingTrack()
    }

    private func prepareUpcomingTrack() {
        guard let currentTrack else {
            engine.prepareNext(nil)
            return
        }
        if repeatMode == .one {
            engine.prepareNext(currentTrack)
            return
        }
        guard let index = queue.firstIndex(where: { $0.id == currentTrack.id }) else {
            engine.prepareNext(nil)
            return
        }
        if queue.indices.contains(index + 1) {
            engine.prepareNext(queue[index + 1])
        } else {
            engine.prepareNext(repeatMode == .all ? queue.first : nil)
        }
    }

    private func appendToOriginalQueueIfNeeded(_ track: Track) {
        if !originalQueue.contains(where: { $0.id == track.id }) { originalQueue.append(track) }
    }

    private func resume() {
        guard currentTrack != nil else { return }
        engine.play()
        nowPlaying.update(elapsed: elapsed, isPlaying: true)
    }

    private func pause() {
        guard currentTrack != nil else { return }
        engine.pause()
        nowPlaying.update(elapsed: elapsed, isPlaying: false)
    }

    private func publishNowPlaying() {
        guard
            let currentTrack,
            let queueIndex = queue.firstIndex(where: { $0.id == currentTrack.id })
        else { return }
        nowPlaying.publish(track: currentTrack, queueIndex: queueIndex, queueCount: queue.count)
    }

    private func remember(_ track: Track) {
        lastPlayedTrackID = track.id
        defaults.set(track.id.uuidString, forKey: Self.lastPlayedTrackIDKey)
    }

    private func apply(_ state: PlaybackEngineState) {
        elapsed = state.elapsed
        isPlaying = state.isPlaying
    }
}
