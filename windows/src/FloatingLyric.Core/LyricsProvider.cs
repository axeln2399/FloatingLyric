using System.Text.Json;
using System.Text.Json.Serialization;

namespace FloatingLyric.Core;

public sealed class LyricsProvider(IHttpClient http, ILyricsCache cache, Func<DateTime>? now = null)
{
    public static readonly TimeSpan NegativeTtl = TimeSpan.FromHours(24);

    public const string UserAgent =
        "FloatingLyric/1.0 (Windows lyrics overlay; contact via app repository)";

    /// <summary>How far a candidate's length may sit from the track's before
    /// it stops being the same recording. Widened in stages — see BestMatch.</summary>
    public const double CloseToleranceSeconds = 5.0;
    public const double LooseToleranceSeconds = 15.0;

    private const string Base = "https://lrclib.net";
    private readonly Func<DateTime> _now = now ?? (() => DateTime.UtcNow);

    public async Task<LyricsResult> LyricsAsync(TrackIdentity track)
    {
        if (cache.Read(track.Id, _now()) is { } cached) return cached;
        try
        {
            var result = await FetchAsync(track);
            cache.Write(result, track.Id, _now());
            return result;
        }
        catch
        {
            // Transient failure: report nothing found, but never cache it —
            // otherwise one flaky moment poisons a song for a day.
            return LyricsResult.None;
        }
    }

    private async Task<LyricsResult> FetchAsync(TrackIdentity track) =>
        await DirectLookupAsync(track) ?? await SearchLookupAsync(track);

    private async Task<LyricsResult?> DirectLookupAsync(TrackIdentity track)
    {
        var query = Query(new()
        {
            ["artist_name"] = track.Artist,
            ["track_name"] = track.Title,
            ["album_name"] = track.Album,
            ["duration"] = (track.DurationMs / 1000).ToString(),
        });
        var response = await http.SendAsync(Request($"{Base}/api/get?{query}"));
        if (response.Status is < 200 or >= 300) return null;

        var record = Deserialize<Record>(response.Body);
        return record?.AsResult();
    }

    private async Task<LyricsResult> SearchLookupAsync(TrackIdentity track)
    {
        var query = Query(new()
        {
            ["artist_name"] = track.Artist,
            ["track_name"] = track.Title,
        });
        var response = await http.SendAsync(Request($"{Base}/api/search?{query}"));
        if (response.Status is < 200 or >= 300) return LyricsResult.None;

        var records = Deserialize<List<Record>>(response.Body);
        if (records is null) return LyricsResult.None;

        return BestMatch(track, records)?.AsResult() ?? LyricsResult.None;
    }

    /// <summary>
    /// Picks the best of LRCLIB's search results, widening in stages.
    ///
    /// A remaster, a regional release and a single edit of one song routinely
    /// differ by tens of seconds, and LRCLIB stores several of each. Demanding
    /// a close match throws all of them away and shows the user nothing — when
    /// being seconds out is what the sync offset slider is for.
    /// </summary>
    public static Record? BestMatch(TrackIdentity track, IReadOnlyList<Record> records)
    {
        var wanted = track.DurationMs / 1000.0;
        var usable = records.Where(r => r.AsResult() is not LyricsResult.NotFound).ToList();
        if (usable.Count == 0) return null;

        List<Record> Within(double tolerance) => usable
            .Where(r => r.Duration is { } d && Math.Abs(d - wanted) <= tolerance)
            .ToList();

        // Last resort only: a search for one song can return another, so the
        // widest tier insists the names match. Records with no duration at all
        // reach the user only here.
        var sameSong = usable.Where(r => r.IsSameSong(track)).ToList();

        foreach (var tier in new[] { Within(CloseToleranceSeconds), Within(LooseToleranceSeconds), sameSong })
            if (tier.Count > 0) return Preferred(tier, wanted);

        return null;
    }

    /// <summary>Synced beats plain; then the closest duration wins.</summary>
    private static Record Preferred(List<Record> records, double wanted) => records
        .OrderByDescending(r => r.HasSynced)
        .ThenBy(r => r.DistanceFrom(wanted))
        .First();

    private static HttpRequestMessage Request(string url)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.Add("User-Agent", UserAgent);
        return request;
    }

    private static string Query(Dictionary<string, string> items) => string.Join("&",
        items.Select(kv => $"{Uri.EscapeDataString(kv.Key)}={Uri.EscapeDataString(kv.Value)}"));

    private static T? Deserialize<T>(byte[] body)
    {
        try { return JsonSerializer.Deserialize<T>(body); }
        catch (JsonException) { return default; }
    }

    public sealed record Record
    {
        [JsonPropertyName("duration")] public double? Duration { get; init; }
        [JsonPropertyName("syncedLyrics")] public string? SyncedLyrics { get; init; }
        [JsonPropertyName("plainLyrics")] public string? PlainLyrics { get; init; }
        [JsonPropertyName("artistName")] public string? ArtistName { get; init; }
        [JsonPropertyName("trackName")] public string? TrackName { get; init; }

        public LyricsResult AsResult()
        {
            if (!string.IsNullOrEmpty(SyncedLyrics))
            {
                var lines = LrcParser.Parse(SyncedLyrics);
                if (lines.Count > 0) return new LyricsResult.Synced(lines);
            }
            if (!string.IsNullOrEmpty(PlainLyrics)) return new LyricsResult.Plain(PlainLyrics);
            return LyricsResult.None;
        }

        public bool HasSynced => AsResult() is LyricsResult.Synced;

        /// <summary>No duration is infinitely far away, so it sorts last
        /// wherever anything better exists.</summary>
        public double DistanceFrom(double seconds) =>
            Duration is { } d ? Math.Abs(d - seconds) : double.MaxValue;

        public bool IsSameSong(TrackIdentity track) =>
            Normalized(ArtistName) == Normalized(track.Artist) &&
            Normalized(TrackName) == Normalized(track.Title);

        private static string Normalized(string? text) => (text ?? "")
            .Trim()
            .Normalize(System.Text.NormalizationForm.FormD)
            .Where(c => System.Globalization.CharUnicodeInfo.GetUnicodeCategory(c)
                        != System.Globalization.UnicodeCategory.NonSpacingMark)
            .Aggregate(new System.Text.StringBuilder(), (sb, c) => sb.Append(c))
            .ToString()
            .ToLowerInvariant();
    }
}
