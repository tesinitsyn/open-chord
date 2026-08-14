import AVFoundation
import Testing
@testable import OpenChord

@Suite("AVPlayer playback engine", .serialized)
@MainActor
struct AVPlayerPlaybackEngineTests {
    @Test("Bundled demo media resolves from the application bundle")
    func bundledDemoMediaResolves() {
        let source = AudioSource.bundled(resource: "OpenChordDemo", fileExtension: "m4a")

        #expect(source.url() != nil)
    }

    @Test("Loading media creates a player item and publishes initial state")
    func loadingMediaCreatesPlayerItem() {
        let player = AVQueuePlayer()
        let engine = AVPlayerPlaybackEngine(player: player)
        let recorder = PlaybackEngineRecorder(engine: engine)

        engine.load(makeTrack(duration: 96), autoplay: false)

        #expect(player.currentItem != nil)
        #expect(recorder.state == .init(elapsed: 0, duration: 96, isPlaying: false))
    }

    @Test("Autoplay activates a playback audio session")
    func autoplayActivatesPlaybackAudioSession() {
        let audioSession = PlaybackAudioSessionRecorder()
        let engine = AVPlayerPlaybackEngine(audioSession: audioSession)

        engine.load(makeTrack(duration: 96), autoplay: true)

        #expect(audioSession.activationCount == 1)
    }

    @Test("Resuming playback reactivates the audio session")
    func resumingReactivatesPlaybackAudioSession() {
        let audioSession = PlaybackAudioSessionRecorder()
        let engine = AVPlayerPlaybackEngine(audioSession: audioSession)
        engine.load(makeTrack(duration: 96), autoplay: false)

        engine.play()

        #expect(audioSession.activationCount == 1)
    }

    @Test("Seeking updates engine state immediately")
    func seekingUpdatesState() {
        let engine = AVPlayerPlaybackEngine()
        let recorder = PlaybackEngineRecorder(engine: engine)
        engine.load(makeTrack(duration: 96), autoplay: false)

        engine.seek(to: 24)

        #expect(recorder.state.elapsed == 24)
    }

    @Test("Preparing the next track queues it before current playback ends")
    func preparesNextTrackForGaplessPlayback() {
        let player = AVQueuePlayer()
        let engine = AVPlayerPlaybackEngine(player: player)
        engine.load(makeTrack(title: "First"), autoplay: false)

        engine.prepareNext(makeTrack(title: "Second"))

        #expect(player.items().count == 2)
    }

    @Test("Player item completion emits the engine finished event")
    func itemCompletionEmitsFinished() async throws {
        let player = AVQueuePlayer()
        let engine = AVPlayerPlaybackEngine(player: player)
        let recorder = PlaybackEngineRecorder(engine: engine)
        engine.load(makeTrack(duration: 96), autoplay: false)
        let item = try #require(player.currentItem)

        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: item)
        await Task.yield()

        #expect(recorder.state.elapsed == 96)
        #expect(!recorder.state.isPlaying)
        #expect(recorder.events == [.finished])
    }
}

@MainActor
private final class PlaybackAudioSessionRecorder: PlaybackAudioSession {
    private(set) var activationCount = 0

    func activate() throws {
        activationCount += 1
    }
}
