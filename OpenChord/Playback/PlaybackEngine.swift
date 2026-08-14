import Combine
import Foundation

/// The observable state of a playback engine.
struct PlaybackEngineState: Equatable {
    var elapsed: TimeInterval = 0
    var duration: TimeInterval = 0
    var isPlaying = false
}

/// Events that represent transitions rather than durable playback state.
enum PlaybackEngineEvent: Equatable {
    case finished
}

@MainActor
/// The media-playing boundary used by ``PlaybackController``.
///
/// Implementations publish state rather than requiring the controller to poll,
/// which keeps the real AVPlayer engine and deterministic test engine
/// interchangeable.
protocol PlaybackEngine: AnyObject {
    var state: AnyPublisher<PlaybackEngineState, Never> { get }
    var events: AnyPublisher<PlaybackEngineEvent, Never> { get }

    /// Loads a track into the engine.
    ///
    /// - Parameters:
    ///   - track: The track whose audio source should be resolved.
    ///   - autoplay: Whether playback should begin after loading succeeds.
    func load(_ track: Track, autoplay: Bool)

    /// Preloads the item that should follow the current track. Production
    /// engines use this to avoid opening media only after playback has ended.
    func prepareNext(_ track: Track?)

    /// Resumes the loaded item when one is available.
    func play()

    /// Pauses the loaded item without changing its position.
    func pause()

    /// Moves playback to a time clamped to the loaded item's duration.
    ///
    /// - Parameter time: Requested offset in seconds.
    func seek(to time: TimeInterval)
}

@MainActor
/// A deterministic, clock-driven engine used by previews and tests.
///
/// The engine advances by one 250-millisecond step per clock tick and emits a
/// single completion event when it reaches the loaded track's duration.
final class SimulatedPlaybackEngine: PlaybackEngine {
    private let stateSubject = CurrentValueSubject<PlaybackEngineState, Never>(.init())
    private let eventSubject = PassthroughSubject<PlaybackEngineEvent, Never>()
    private var clockSubscription: AnyCancellable?

    var state: AnyPublisher<PlaybackEngineState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    var events: AnyPublisher<PlaybackEngineEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }

    init(clock: any PlaybackClock = SystemPlaybackClock()) {
        clockSubscription = clock.ticks
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    func load(_ track: Track, autoplay: Bool) {
        let duration = max(0, track.duration)
        stateSubject.send(
            PlaybackEngineState(
                elapsed: 0,
                duration: duration,
                isPlaying: autoplay && duration > 0
            )
        )
    }

    func prepareNext(_: Track?) {}

    func play() {
        guard stateSubject.value.duration > 0 else { return }
        updateState { $0.isPlaying = true }
    }

    func pause() {
        updateState { $0.isPlaying = false }
    }

    func seek(to time: TimeInterval) {
        updateState { state in
            state.elapsed = min(max(0, time), state.duration)
        }
    }

    private func tick() {
        let currentState = stateSubject.value
        guard currentState.isPlaying, currentState.duration > 0 else { return }

        let nextElapsed = min(currentState.elapsed + 0.25, currentState.duration)
        if nextElapsed >= currentState.duration {
            stateSubject.send(
                PlaybackEngineState(
                    elapsed: currentState.duration,
                    duration: currentState.duration,
                    isPlaying: false
                )
            )
            eventSubject.send(.finished)
        } else {
            updateState { $0.elapsed = nextElapsed }
        }
    }

    private func updateState(_ update: (inout PlaybackEngineState) -> Void) {
        var nextState = stateSubject.value
        update(&nextState)
        stateSubject.send(nextState)
    }
}
