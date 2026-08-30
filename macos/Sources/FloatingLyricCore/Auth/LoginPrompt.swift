import Foundation

/// Decides whether the login window is owed to the user, and which of its
/// three faces to show.
///
/// They are genuinely different moments. Someone opening the app for the first
/// time should meet a single button, not a walkthrough for building a Spotify
/// app — that walkthrough only exists for the rare person supplying their own
/// Client ID.
public enum LoginPrompt: Equatable {
    /// No Client ID at all: show the full walkthrough.
    case setup
    /// First run with a Client ID available: welcome them in.
    case welcome
    /// Signed in before, signed out now: just offer to log back in.
    case logIn

    public static func required(clientID: String?,
                                isLoggedIn: Bool,
                                hasSignedInBefore: Bool) -> LoginPrompt? {
        guard let clientID, !clientID.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .setup
        }
        if isLoggedIn { return nil }
        return hasSignedInBefore ? .logIn : .welcome
    }

    /// True for the two faces that only need a button.
    public var isOneClick: Bool { self != .setup }
}
