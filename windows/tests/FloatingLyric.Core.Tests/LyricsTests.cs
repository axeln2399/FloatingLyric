using FloatingLyric.Core;
using Xunit;

namespace FloatingLyric.Core.Tests;

public class LyricsProviderTests
{
    private static readonly TrackIdentity Track =
        new("t1", "Blinding Lights", "The Weeknd", "After Hours", 200_040);

    private static LyricsProvider.Record Record(
        double? duration, bool synced = true,
        string artist = "The Weeknd", string title = "Blinding Lights") => new()
    {
        Duration = duration,
        SyncedLyrics = synced ? "[00:10.00]Line" : null,
        PlainLyrics = "Line",
        ArtistName = artist,
        TrackName = title,
    };

    [Fact]
    public void AnExactDurationMatchWins() =>
        Assert.Equal(201, LyricsProvider.BestMatch(Track,
            [Record(186), Record(201), Record(260)])!.Duration);

    /// <summary>Nothing within 5 s, but 188 is within 15. The old rule showed
    /// the user nothing here — the bug this exists to prevent.</summary>
    [Fact]
    public void FallsBackToALooserDurationRatherThanGivingUp() =>
        Assert.Equal(188, LyricsProvider.BestMatch(Track, [Record(188), Record(260)])!.Duration);

    [Fact]
    public void TakesTheSameSongAtAnyLengthWhenNothingElseIsClose() =>
        Assert.Equal(254, LyricsProvider.BestMatch(Track, [Record(254), Record(300)])!.Duration);

    [Fact]
    public void RecordsWithNoDurationAreStillUsable() =>
        Assert.NotNull(LyricsProvider.BestMatch(Track, [Record(null)]));

    [Fact]
    public void ADifferentSongIsNeverAcceptedAtTheWidestTier() =>
        Assert.Null(LyricsProvider.BestMatch(Track, [
            Record(400, artist: "Someone Else", title: "Other Song"),
            Record(null, artist: "Someone Else", title: "Other Song"),
        ]));

    [Fact]
    public void SyncedBeatsPlainWithinTheSameTier() =>
        Assert.Equal(203, LyricsProvider.BestMatch(Track,
            [Record(200, synced: false), Record(203)])!.Duration);

    [Fact]
    public void NamesAreComparedIgnoringCaseAndAccents() =>
        Assert.NotNull(LyricsProvider.BestMatch(Track,
            [Record(400, artist: "the wéeknd", title: "BLINDING LIGHTS")]));

    [Fact]
    public void EmptyRecordsAreIgnored() =>
        Assert.Null(LyricsProvider.BestMatch(Track, [new LyricsProvider.Record
        {
            Duration = 200, ArtistName = "The Weeknd", TrackName = "Blinding Lights",
        }]));

    [Fact]
    public async Task DirectLookupIsTriedFirstWithAllFourFields()
    {
        var http = new StubHttpClient().Enqueue(
            Responses.Json("""{"syncedLyrics":"[00:10.00]Hello","plainLyrics":"Hello"}"""));
        var provider = new LyricsProvider(http, new MemoryLyricsCache());

        var result = await provider.LyricsAsync(Track);

        var synced = Assert.IsType<LyricsResult.Synced>(result);
        Assert.Equal(10_000, synced.Lines[0].TimeMs);

        var query = System.Web.HttpUtility.ParseQueryString(http.Recorded[0].RequestUri!.Query);
        Assert.Equal("lrclib.net", http.Recorded[0].RequestUri!.Host);
        Assert.Equal("/api/get", http.Recorded[0].RequestUri!.AbsolutePath);
        Assert.Equal("The Weeknd", query["artist_name"]);
        Assert.Equal("After Hours", query["album_name"]);
        Assert.Equal("200", query["duration"]);
    }

    [Fact]
    public async Task SearchRescuesATrackWhoseDurationsAllDisagree()
    {
        var http = new StubHttpClient().Enqueue(
            Responses.Status(404),
            Responses.Json("""
            [{"duration":186.0,"syncedLyrics":"[00:12.00]Found","plainLyrics":"Found",
              "artistName":"The Weeknd","trackName":"Blinding Lights"},
             {"duration":260.0,"syncedLyrics":"[00:12.00]Other","plainLyrics":"Other",
              "artistName":"The Weeknd","trackName":"Blinding Lights"}]
            """));

        var result = await new LyricsProvider(http, new MemoryLyricsCache()).LyricsAsync(Track);

        var synced = Assert.IsType<LyricsResult.Synced>(result);
        Assert.Equal("Found", synced.Lines[0].Text);
    }

    [Fact]
    public async Task ASuccessIsCachedAndNotFetchedTwice()
    {
        var cache = new MemoryLyricsCache();
        var http = new StubHttpClient().Enqueue(Responses.Json("""{"plainLyrics":"words"}"""));
        var provider = new LyricsProvider(http, cache);

        await provider.LyricsAsync(Track);
        await provider.LyricsAsync(Track);

        Assert.Single(http.Recorded);
    }

    [Fact]
    public async Task UserAgentIdentifiesTheApp()
    {
        var http = new StubHttpClient().Enqueue(Responses.Json("""{"plainLyrics":"x"}"""));
        await new LyricsProvider(http, new MemoryLyricsCache()).LyricsAsync(Track);
        // .NET splits User-Agent into product tokens, so compare the whole
        // header rather than a single value.
        Assert.Equal(LyricsProvider.UserAgent,
            string.Join(" ", http.Recorded[0].Headers.GetValues("User-Agent")));
    }

    /// <summary>The distinction that matters: a missing song is remembered for
    /// a day, a broken network is never remembered at all.</summary>
    [Fact]
    public async Task ANetworkFailureIsNeverCached()
    {
        var cache = new MemoryLyricsCache();
        var http = new StubHttpClient { ExceptionToThrow = new AppErrorException(new AppError.Network("down")) };

        var result = await new LyricsProvider(http, cache).LyricsAsync(Track);

        Assert.IsType<LyricsResult.NotFound>(result);
        Assert.Empty(cache.Stored);
    }
}

public class LyricsCacheTests : IDisposable
{
    private readonly string _directory = Path.Combine(
        Path.GetTempPath(), "LyricsCacheTests-" + Guid.NewGuid());
    private readonly LyricsCache _cache;
    private readonly DateTime _now = new(2026, 1, 1, 12, 0, 0, DateTimeKind.Utc);

    public LyricsCacheTests() => _cache = new LyricsCache(_directory);

    public void Dispose()
    {
        try { Directory.Delete(_directory, true); } catch (IOException) { }
    }

    [Fact]
    public void RoundTripsSyncedLyrics()
    {
        List<LyricLine> lines = [new(0, "one"), new(900, "two")];
        _cache.Write(new LyricsResult.Synced(lines), "t1", _now);
        var read = Assert.IsType<LyricsResult.Synced>(_cache.Read("t1", _now));
        Assert.Equal(lines, read.Lines);
    }

    [Fact]
    public void RemoveSendsTheNextLookupBackToTheNetwork()
    {
        _cache.Write(LyricsResult.None, "t1", _now);
        Assert.NotNull(_cache.Read("t1", _now));

        _cache.Remove("t1");
        Assert.Null(_cache.Read("t1", _now));
    }

    [Fact]
    public void RemovingSomethingNeverCachedIsHarmless() => _cache.Remove("never-cached");

    [Fact]
    public void ANotFoundExpiresButLyricsDoNot()
    {
        _cache.Write(LyricsResult.None, "missing", _now);
        _cache.Write(new LyricsResult.Plain("words"), "found", _now);

        var later = _now + LyricsProvider.NegativeTtl + TimeSpan.FromSeconds(1);
        Assert.Null(_cache.Read("missing", later));
        Assert.Equal(new LyricsResult.Plain("words"), _cache.Read("found", later));
    }

    /// <summary>Spotify IDs are safe, but the cache must not be one odd ID
    /// away from writing outside its own directory.</summary>
    [Fact]
    public void ATrackIdWithASlashStaysInsideTheCacheDirectory()
    {
        _cache.Write(new LyricsResult.Plain("x"), "a/b", _now);
        Assert.Equal(new LyricsResult.Plain("x"), _cache.Read("a/b", _now));
        Assert.Equal(["a_b.json"], Directory.GetFiles(_directory).Select(Path.GetFileName));
    }
}

public class SettingsTests
{
    [Fact]
    public void TheBuiltInClientIdIsUsedWhenNobodyOverridesIt() =>
        Assert.Equal(AppCredentials.BuiltInClientId, new Settings().ClientId);

    [Fact]
    public void AnOverrideWins() =>
        Assert.Equal("MINE", new Settings { ClientIdOverride = "MINE" }.ClientId);

    [Fact]
    public void ABlankOverrideFallsBackRatherThanBreakingLogin() =>
        Assert.Equal(AppCredentials.BuiltInClientId,
            new Settings { ClientIdOverride = "   " }.ClientId);

    [Fact]
    public void StoredValuesAreClamped()
    {
        var settings = new Settings { SyncOffsetMs = 99_999, OpacityPercent = 500 };
        settings.ClampForStorage();
        Assert.Equal(2000, settings.SyncOffsetMs);
        Assert.Equal(100, settings.OpacityPercent);
    }
}
