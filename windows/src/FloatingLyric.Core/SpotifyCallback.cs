using System.Web;

namespace FloatingLyric.Core;

/// <summary>
/// Where Spotify sends the browser back to, and how to read what it sent.
///
/// Windows has no ASWebAuthenticationSession, so unlike the Mac build this
/// port uses the loopback redirect — which is why the Spotify dashboard needs
/// http://127.0.0.1:8888/callback registered.
/// </summary>
public static class SpotifyCallback
{
    public static readonly int[] CandidatePorts = [8888, 8889, 8890];

    public static string RedirectUri(int port) => $"http://127.0.0.1:{port}/callback";

    /// <summary>
    /// Reads the authorization code out of the callback, rejecting anything
    /// that does not carry back the state we sent — that is the CSRF defence,
    /// not decoration.
    /// </summary>
    public static Result Code(Uri url, string expectedState)
    {
        var query = HttpUtility.ParseQueryString(url.Query);
        string? Value(string name) =>
            string.IsNullOrEmpty(query[name]) ? null : query[name];

        // Spotify reports a refusal in the query, not as a failed request, and
        // sends no code with it — so this is checked before the state.
        if (Value("error") is not null) return Result.Fail(new AppError.AuthCancelled());
        if (Value("state") is not { } state || state != expectedState)
            return Result.Fail(new AppError.AuthStateMismatch());
        if (Value("code") is not { } code) return Result.Fail(new AppError.AuthCancelled());
        return Result.Ok(code);
    }

    public sealed record Result(string? Value, AppError? Error)
    {
        public static Result Ok(string code) => new(code, null);
        public static Result Fail(AppError error) => new(null, error);
        public bool IsSuccess => Error is null;
    }
}
