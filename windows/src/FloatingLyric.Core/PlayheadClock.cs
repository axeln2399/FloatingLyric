namespace FloatingLyric.Core;

/// <summary>
/// Extrapolates the playback position between polls, so a 3-second poll can
/// drive a 10 Hz display. Pure: callers supply "now".
/// </summary>
public sealed class PlayheadClock
{
    public const int SeekThresholdMs = 1500;

    private int _anchorProgressMs;
    private double? _anchorTime;
    private bool _playing;

    public void Anchor(int progressMs, bool isPlaying, double now)
    {
        _anchorProgressMs = Math.Max(0, progressMs);
        _anchorTime = now;
        _playing = isPlaying;
    }

    public int PositionMs(double now)
    {
        if (_anchorTime is not { } anchorTime) return 0;
        if (!_playing) return _anchorProgressMs;
        var elapsedMs = (int)Math.Round((now - anchorTime) * 1000);
        return Math.Max(0, _anchorProgressMs + elapsedMs);
    }

    /// <summary>True when a fresh poll disagrees with the extrapolation by
    /// more than the threshold — that is a seek, not drift.</summary>
    public bool IsSeek(int polledProgressMs, double now) =>
        _anchorTime is not null &&
        Math.Abs(polledProgressMs - PositionMs(now)) > SeekThresholdMs;
}
