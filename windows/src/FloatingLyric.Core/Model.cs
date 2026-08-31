namespace FloatingLyric.Core;

public sealed record LyricLine(int TimeMs, string Text);

public sealed record TrackIdentity(
    string Id, string Title, string Artist, string Album, int DurationMs);

/// <summary>What a lyrics lookup produced.</summary>
public abstract record LyricsResult
{
    public sealed record Synced(IReadOnlyList<LyricLine> Lines) : LyricsResult
    {
        public bool Equals(Synced? other) =>
            other is not null && Lines.SequenceEqual(other.Lines);
        public override int GetHashCode() => Lines.Count;
    }

    public sealed record Plain(string Text) : LyricsResult;
    public sealed record NotFound : LyricsResult;

    public static readonly LyricsResult None = new NotFound();
}

public sealed record NowPlaying(
    TrackIdentity Track, int ProgressMs, bool IsPlaying, string? AlbumArtUrl);

public abstract record PlaybackState
{
    public sealed record Idle : PlaybackState;
    public sealed record Playing(NowPlaying Np) : PlaybackState;
    public sealed record Paused(NowPlaying Np) : PlaybackState;
    public sealed record Failed(AppError Error) : PlaybackState;

    public NowPlaying? NowPlaying => this switch
    {
        Playing p => p.Np,
        Paused p => p.Np,
        _ => null,
    };
}
