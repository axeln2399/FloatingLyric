using FloatingLyric.Core;
using Xunit;

namespace FloatingLyric.Core.Tests;

public class TransliterationTests
{
    private static bool IsLatinish(string s) => s.Length > 0 && s.All(c => c < 'ɐ');

    [Theory]
    [InlineData("Blinding Lights")]
    [InlineData("I'm going through withdrawals")]
    [InlineData("Café déjà vu")]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("♪ ♪ ♪")]
    [InlineData("123 456")]
    public void LinesThatNeedNothingGetNothing(string text) =>
        Assert.Null(Transliteration.Romanize(text));

    [Theory]
    [InlineData("こんにちは", "konnichiha")]
    [InlineData("カタカナ", "katakana")]
    [InlineData("きゃっと", "kyatto")]
    [InlineData("しゅう", "shuu")]
    [InlineData("ラーメン", "raamen")]
    public void KanaIsRomanized(string text, string expected) =>
        Assert.Equal(expected, Transliteration.Romanize(text));

    [Fact]
    public void SmallTsuDoublesTheFollowingConsonant() =>
        Assert.Equal("gakkou", Transliteration.Romanize("がっこう"));

    [Fact]
    public void CyrillicIsRomanized()
    {
        var result = Transliteration.Romanize("привет мир");
        Assert.NotNull(result);
        Assert.True(IsLatinish(result!), result);
    }

    [Fact]
    public void GreekIsRomanized()
    {
        var result = Transliteration.Romanize("καλημέρα");
        Assert.NotNull(result);
        Assert.True(IsLatinish(result!), result);
    }

    /// <summary>
    /// The honest limit of the Windows build: reading kanji needs a dictionary
    /// and the surrounding words, which Windows ships nothing for. Half a line
    /// in Latin would be worse than none.
    /// </summary>
    [Theory]
    [InlineData("君の名は")]
    [InlineData("僕は歩く")]
    public void KanjiIsRefusedRatherThanGuessed(string text) =>
        Assert.Null(Transliteration.Romanize(text));

    [Fact]
    public void LatinWordsInsideANonLatinLineSurvive()
    {
        var result = Transliteration.Romanize("こんにちは world");
        Assert.Equal("konnichiha world", result);
    }

    [Fact]
    public void IsRepeatable() =>
        Assert.Equal(Transliteration.Romanize("こんにちは"), Transliteration.Romanize("こんにちは"));
}

public class SpotifyAuthTests
{
    private static (SpotifyAuth, StubHttpClient, InMemoryTokenStore) Make(string? refresh = "RT")
    {
        var http = new StubHttpClient();
        var store = new InMemoryTokenStore(refresh);
        return (new SpotifyAuth("CID", http, store), http, store);
    }

    [Fact]
    public void AuthorizationUrlCarriesPkceAndScope()
    {
        var (auth, _, _) = Make();
        var url = auth.AuthorizationUrl("CHAL", "ST", "http://127.0.0.1:8888/callback");
        var query = System.Web.HttpUtility.ParseQueryString(url.Query);

        Assert.Equal("accounts.spotify.com", url.Host);
        Assert.Equal("/authorize", url.AbsolutePath);
        Assert.Equal("code", query["response_type"]);
        Assert.Equal("CID", query["client_id"]);
        Assert.Equal("S256", query["code_challenge_method"]);
        Assert.Equal("CHAL", query["code_challenge"]);
        Assert.Equal("ST", query["state"]);
        Assert.Equal(SpotifyAuth.Scope, query["scope"]);
        Assert.Contains("user-modify-playback-state", SpotifyAuth.Scope);
    }

    [Fact]
    public async Task ExchangeStoresTheRefreshToken()
    {
        var (auth, http, store) = Make(null);
        http.Enqueue(Responses.Json("""{"access_token":"AT","refresh_token":"NEW","expires_in":3600}"""));

        await auth.ExchangeAsync("CODE", "VERIFIER", "http://127.0.0.1:8888/callback");

        Assert.Equal("NEW", store.ReadRefreshToken());
        Assert.Equal("AT", await auth.AccessTokenAsync());
    }

    [Fact]
    public async Task ACachedTokenIsReusedUntilItNearsExpiry()
    {
        var (auth, http, _) = Make();
        auth.SetAccessTokenForTesting("AT", 3600);

        Assert.Equal("AT", await auth.AccessTokenAsync());
        Assert.Empty(http.Recorded);
    }

    [Fact]
    public async Task InvalidateForcesTheNextCallToRefresh()
    {
        var (auth, http, _) = Make();
        auth.SetAccessTokenForTesting("AT", 3600);
        auth.InvalidateAccessToken();
        http.Enqueue(Responses.Json("""{"access_token":"AT2","expires_in":3600}"""));

        Assert.Equal("AT2", await auth.AccessTokenAsync());
        Assert.Single(http.Recorded);
    }

    [Fact]
    public async Task AFailedRefreshClearsTheSessionRatherThanRetryingForever()
    {
        var (auth, http, store) = Make();
        http.Enqueue(Responses.Status(400));

        var error = await Assert.ThrowsAsync<AppErrorException>(() => auth.AccessTokenAsync());

        Assert.IsType<AppError.SessionExpired>(error.Error);
        Assert.Null(store.ReadRefreshToken());
        Assert.False(auth.IsLoggedIn);
    }

    [Fact]
    public async Task NoRefreshTokenMeansNotLoggedIn()
    {
        var (auth, _, _) = Make(null);
        var error = await Assert.ThrowsAsync<AppErrorException>(() => auth.AccessTokenAsync());
        Assert.IsType<AppError.NotLoggedIn>(error.Error);
    }

    [Fact]
    public void LogOutForgetsEverything()
    {
        var (auth, _, store) = Make();
        auth.LogOut();
        Assert.Null(store.ReadRefreshToken());
    }
}

public class PlaybackControllerTests
{
    private static (PlaybackController, StubHttpClient) Make(params HttpResponse[] responses)
    {
        var http = new StubHttpClient().Enqueue(responses);
        var auth = new SpotifyAuth("CID", new StubHttpClient(), new InMemoryTokenStore("RT"));
        auth.SetAccessTokenForTesting("AT", 3600);
        return (new PlaybackController(auth, http), http);
    }

    private static HttpResponse Ok => Responses.Status(204);

    [Fact]
    public async Task PlayAndPauseUsePut()
    {
        var (controller, http) = Make(Ok);
        Assert.Null(await controller.PlayAsync());
        Assert.Equal(HttpMethod.Put, http.Recorded[0].Method);
        Assert.Equal("/v1/me/player/play", http.Recorded[0].RequestUri!.AbsolutePath);
    }

    [Fact]
    public async Task SkipsUsePost()
    {
        var (controller, http) = Make(Ok);
        Assert.Null(await controller.NextAsync());
        Assert.Equal(HttpMethod.Post, http.Recorded[0].Method);
        Assert.Equal("/v1/me/player/next", http.Recorded[0].RequestUri!.AbsolutePath);
    }

    [Fact]
    public async Task ToggleCallsPauseWhenPlaying()
    {
        var (playing, playingHttp) = Make(Ok);
        await playing.ToggleAsync(true);
        Assert.Equal("/v1/me/player/pause", playingHttp.Recorded[0].RequestUri!.AbsolutePath);

        var (paused, pausedHttp) = Make(Ok);
        await paused.ToggleAsync(false);
        Assert.Equal("/v1/me/player/play", pausedHttp.Recorded[0].RequestUri!.AbsolutePath);
    }

    [Fact]
    public async Task CarriesTheBearerToken()
    {
        var (controller, http) = Make(Ok);
        await controller.PlayAsync();
        Assert.Equal("Bearer AT", http.Recorded[0].Headers.GetValues("Authorization").Single());
    }

    [Fact]
    public async Task FreeAccountsGetAPremiumRequiredError()
    {
        var (controller, _) = Make(Responses.Json("""{"error":{"message":"Player command failed: Premium required"}}""", 403));
        Assert.IsType<AppError.PremiumRequired>(await controller.PlayAsync());
    }

    [Fact]
    public async Task AMissingScopeIsDistinguishedFromAFreeAccount()
    {
        var (controller, _) = Make(Responses.Json("""{"error":{"message":"Insufficient client scope"}}""", 403));
        Assert.IsType<AppError.ControlScopeMissing>(await controller.PlayAsync());
    }

    [Fact]
    public async Task NoActiveDeviceIsReported() =>
        Assert.IsType<AppError.NoActiveDevice>(await Make(Responses.Status(404)).Item1.NextAsync());

    [Fact]
    public async Task RateLimitCarriesRetryAfter()
    {
        var (controller, _) = Make(Responses.Status(429, ("Retry-After", "3")));
        var error = Assert.IsType<AppError.RateLimited>(await controller.NextAsync());
        Assert.Equal(3, error.RetryAfterSeconds);
    }

    [Fact]
    public async Task UnauthorizedRefreshesAndRetriesOnce()
    {
        var http = new StubHttpClient().Enqueue(Responses.Status(401), Responses.Status(204));
        var authHttp = new StubHttpClient().Enqueue(
            Responses.Json("""{"access_token":"AT2","expires_in":3600}"""));
        var auth = new SpotifyAuth("CID", authHttp, new InMemoryTokenStore("RT"));
        auth.SetAccessTokenForTesting("AT", 3600);

        Assert.Null(await new PlaybackController(auth, http).PlayAsync());
        Assert.Equal(2, http.Recorded.Count);
        Assert.Equal("Bearer AT2", http.Recorded[1].Headers.GetValues("Authorization").Single());
    }

    [Fact]
    public async Task NetworkFailureIsReported()
    {
        var http = new StubHttpClient { ExceptionToThrow = new AppErrorException(new AppError.Network("offline")) };
        var auth = new SpotifyAuth("CID", new StubHttpClient(), new InMemoryTokenStore("RT"));
        auth.SetAccessTokenForTesting("AT", 3600);
        Assert.IsType<AppError.Network>(await new PlaybackController(auth, http).PlayAsync());
    }
}

public class NowPlayingPollerTests
{
    private static NowPlayingPoller Make(params HttpResponse[] responses)
    {
        var http = new StubHttpClient().Enqueue(responses);
        var auth = new SpotifyAuth("CID", new StubHttpClient(), new InMemoryTokenStore("RT"));
        auth.SetAccessTokenForTesting("AT", 3600);
        return new NowPlayingPoller(auth, http);
    }

    private const string PlayingJson = """
    {"is_playing":true,"progress_ms":42000,
     "item":{"id":"t1","name":"Song","duration_ms":210000,
             "artists":[{"name":"Band"}],
             "album":{"name":"Album","images":[{"url":"https://img"}]}}}
    """;

    [Fact]
    public async Task DecodesAPlayingTrack()
    {
        var state = await Make(Responses.Json(PlayingJson)).PollOnceAsync();
        var playing = Assert.IsType<PlaybackState.Playing>(state);
        Assert.Equal("t1", playing.Np.Track.Id);
        Assert.Equal("Song", playing.Np.Track.Title);
        Assert.Equal("Band", playing.Np.Track.Artist);
        Assert.Equal("Album", playing.Np.Track.Album);
        Assert.Equal(210_000, playing.Np.Track.DurationMs);
        Assert.Equal(42_000, playing.Np.ProgressMs);
    }

    [Fact]
    public async Task PausedIsDistinguishedFromPlaying()
    {
        var state = await Make(Responses.Json(PlayingJson.Replace("\"is_playing\":true", "\"is_playing\":false"))).PollOnceAsync();
        Assert.IsType<PlaybackState.Paused>(state);
    }

    [Fact]
    public async Task NoContentMeansNothingIsPlaying() =>
        Assert.IsType<PlaybackState.Idle>(await Make(Responses.Status(204)).PollOnceAsync());

    [Fact]
    public async Task TwoUnauthorizedRepliesMeanTheSessionIsDead()
    {
        var http = new StubHttpClient().Enqueue(Responses.Status(401), Responses.Status(401));
        var authHttp = new StubHttpClient().Enqueue(
            Responses.Json("""{"access_token":"AT2","expires_in":3600}"""));
        var auth = new SpotifyAuth("CID", authHttp, new InMemoryTokenStore("RT"));
        auth.SetAccessTokenForTesting("AT", 3600);

        var state = await new NowPlayingPoller(auth, http).PollOnceAsync();

        var failed = Assert.IsType<PlaybackState.Failed>(state);
        Assert.IsType<AppError.SessionExpired>(failed.Error);
    }

    /// The case that used to be misread as silence: Spotify's real 429 has no
    /// body at all.
    [Fact]
    public async Task RateLimitWithAnEmptyBodyIsStillARateLimit()
    {
        var state = await Make(Responses.Status(429, ("Retry-After", "7"))).PollOnceAsync();
        var failed = Assert.IsType<PlaybackState.Failed>(state);
        Assert.Equal(7, Assert.IsType<AppError.RateLimited>(failed.Error).RetryAfterSeconds);
    }

    [Fact]
    public async Task AServerErrorWithNoBodyIsNotMistakenForSilence()
    {
        var state = await Make(Responses.Status(502)).PollOnceAsync();
        var failed = Assert.IsType<PlaybackState.Failed>(state);
        Assert.Equal(502, Assert.IsType<AppError.BadResponse>(failed.Error).Status);
    }

    [Fact]
    public void PollingSlowsDownWhenNothingIsPlaying()
    {
        Assert.Equal(3_000, NowPlayingPoller.IntervalMs(new PlaybackState.Playing(
            new NowPlaying(new TrackIdentity("i", "t", "a", "al", 1), 0, true, null))));
        Assert.Equal(10_000, NowPlayingPoller.IntervalMs(new PlaybackState.Idle()));
    }
}
