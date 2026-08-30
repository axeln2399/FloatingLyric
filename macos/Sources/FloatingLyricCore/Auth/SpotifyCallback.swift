import Foundation

/// Where Spotify sends the browser back to, and how to read what it sent.
///
/// The app registers a private URL scheme rather than a loopback address:
/// `ASWebAuthenticationSession` intercepts a custom scheme itself, which is
/// what lets the login happen in a sheet with no local web server, no port to
/// fight over, and no firewall prompt.
public enum SpotifyCallback {
    public static let scheme = "floatinglyric"
    public static let uri = "floatinglyric://callback"

    /// Reads the authorization code out of the URL Spotify redirected to,
    /// rejecting anything that does not carry back the `state` we sent.
    ///
    /// The state check is the CSRF defence: without it, someone else's
    /// authorization response would be accepted as if it were ours.
    public static func code(from url: URL, expectedState: String) -> Result<String, AppError> {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .failure(.authCancelled)
        }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value?.nilIfEmpty
        }

        // Spotify reports a refusal — "access_denied" when the user clicks
        // Cancel — in the query rather than as a failed request.
        if value("error") != nil { return .failure(.authCancelled) }

        guard let state = value("state"), state == expectedState else {
            return .failure(.authStateMismatch)
        }
        guard let code = value("code") else { return .failure(.authCancelled) }
        return .success(code)
    }
}
