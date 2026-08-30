import Foundation

/// Decides whether the login window is owed to the user, and which of its two
/// faces to show.
///
/// The two are genuinely different jobs: a first run has to walk someone
/// through creating a Spotify app, while logging back in after **Log Out**
/// only needs a button — the Client ID is already saved and does not change.
public enum LoginPrompt: Equatable {
    /// No Client ID yet: show the full walkthrough.
    case firstRun
    /// Client ID known, no session: just offer to log in.
    case logIn

    public static func required(clientID: String?, isLoggedIn: Bool) -> LoginPrompt? {
        guard let clientID, !clientID.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .firstRun
        }
        return isLoggedIn ? nil : .logIn
    }
}
