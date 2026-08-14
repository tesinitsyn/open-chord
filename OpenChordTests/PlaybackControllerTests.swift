import Testing
import UIKit
@testable import OpenChord

@Suite("Playback state", .serialized)
@MainActor
struct PlaybackControllerTests {
    @Test("Play selects a track and starts playback")
    func playSelectsTrack() {
        let engine = ManualPlaybackEngine()
        let track = makeTrack()
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let controller = PlaybackController(
            engine: engine,
            nowPlaying: NowPlayingManagerRecorder(),
            defaults: defaults
        )

        controller.play(track: track, in: [track])

        #expect(engine.loadedTrack == track)
        #expect(controller.currentTrack == track)
        #expect(controller.queue == [track])
        #expect(controller.isPlaying)
        #expect(controller.elapsed == 0)
        #expect(controller.lastPlayedTrackID == track.id)
        #expect(defaults.string(forKey: PlaybackController.lastPlayedTrackIDKey) == track.id.uuidString)
    }

    @Test("Last played track survives controller recreation")
    func lastPlayedTrackSurvivesRecreation() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let track = makeTrack()
        let first = PlaybackController(
            engine: ManualPlaybackEngine(),
            nowPlaying: NowPlayingManagerRecorder(),
            defaults: defaults
        )
        first.play(track: track, in: [track])

        let restored = PlaybackController(
            engine: ManualPlaybackEngine(),
            nowPlaying: NowPlayingManagerRecorder(),
            defaults: defaults
        )

        #expect(restored.currentTrack == nil)
        #expect(restored.lastPlayedTrackID == track.id)
    }

    @Test("Engine state drives the public playback state")
    func engineDrivesPlaybackState() {
        let engine = ManualPlaybackEngine()
        let track = makeTrack(duration: 10)
        let nowPlaying = NowPlayingManagerRecorder()
        let controller = PlaybackController(engine: engine, nowPlaying: nowPlaying)
        controller.play(track: track, in: [track])

        engine.send(elapsed: 1, isPlaying: true)

        #expect(controller.elapsed == 1)
        #expect(controller.progress == 0.1)
    }

    @Test("Seek clamps values to the playable range")
    func seekClampsToTrackDuration() {
        let track = makeTrack(duration: 10)
        let controller = PlaybackController(
            engine: ManualPlaybackEngine(),
            nowPlaying: NowPlayingManagerRecorder()
        )
        controller.play(track: track, in: [track])

        controller.seek(to: -4)
        #expect(controller.elapsed == 0)

        controller.seek(to: 15)
        #expect(controller.elapsed == 10)
    }

    @Test("Next stops at the end when repeat is off")
    func nextTrackStopsAtQueueEnd() {
        let first = makeTrack(title: "First")
        let second = makeTrack(title: "Second")
        let controller = PlaybackController(
            engine: ManualPlaybackEngine(),
            nowPlaying: NowPlayingManagerRecorder()
        )
        controller.play(track: second, in: [first, second])

        controller.playNext()

        #expect(controller.currentTrack == second)
    }

    @Test("Repeat all wraps around the queue")
    func repeatAllWrapsQueue() {
        let first = makeTrack(title: "First")
        let second = makeTrack(title: "Second")
        let controller = PlaybackController(
            engine: ManualPlaybackEngine(),
            nowPlaying: NowPlayingManagerRecorder()
        )
        controller.play(track: second, in: [first, second])
        controller.cycleRepeatMode()

        controller.playNext()

        #expect(controller.currentTrack == first)
    }

    @Test("Repeat one prepares the current track again")
    func repeatOnePreparesCurrentTrack() {
        let engine = ManualPlaybackEngine()
        let track = makeTrack()
        let controller = PlaybackController(engine: engine, nowPlaying: NowPlayingManagerRecorder())
        controller.play(track: track, in: [track])
        controller.cycleRepeatMode()
        controller.cycleRepeatMode()

        #expect(controller.repeatMode == .one)
        #expect(engine.preparedTrack == track)
    }

    @Test("Queue supports play next, append, removal and reordering")
    func editsUpcomingQueue() {
        let first = makeTrack(title: "First")
        let second = makeTrack(title: "Second")
        let third = makeTrack(title: "Third")
        let fourth = makeTrack(title: "Fourth")
        let controller = PlaybackController(
            engine: ManualPlaybackEngine(),
            nowPlaying: NowPlayingManagerRecorder()
        )
        controller.play(track: first, in: [first, second])

        controller.addToQueue(third)
        controller.playNext(fourth)
        #expect(controller.upcomingTracks == [fourth, second, third])

        controller.moveUpcomingTracks(from: [2], to: 0)
        #expect(controller.upcomingTracks == [third, fourth, second])

        controller.removeUpcomingTracks(at: [1])
        #expect(controller.upcomingTracks == [third, second])
    }

    @Test("Disabling shuffle restores the source order")
    func disablingShuffleRestoresOrder() {
        let first = makeTrack(title: "First")
        let second = makeTrack(title: "Second")
        let third = makeTrack(title: "Third")
        let controller = PlaybackController(
            engine: ManualPlaybackEngine(),
            nowPlaying: NowPlayingManagerRecorder()
        )
        controller.play(track: first, in: [first, second, third])
        controller.toggleShuffle()

        controller.toggleShuffle()

        #expect(!controller.isShuffleEnabled)
        #expect(controller.queue == [first, second, third])
    }

    @Test("Previous restarts a track after four seconds")
    func previousRestartsCurrentTrack() {
        let first = makeTrack(title: "First")
        let second = makeTrack(title: "Second")
        let controller = PlaybackController(
            engine: ManualPlaybackEngine(),
            nowPlaying: NowPlayingManagerRecorder()
        )
        controller.play(track: second, in: [first, second])
        controller.seek(to: 5)

        controller.playPrevious()

        #expect(controller.currentTrack == second)
        #expect(controller.elapsed == 0)
    }

    @Test("Finished engine event advances the queue")
    func finishedEventAdvancesQueue() {
        let first = makeTrack(title: "First")
        let second = makeTrack(title: "Second")
        let engine = ManualPlaybackEngine()
        let controller = PlaybackController(engine: engine, nowPlaying: NowPlayingManagerRecorder())
        controller.play(track: first, in: [first, second])

        engine.finish()

        #expect(controller.currentTrack == second)
        #expect(engine.loadedTrack == second)
        #expect(controller.isPlaying)
    }

    @Test("Selecting a track publishes system Now Playing metadata")
    func selectingTrackPublishesNowPlayingMetadata() {
        let first = makeTrack(title: "First")
        let second = makeTrack(title: "Second")
        let nowPlaying = NowPlayingManagerRecorder()
        let controller = PlaybackController(
            engine: ManualPlaybackEngine(),
            nowPlaying: nowPlaying
        )

        controller.play(track: second, in: [first, second])

        #expect(nowPlaying.publishedTrack == second)
        #expect(nowPlaying.publishedQueueIndex == 1)
        #expect(nowPlaying.publishedQueueCount == 2)
    }

    @Test("System pause and play commands control the engine")
    func systemCommandsControlPlayback() throws {
        let engine = ManualPlaybackEngine()
        let nowPlaying = NowPlayingManagerRecorder()
        let controller = PlaybackController(engine: engine, nowPlaying: nowPlaying)
        let track = makeTrack()
        controller.play(track: track, in: [track])
        let handlers = try #require(nowPlaying.handlers)

        handlers.pause()
        #expect(!controller.isPlaying)
        #expect(nowPlaying.isPlaying == false)

        handlers.play()
        #expect(controller.isPlaying)
        #expect(nowPlaying.isPlaying == true)
    }

    @Test("System artwork handler supports MediaPlayer background callbacks")
    func artworkHandlerSupportsBackgroundCallbacks() async {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: 2, height: 2)))
        }
        let imageProvider = SystemNowPlayingManager.artworkImageProvider(for: image)

        let renderedSize = await Task.detached {
            imageProvider(CGSize(width: 1, height: 1)).size
        }.value

        #expect(renderedSize == image.size)
    }
}
