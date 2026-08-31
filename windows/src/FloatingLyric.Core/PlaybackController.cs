namespace FloatingLyric.Core;

/// <summary>
/// Play, pause and skip. Every one of these needs the
/// user-modify-playback-state scope and a Premium account — Spotify rejects
/// control calls from free accounts with 403.
/// </summary>
public sealed class PlaybackController(SpotifyAuth auth, IHttpClient http)
{
    private const string Base = "https://api.spotify.com/v1/me/player";

    public Task<AppError?> PlayAsync() => SendAsync("/play", HttpMethod.Put);
    public Task<AppError?> PauseAsync() => SendAsync("/pause", HttpMethod.Put);
    public Task<AppError?> NextAsync() => SendAsync("/next", HttpMethod.Post);
    public Task<AppError?> PreviousAsync() => SendAsync("/previous", HttpMethod.Post);

    public Task<AppError?> ToggleAsync(bool isPlaying) =>
        isPlaying ? PauseAsync() : PlayAsync();

    /// <summary>Null on success, or the error to show in the panel.</summary>
    private async Task<AppError?> SendAsync(string path, HttpMethod method)
    {
        try
        {
            var response = await RequestAsync(path, method);
            if (response.Status == 401)
            {
                auth.InvalidateAccessToken();
                return Classify(await RequestAsync(path, method));
            }
            return Classify(response);
        }
        catch (AppErrorException e)
        {
            return e.Error;
        }
        catch (Exception e)
        {
            return new AppError.Network(e.Message);
        }
    }

    private async Task<HttpResponse> RequestAsync(string path, HttpMethod method)
    {
        using var request = new HttpRequestMessage(method, Base + path);
        request.Headers.Add("Authorization", $"Bearer {await auth.AccessTokenAsync()}");
        // Spotify rejects a PUT with no body and no length header.
        request.Content = new ByteArrayContent([]);
        return await http.SendAsync(request);
    }

    private static AppError? Classify(HttpResponse response) => response.Status switch
    {
        >= 200 and < 300 => null,
        401 => new AppError.SessionExpired(),
        // 403 covers both "free account" and "token predates the control
        // scope"; only the body tells them apart.
        403 => response.Text.Contains("scope", StringComparison.OrdinalIgnoreCase)
            ? new AppError.ControlScopeMissing()
            : new AppError.PremiumRequired(),
        404 => new AppError.NoActiveDevice(),
        429 => new AppError.RateLimited(
            response.Headers.TryGetValue("Retry-After", out var value)
                && double.TryParse(value, out var seconds) ? seconds : 5),
        var status => new AppError.BadResponse(status),
    };
}
