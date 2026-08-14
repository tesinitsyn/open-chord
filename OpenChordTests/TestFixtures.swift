import Combine
import Foundation
@testable import OpenChord

@MainActor
final class ManualPlaybackClock: PlaybackClock {
    private let subject = PassthroughSubject<Void, Never>()

    var ticks: AnyPublisher<Void, Never> {
        subject.eraseToAnyPublisher()
    }

    func advance(by tickCount: Int = 1) {
        for _ in 0..<tickCount {
            subject.send()
        }
    }
}

@MainActor
final class ManualPlaybackEngine: PlaybackEngine {
    private let stateSubject = CurrentValueSubject<PlaybackEngineState, Never>(.init())
    private let eventSubject = PassthroughSubject<PlaybackEngineEvent, Never>()

    private(set) var loadedTrack: Track?
    private(set) var preparedTrack: Track?

    var state: AnyPublisher<PlaybackEngineState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    var events: AnyPublisher<PlaybackEngineEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }

    func load(_ track: Track, autoplay: Bool) {
        loadedTrack = track
        stateSubject.send(.init(elapsed: 0, duration: track.duration, isPlaying: autoplay))
    }

    func prepareNext(_ track: Track?) {
        preparedTrack = track
    }

    func play() {
        send(elapsed: stateSubject.value.elapsed, isPlaying: true)
    }

    func pause() {
        send(elapsed: stateSubject.value.elapsed, isPlaying: false)
    }

    func seek(to time: TimeInterval) {
        send(elapsed: min(max(0, time), stateSubject.value.duration), isPlaying: stateSubject.value.isPlaying)
    }

    func send(elapsed: TimeInterval, isPlaying: Bool) {
        stateSubject.send(
            .init(
                elapsed: elapsed,
                duration: loadedTrack?.duration ?? 0,
                isPlaying: isPlaying
            )
        )
    }

    func finish() {
        if let preparedTrack {
            loadedTrack = preparedTrack
            self.preparedTrack = nil
            stateSubject.send(
                .init(elapsed: 0, duration: preparedTrack.duration, isPlaying: true)
            )
        }
        eventSubject.send(.finished)
    }
}

@MainActor
final class PlaybackEngineRecorder {
    private(set) var state = PlaybackEngineState()
    private(set) var events: [PlaybackEngineEvent] = []
    private var subscriptions = Set<AnyCancellable>()

    init(engine: any PlaybackEngine) {
        engine.state
            .sink { [weak self] in self?.state = $0 }
            .store(in: &subscriptions)

        engine.events
            .sink { [weak self] in self?.events.append($0) }
            .store(in: &subscriptions)
    }
}

@MainActor
final class NowPlayingManagerRecorder: NowPlayingManaging {
    private(set) var handlers: NowPlayingCommandHandlers?
    private(set) var publishedTrack: Track?
    private(set) var publishedQueueIndex: Int?
    private(set) var publishedQueueCount: Int?
    private(set) var elapsed: TimeInterval?
    private(set) var isPlaying: Bool?

    func install(_ handlers: NowPlayingCommandHandlers) {
        self.handlers = handlers
    }

    func publish(track: Track, queueIndex: Int, queueCount: Int) {
        publishedTrack = track
        publishedQueueIndex = queueIndex
        publishedQueueCount = queueCount
    }

    func update(elapsed: TimeInterval, isPlaying: Bool) {
        self.elapsed = elapsed
        self.isPlaying = isPlaying
    }
}

func makeTrack(
    title: String = "Test Track",
    duration: TimeInterval = 10,
    lyrics: [LyricLine] = []
) -> Track {
    Track(
        id: UUID(),
        title: title,
        artistName: "Test Artist",
        albumTitle: "Test Album",
        duration: duration,
        audioSource: .bundled(resource: "OpenChordDemo", fileExtension: "m4a"),
        artwork: ArtworkStyle(symbol: "music.note", colors: [.blue, .indigo]),
        lyrics: lyrics
    )
}
