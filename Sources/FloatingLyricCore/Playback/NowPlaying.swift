import Foundation

public struct NowPlaying: Equatable, Sendable {
    public let track: TrackIdentity
    public let progressMs: Int
    public let isPlaying: Bool
    public let albumArtURL: URL?

    public init(track: TrackIdentity, progressMs: Int, isPlaying: Bool, albumArtURL: URL?) {
        self.track = track
        self.progressMs = progressMs
        self.isPlaying = isPlaying
        self.albumArtURL = albumArtURL
    }
}

public enum PlaybackState: Equatable, Sendable {
    case idle
    case playing(NowPlaying)
    case paused(NowPlaying)
    case failed(AppError)

    public var nowPlaying: NowPlaying? {
        switch self {
        case .playing(let np), .paused(let np): return np
        case .idle, .failed: return nil
        }
    }
}
