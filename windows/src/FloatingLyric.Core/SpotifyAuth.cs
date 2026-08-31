using System.Text.Json;

namespace FloatingLyric.Core;

public sealed class SpotifyAuth(
    string clientId, IHttpClient http, ITokenStore store, Func<DateTime>? now = null)
{
    public const string Scope = "user-read-playback-state user-modify-playback-state";

    private const string AuthorizeUrl = "https://accounts.spotify.com/authorize";
    private const string TokenUrl = "https://accounts.spotify.com/api/token";
    private const double RefreshMarginSeconds = 60;

    private readonly Func<DateTime> _now = now ?? (() => DateTime.UtcNow);
    private string? _accessToken;
    private DateTime? _expiresAt;

    public bool IsLoggedIn => store.ReadRefreshToken() is not null;

    public Uri AuthorizationUrl(string challenge, string state, string redirectUri)
    {
        var query = new Dictionary<string, string>
        {
            ["response_type"] = "code",
            ["client_id"] = clientId,
            ["scope"] = Scope,
            ["redirect_uri"] = redirectUri,
            ["state"] = state,
            ["code_challenge_method"] = "S256",
            ["code_challenge"] = challenge,
        };
        var encoded = string.Join("&", query.Select(kv =>
            $"{Uri.EscapeDataString(kv.Key)}={Uri.EscapeDataString(kv.Value)}"));
        return new Uri($"{AuthorizeUrl}?{encoded}");
    }

    public Task ExchangeAsync(string code, string verifier, string redirectUri) =>
        RequestTokenAsync(new Dictionary<string, string>
        {
            ["grant_type"] = "authorization_code",
            ["code"] = code,
            ["redirect_uri"] = redirectUri,
            ["client_id"] = clientId,
            ["code_verifier"] = verifier,
        }, new AppError.AuthCancelled());

    /// <summary>The only route to a token. Refreshes with a minute to spare,
    /// so no caller anywhere thinks about expiry.</summary>
    public async Task<string> AccessTokenAsync()
    {
        if (_accessToken is { } token && _expiresAt is { } expiry &&
            (expiry - _now()).TotalSeconds > RefreshMarginSeconds)
            return token;

        if (store.ReadRefreshToken() is not { } refresh)
            throw new AppErrorException(new AppError.NotLoggedIn());

        await RequestTokenAsync(new Dictionary<string, string>
        {
            ["grant_type"] = "refresh_token",
            ["refresh_token"] = refresh,
            ["client_id"] = clientId,
        }, new AppError.SessionExpired());

        return _accessToken!;
    }

    /// <summary>Forces the next call to refresh — used after a 401.</summary>
    public void InvalidateAccessToken() => _expiresAt = null;

    public void LogOut()
    {
        _accessToken = null;
        _expiresAt = null;
        store.DeleteRefreshToken();
    }

    public void SetAccessTokenForTesting(string token, double expiresIn)
    {
        _accessToken = token;
        _expiresAt = _now().AddSeconds(expiresIn);
    }

    private async Task RequestTokenAsync(Dictionary<string, string> form, AppError failure)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, TokenUrl)
        {
            Content = new FormUrlEncodedContent(form),
        };
        var response = await http.SendAsync(request);

        if (response.Status is < 200 or >= 300)
        {
            // A refresh that fails is a dead session: clear it rather than
            // retrying forever with a token Spotify has rejected.
            if (form["grant_type"] == "refresh_token") store.DeleteRefreshToken();
            throw new AppErrorException(failure);
        }

        JsonDocument json;
        try { json = JsonDocument.Parse(response.Body); }
        catch (JsonException) { throw new AppErrorException(failure); }

        using var _ = json;
        var root = json.RootElement;
        if (root.ValueKind != JsonValueKind.Object ||
            !root.TryGetProperty("access_token", out var accessToken))
            throw new AppErrorException(failure);

        _accessToken = accessToken.GetString();
        var expiresIn = root.TryGetProperty("expires_in", out var e) ? e.GetDouble() : 3600;
        _expiresAt = _now().AddSeconds(expiresIn);

        if (root.TryGetProperty("refresh_token", out var refresh) &&
            refresh.GetString() is { Length: > 0 } value)
            store.WriteRefreshToken(value);
    }
}
