import Foundation

/// The Spotify app FloatingLyric ships with, so nobody has to visit a
/// developer dashboard before hearing their first line of lyrics.
///
/// **A Client ID is not a secret.** FloatingLyric authenticates with OAuth
/// PKCE, which exists precisely so public apps can ship their identifier: the
/// proof of identity is a code verifier generated fresh on each login, never
/// anything baked into the binary. There is no client secret here to leak.
///
/// What it *does* mean: this app's name appears on every user's Spotify
/// consent screen, and every user shares its rate limit.
public enum AppCredentials {
    public static let builtInClientID = "28c043c19e724be68994dc1061251068"

    /// True when a usable Client ID shipped with the build. If this is ever
    /// blanked out, the app falls back to asking each user for their own.
    public static var hasBuiltInClientID: Bool {
        !builtInClientID.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
