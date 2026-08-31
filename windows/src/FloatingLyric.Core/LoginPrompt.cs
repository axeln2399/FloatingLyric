namespace FloatingLyric.Core;

/// <summary>
/// Which face of the login window is owed to the user. Someone opening the app
/// for the first time should meet a button, not a walkthrough for registering
/// a Spotify app.
/// </summary>
public enum LoginPrompt { Setup, Welcome, LogIn }

public static class LoginPrompts
{
    public static LoginPrompt? Required(string? clientId, bool isLoggedIn, bool hasSignedInBefore)
    {
        if (string.IsNullOrWhiteSpace(clientId)) return LoginPrompt.Setup;
        if (isLoggedIn) return null;
        return hasSignedInBefore ? LoginPrompt.LogIn : LoginPrompt.Welcome;
    }

    public static bool IsOneClick(this LoginPrompt prompt) => prompt != LoginPrompt.Setup;
}

/// <summary>
/// The Spotify app this build ships with, so nobody visits a developer
/// dashboard before hearing their first line. A Client ID is not a secret
/// under PKCE — there is no client secret here at all.
/// </summary>
public static class AppCredentials
{
    public const string BuiltInClientId = "28c043c19e724be68994dc1061251068";

    public static bool HasBuiltInClientId => !string.IsNullOrWhiteSpace(BuiltInClientId);
}
