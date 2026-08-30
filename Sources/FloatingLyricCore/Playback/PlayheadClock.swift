import Foundation

/// Extrapolates the playback position between polls. Pure: callers supply `now`.
public final class PlayheadClock: @unchecked Sendable {
    public static let seekThresholdMs = 1500

    private var anchorProgressMs: Int = 0
    private var anchorTime: TimeInterval?
    private var playing = false

    public init() {}

    public func anchor(progressMs: Int, isPlaying: Bool, now: TimeInterval) {
        anchorProgressMs = max(0, progressMs)
        anchorTime = now
        playing = isPlaying
    }

    public func positionMs(now: TimeInterval) -> Int {
        guard let anchorTime else { return 0 }
        guard playing else { return anchorProgressMs }
        let elapsedMs = Int(((now - anchorTime) * 1000).rounded())
        return max(0, anchorProgressMs + elapsedMs)
    }

    /// True when a freshly polled progress differs from the extrapolated
    /// position by more than `seekThresholdMs`.
    public func isSeek(polledProgressMs: Int, now: TimeInterval) -> Bool {
        guard anchorTime != nil else { return false }
        return abs(polledProgressMs - positionMs(now: now)) > Self.seekThresholdMs
    }
}
