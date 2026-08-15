import AVFoundation
import Combine
import Foundation

/// Configures the process audio session for music playback.
@MainActor
protocol PlaybackAudioSession: AnyObject {
    /// Activates a session that continues producing audio in silent mode.
    func activate() throws
}

/// Production audio-session adapter backed by `AVAudioSession.sharedInstance()`.
@MainActor
final class SystemPlaybackAudioSession: PlaybackAudioSession {
    private let session: AVAudioSession

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
    }

    func activate() throws {
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }
}

/// `PlaybackEngine` backed by Apple's system media pipeline.
///
/// This implementation intentionally owns all AVFoundation details so the
/// controller and SwiftUI views continue to depend only on playback semantics.
@MainActor
final class AVPlayerPlaybackEngine: PlaybackEngine {
    private let player: AVQueuePlayer
    private let bundle: Bundle
    private let audioSession: any PlaybackAudioSession
    private let stateSubject = CurrentValueSubject<PlaybackEngineState, Never>(.init())
    private let eventSubject = PassthroughSubject<PlaybackEngineEvent, Never>()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var preparedItem: AVPlayerItem?
    private var preparedDuration: TimeInterval = 0

    var state: AnyPublisher<PlaybackEngineState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    var events: AnyPublisher<PlaybackEngineEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }

    init(
        player: AVQueuePlayer = AVQueuePlayer(),
        bundle: Bundle = .main,
        audioSession: any PlaybackAudioSession = SystemPlaybackAudioSession()
    ) {
        self.player = player
        self.bundle = bundle
        self.audioSession = audioSession
        installTimeObserver()
        observeItemCompletion()
    }

    isolated deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    func load(_ track: Track, autoplay: Bool) {
        guard let url = track.audioSource.url(in: bundle) else {
            player.removeAllItems()
            preparedItem = nil
            stateSubject.send(.init())
            return
        }

        let item = AVPlayerItem(url: url)
        player.removeAllItems()
        player.insert(item, after: nil)
        preparedItem = nil
        stateSubject.send(
            PlaybackEngineState(
                elapsed: 0,
                duration: max(0, track.duration),
                isPlaying: autoplay
            )
        )

        if autoplay {
            try? audioSession.activate()
            player.play()
        }
    }

    func prepareNext(_ track: Track?) {
        if let preparedItem {
            player.remove(preparedItem)
            self.preparedItem = nil
        }
        guard
            let track,
            let url = track.audioSource.url(in: bundle),
            let currentItem = player.currentItem
        else { return }

        let item = AVPlayerItem(url: url)
        preparedItem = item
        preparedDuration = max(0, track.duration)
        player.insert(item, after: currentItem)
    }

    func play() {
        guard player.currentItem != nil else { return }
        try? audioSession.activate()
        player.play()
        updateState { $0.isPlaying = true }
    }

    func pause() {
        player.pause()
        updateState { $0.isPlaying = false }
    }

    func seek(to time: TimeInterval) {
        let clampedTime = min(max(0, time), stateSubject.value.duration)
        player.seek(
            to: CMTime(seconds: clampedTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        updateState { $0.elapsed = clampedTime }
    }

    private func installTimeObserver() {
        timeObserver = player.addPeriodicTimeObserver(
            // Lyrics need tighter timing than the progress slider. At 250 ms a correctly
            // timestamped line can still feel visibly late; 100 ms stays inexpensive while
            // keeping the highlight close to the audio boundary.
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let elapsed = time.seconds
                guard elapsed.isFinite else { return }
                self.updateState {
                    $0.elapsed = min(max(0, elapsed), $0.duration)
                    $0.isPlaying = self.player.rate != 0
                }
            }
        }
    }

    private func observeItemCompletion() {
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let isPlayerItem = notification.object is AVPlayerItem
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard isPlayerItem else { return }
                self.updateState {
                    $0.elapsed = self.preparedItem == nil ? $0.duration : 0
                    $0.duration = self.preparedItem == nil ? $0.duration : self.preparedDuration
                    $0.isPlaying = self.player.rate != 0
                }
                self.preparedItem = nil
                self.eventSubject.send(.finished)
            }
        }
    }

    private func updateState(_ update: (inout PlaybackEngineState) -> Void) {
        var nextState = stateSubject.value
        update(&nextState)
        stateSubject.send(nextState)
    }
}
