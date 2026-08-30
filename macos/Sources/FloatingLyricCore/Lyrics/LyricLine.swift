import Foundation

public struct LyricLine: Equatable, Codable, Sendable {
    public let timeMs: Int
    public let text: String

    public init(timeMs: Int, text: String) {
        self.timeMs = timeMs
        self.text = text
    }
}

public struct TrackIdentity: Equatable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String
    public let durationMs: Int

    public init(id: String, title: String, artist: String, album: String, durationMs: Int) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.durationMs = durationMs
    }
}

public enum LyricsResult: Equatable, Sendable {
    case synced([LyricLine])
    case plain(String)
    case notFound
}
