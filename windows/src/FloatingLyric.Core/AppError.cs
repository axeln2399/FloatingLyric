namespace FloatingLyric.Core;

/// <summary>Everything that can go wrong, and what to say about it.</summary>
public abstract record AppError
{
    public sealed record NotConfigured : AppError;
    public sealed record NotLoggedIn : AppError;
    public sealed record SessionExpired : AppError;
    public sealed record Network(string Detail) : AppError;
    public sealed record RateLimited(double RetryAfterSeconds) : AppError;
    public sealed record BadResponse(int Status) : AppError;
    public sealed record PortUnavailable : AppError;
    public sealed record AuthCancelled : AppError;
    public sealed record AuthStateMismatch : AppError;
    public sealed record PremiumRequired : AppError;
    public sealed record NoActiveDevice : AppError;
    public sealed record ControlScopeMissing : AppError;

    public string DisplayMessage => this switch
    {
        NotConfigured => "Set up Spotify to begin",
        NotLoggedIn => "Log in to Spotify",
        SessionExpired => "Session expired — log in again",
        Network => "Offline",
        RateLimited => "Spotify is rate limiting — retrying",
        BadResponse => "Spotify returned an unexpected response",
        PortUnavailable => "Port 8888–8890 in use. Free one and retry.",
        AuthCancelled => "Login cancelled",
        AuthStateMismatch => "Login response did not match this request — try again",
        PremiumRequired => "Spotify Premium required to control playback",
        NoActiveDevice => "No active Spotify device",
        ControlScopeMissing => "Log out and back in to enable playback controls",
        _ => "Something went wrong",
    };
}

public sealed class AppErrorException(AppError error) : Exception(error.DisplayMessage)
{
    public AppError Error { get; } = error;
}
