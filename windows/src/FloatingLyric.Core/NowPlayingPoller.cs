using System.Text.Json;

namespace FloatingLyric.Core;

/// <summary>
/// The slow loop: asks Spotify what is playing, every few seconds. Between
/// polls, <see cref="PlayheadClock"/> fills in the gaps.
/// </summary>
public sealed class NowPlayingPoller(SpotifyAuth auth, IHttpClient http)
{
    public const int PlayingIntervalMs = 3_000;
    public const int IdleIntervalMs = 10_000;

    private const string Endpoint = "https://api.spotify.com/v1/me/player/currently-playing";

    private CancellationTokenSource? _loop;

    public static int IntervalMs(PlaybackState state) =>
        state is PlaybackState.Playing ? PlayingIntervalMs : IdleIntervalMs;

    public void Start(Action<PlaybackState> onState)
    {
        Stop();
        var cts = new CancellationTokenSource();
        _loop = cts;

        _ = Task.Run(async () =>
        {
            while (!cts.IsCancellationRequested)
            {
                var state = await PollOnceAsync();
                if (cts.IsCancellationRequested) return;
                onState(state);

                var waitMs = IntervalMs(state);
                if (state is PlaybackState.Failed { Error: AppError.RateLimited limited })
                    waitMs = Math.Max(waitMs, (int)(limited.RetryAfterSeconds * 1000));

                try { await Task.Delay(waitMs, cts.Token); }
                catch (TaskCanceledException) { return; }
            }
        }, cts.Token);
    }

    public void Stop()
    {
        _loop?.Cancel();
        _loop = null;
    }

    public async Task<PlaybackState> PollOnceAsync()
    {
        try
        {
            var response = await RequestAsync();
            if (response.Status == 401)
            {
                auth.InvalidateAccessToken();
                var retry = await RequestAsync();
                if (retry.Status == 401)
                    return new PlaybackState.Failed(new AppError.SessionExpired());
                return Decode(retry);
            }
            return Decode(response);
        }
        catch (AppErrorException e)
        {
            return new PlaybackState.Failed(e.Error);
        }
        catch (Exception e)
        {
            return new PlaybackState.Failed(new AppError.Network(e.Message));
        }
    }

    private async Task<HttpResponse> RequestAsync()
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, Endpoint);
        request.Headers.Add("Authorization", $"Bearer {await auth.AccessTokenAsync()}");
        return await http.SendAsync(request);
    }

    private static PlaybackState Decode(HttpResponse response)
    {
        // Status first, body second. Spotify sends 429 with an empty body, so
        // checking emptiness first reads rate limiting as "nothing playing" —
        // throwing away Retry-After and polling straight back into the limit.
        if (response.Status == 429)
        {
            var retryAfter = response.Headers.TryGetValue("Retry-After", out var value)
                && double.TryParse(value, out var seconds) ? seconds : 5;
            return new PlaybackState.Failed(new AppError.RateLimited(retryAfter));
        }
        if (response.Status is < 200 or >= 300)
            return new PlaybackState.Failed(new AppError.BadResponse(response.Status));
        if (response.Status == 204 || response.Body.Length == 0) return new PlaybackState.Idle();

        try
        {
            using var json = JsonDocument.Parse(response.Body);
            var root = json.RootElement;
            if (!root.TryGetProperty("item", out var item) ||
                item.ValueKind != JsonValueKind.Object) return new PlaybackState.Idle();

            var id = item.GetPropertyOrNull("id")?.GetString();
            var name = item.GetPropertyOrNull("name")?.GetString();
            var duration = item.GetPropertyOrNull("duration_ms")?.GetInt32();
            var artist = item.GetPropertyOrNull("artists") is { ValueKind: JsonValueKind.Array } artists
                && artists.GetArrayLength() > 0
                ? artists[0].GetPropertyOrNull("name")?.GetString()
                : null;

            if (id is null || name is null || duration is null || artist is null)
                return new PlaybackState.Idle();

            var album = item.GetPropertyOrNull("album");
            var track = new TrackIdentity(id, name, artist,
                album?.GetPropertyOrNull("name")?.GetString() ?? "", duration.Value);

            var np = new NowPlaying(
                track,
                root.GetPropertyOrNull("progress_ms")?.GetInt32() ?? 0,
                root.GetPropertyOrNull("is_playing")?.GetBoolean() ?? false,
                album?.GetPropertyOrNull("images") is { ValueKind: JsonValueKind.Array } images
                    && images.GetArrayLength() > 0
                    ? images[0].GetPropertyOrNull("url")?.GetString()
                    : null);

            return np.IsPlaying ? new PlaybackState.Playing(np) : new PlaybackState.Paused(np);
        }
        catch (JsonException)
        {
            return new PlaybackState.Idle();
        }
    }
}

internal static class JsonExtensions
{
    public static JsonElement? GetPropertyOrNull(this JsonElement element, string name) =>
        element.ValueKind == JsonValueKind.Object &&
        element.TryGetProperty(name, out var value) &&
        value.ValueKind != JsonValueKind.Null
            ? value : null;
}
