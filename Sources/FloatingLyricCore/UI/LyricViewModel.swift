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

    /// Transport state. `canControl` is false until there is a session, so the
    /// buttons are not offered before login.
    @Published public var isPlaying: Bool = false
    @Published public var canControl: Bool = false
    /// A transient complaint from a control action ("Premium required" …).
    @Published public var controlMessage: String?

    /// Everything but the lyrics — header, progress bar, transport buttons —
    /// is hidden while the window sits idle. See `ChromeVisibility`.
    @Published public var chromeVisible: Bool = true
    @Published public var showRomaji: Bool = Defaults.showRomaji

    /// Set by the view as the pointer enters and leaves the window.
    public private(set) var isHovering: Bool = false

    public var onPlayPause: (() -> Void)?
    public var onNext: (() -> Void)?
    public var onPrevious: (() -> Void)?

    private var document: LyricsDocument?
    /// The plain-text lyrics with a Latin reading under each non-Latin line,
    /// kept alongside the original so the romaji toggle is instant.
    private var plainText: String?
    private var plainWithRomaji: String?
    private var lastActivity: TimeInterval = Date().timeIntervalSinceReferenceDate
    private var messageExpiry: TimeInterval?

    public init() {}

    public func apply(state: PlaybackState) {
        switch state {
        case .idle:
            title = "Nothing playing"
            artist = ""
            document = nil
            display = .message("Nothing playing")
            isOffline = false
            setPlaying(false)
        case .playing(let np), .paused(let np):
            title = np.track.title
            artist = np.track.artist
            durationMs = np.track.durationMs
            isOffline = false
            setPlaying(np.isPlaying)
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
            case .rateLimited, .badResponse, .portUnavailable, .authCancelled,
                 .premiumRequired, .noActiveDevice, .controlScopeMissing:
                break                  // transient; leave the current display alone
            }
        }
    }

    public func apply(lyrics: LyricsResult) {
        switch lyrics {
        case .synced(let lines):
            let doc = LyricsDocument(lines: lines)
            document = doc
            plainText = nil
            plainWithRomaji = nil
            display = .synced(doc, currentIndex: doc.index(atPositionMs: positionMs,
                                                           offsetMs: Defaults.syncOffsetMs))
        case .plain(let text):
            document = nil
            plainText = text
            plainWithRomaji = Self.interleavedRomaji(text)
            display = .plain(plainDisplayText)
        case .notFound:
            document = nil
            plainText = nil
            plainWithRomaji = nil
            display = .message("No lyrics found")
        }
        noteActivity()
    }

    public func tick(positionMs newPosition: Int) {
        positionMs = newPosition
        guard let document else { return }
        let index = document.index(atPositionMs: newPosition, offsetMs: Defaults.syncOffsetMs)
        if case .synced(_, let current) = display, current == index { return }
        display = .synced(document, currentIndex: index)
    }

    // MARK: - Romaji

    /// Plain lyrics come as one blob, so the reading goes under each line here
    /// rather than in the view.
    private static func interleavedRomaji(_ text: String) -> String {
        text.components(separatedBy: .newlines).map { line -> String in
            guard let romaji = Transliteration.romanize(line) else { return line }
            return line + "\n" + romaji
        }.joined(separator: "\n")
    }

    private var plainDisplayText: String {
        (showRomaji ? plainWithRomaji : plainText) ?? plainText ?? ""
    }

    public func setShowRomaji(_ show: Bool) {
        guard showRomaji != show else { return }
        showRomaji = show
        if case .plain = display { display = .plain(plainDisplayText) }
        noteActivity()
    }

    // MARK: - Transport

    private func setPlaying(_ playing: Bool) {
        guard isPlaying != playing else { return }
        isPlaying = playing
        noteActivity()      // a track starting or stopping is worth surfacing
    }

    public func playPauseTapped() {
        noteActivity()
        // Flip straight away: Spotify needs a moment to report the new state
        // and a button that waits for the next poll feels broken.
        isPlaying.toggle()
        onPlayPause?()
    }

    public func nextTapped() {
        noteActivity()
        onNext?()
    }

    public func previousTapped() {
        noteActivity()
        onPrevious?()
    }

    /// Shows a control failure for a few seconds, then clears it.
    public func report(controlError: AppError, now: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        controlMessage = controlError.displayMessage
        // Matches the chrome timeout so the message never outlives the row
        // it is printed in.
        messageExpiry = now + ChromeVisibility.idleTimeout
        noteActivity(now: now)
    }

    // MARK: - Chrome visibility

    /// Called on every tick with the current pointer state, so only a change
    /// counts as activity — otherwise the idle countdown would never start.
    public func setHovering(_ hovering: Bool, now: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        if isHovering != hovering { lastActivity = now }
        isHovering = hovering
        refreshChrome(now: now)
    }

    public func noteActivity(now: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        lastActivity = now
        refreshChrome(now: now)
    }

    /// Called from the coordinator's tick; cheap and idempotent.
    public func refreshChrome(now: TimeInterval) {
        if let expiry = messageExpiry, now >= expiry {
            messageExpiry = nil
            controlMessage = nil
        }
        let visible = !Defaults.autoHideChrome
            || ChromeVisibility.isVisible(now: now, lastActivity: lastActivity,
                                          isHovering: isHovering)
        if chromeVisible != visible { chromeVisible = visible }
    }
}
