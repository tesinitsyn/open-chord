import Foundation

/// An artist identity shared by catalog albums.
struct Artist: Identifiable, Hashable {
    let id: UUID
    let name: String
}

/// An album and its playback-ordered tracks.
struct Album: Identifiable, Hashable {
    let id: UUID
    let title: String
    let artist: Artist
    let year: Int
    let artwork: ArtworkStyle
    let tracks: [Track]

    var durationText: String {
        let seconds = tracks.reduce(0) { $0 + $1.duration }
        // The UI intentionally presents whole listening minutes.
        let wholeMinutes = Int(seconds) / 60
        return "\(tracks.count) tracks · \(wholeMinutes) min"
    }
}

/// User-curated ordered collection returned by the OpenChord server.
struct Playlist: Identifiable, Hashable {
    let id: UUID
    let name: String
    let description: String
    let createdAt: Date
    let updatedAt: Date
    let tracks: [Track]
    private let customArtwork: ArtworkStyle?

    init(
        id: UUID,
        name: String,
        description: String = "",
        createdAt: Date,
        updatedAt: Date,
        tracks: [Track],
        artwork: ArtworkStyle? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tracks = tracks
        self.customArtwork = artwork
    }

    var artwork: ArtworkStyle {
        customArtwork
            ?? tracks.first?.artwork
            ?? ArtworkStyle(symbol: "music.note.list", colors: [.indigo, .violet])
    }

    var durationText: String {
        let minutes = Int(tracks.reduce(0) { $0 + $1.duration }) / 60
        return "\(tracks.count) tracks · \(minutes) min"
    }
}

/// User-entered values and optional JPEG artwork for a new playlist.
struct PlaylistCreation: Sendable {
    let name: String
    let description: String
    let artworkData: Data?
}

/// A playable catalog item with optional synchronized lyrics.
struct Track: Identifiable, Hashable {
    let id: UUID
    let title: String
    let artistName: String
    let albumTitle: String
    let duration: TimeInterval
    let audioSource: AudioSource
    let artwork: ArtworkStyle
    let lyrics: [LyricLine]

    /// Returns the track with a different media location.
    ///
    /// - Parameter audioSource: The source the playback engine should resolve.
    /// - Returns: A copy preserving the track's catalog identity and metadata.
    func using(audioSource: AudioSource) -> Track {
        Track(
            id: id,
            title: title,
            artistName: artistName,
            albumTitle: albumTitle,
            duration: duration,
            audioSource: audioSource,
            artwork: artwork,
            lyrics: lyrics
        )
    }

    /// Returns a metadata-equivalent track rendered with catalog artwork.
    func using(artwork: ArtworkStyle) -> Track {
        Track(
            id: id,
            title: title,
            artistName: artistName,
            albumTitle: albumTitle,
            duration: duration,
            audioSource: audioSource,
            artwork: artwork,
            lyrics: lyrics
        )
    }
}

/// A media location understood by a playback engine.
enum AudioSource: Hashable {
    case bundled(resource: String, fileExtension: String)
    case remote(URL)

    /// Resolves the media location to a URL.
    ///
    /// - Parameter bundle: The bundle used to resolve bundled resources.
    /// - Returns: The source URL, or `nil` when a bundled resource is absent.
    func url(in bundle: Bundle = .main) -> URL? {
        switch self {
        case let .bundled(resource, fileExtension):
            bundle.url(forResource: resource, withExtension: fileExtension)
        case let .remote(url):
            url
        }
    }
}

/// A synchronized lyric segment.
///
/// `startTime` is inclusive and `endTime` is exclusive. Both values are
/// measured in seconds from the beginning of the track.
struct LyricLine: Identifiable, Hashable {
    let id: UUID
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}

/// Remote artwork with the deterministic fallback rendered while unavailable.
struct ArtworkStyle: Hashable {
    let symbol: String
    let colors: [ArtworkColor]
    let remoteURL: URL?

    init(symbol: String, colors: [ArtworkColor], remoteURL: URL? = nil) {
        self.symbol = symbol
        self.colors = colors
        self.remoteURL = remoteURL
    }
}

/// Semantic colors available to deterministic artwork placeholders.
enum ArtworkColor: String, Hashable {
    case violet, indigo, blue, cyan, mint, orange, pink, red

    var colorName: String { rawValue }
}
