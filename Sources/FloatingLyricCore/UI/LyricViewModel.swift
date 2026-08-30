import Foundation
import SwiftUI

@MainActor
public final class LyricViewModel: ObservableObject {
    public enum Display: Equatable {
        case message(String)
        case synced(LyricsDocument, currentIndex: Int?)
        case plain(String)
    }

    @Published public var title: String = "FloatingLyric"
    @Published public var artist: String = ""
    @Published public var display: Display = .message("Set up Spotify to begin")
    @Published public var positionMs: Int = 0
    @Published public var durationMs: Int = 0
    @Published public var fontSize: Int = Defaults.fontSize
    @Published public var isOffline: Bool = false

    private var document: LyricsDocument?

    public init() {}

    public func apply(state: PlaybackState) {
        switch state {
        case .idle:
            title = "Nothing playing"
            artist = ""
            document = nil
            display = .message("Nothing playing")
            isOffline = false
        case .playing(let np), .paused(let np):
            title = np.track.title
            artist = np.track.artist
            durationMs = np.track.durationMs
            isOffline = false
        case .failed(let error):
            switch error {
            case .notConfigured, .notLoggedIn, .sessionExpired:
                document = nil
                title = "FloatingLyric"
                artist = ""
                display = .message(error.displayMessage)
                isOffline = false
            case .network:
                isOffline = true       // keep whatever lyrics are on screen
            case .rateLimited, .badResponse, .portUnavailable, .authCancelled:
                break                  // transient; leave the current display alone
            }
        }
    }

    public func apply(lyrics: LyricsResult) {
        switch lyrics {
        case .synced(let lines):
            let doc = LyricsDocument(lines: lines)
            document = doc
            display = .synced(doc, currentIndex: doc.index(atPositionMs: positionMs,
                                                           offsetMs: Defaults.syncOffsetMs))
        case .plain(let text):
            document = nil
            display = .plain(text)
        case .notFound:
            document = nil
            display = .message("No lyrics found")
        }
    }

    public func tick(positionMs newPosition: Int) {
        positionMs = newPosition
        guard let document else { return }
        let index = document.index(atPositionMs: newPosition, offsetMs: Defaults.syncOffsetMs)
        if case .synced(_, let current) = display, current == index { return }
        display = .synced(document, currentIndex: index)
    }
}
