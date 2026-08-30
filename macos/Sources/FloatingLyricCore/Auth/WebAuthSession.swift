import AppKit
import AuthenticationServices

/// Presents Spotify's own login page and hands back the URL it redirects to.
public protocol WebAuthenticating: AnyObject, Sendable {
    /// Throws `AppError.authCancelled` if the user closes the sheet, and
    /// `AppError.authUnavailable` if the sheet cannot be shown at all.
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}

/// The real thing: a sheet over the app running Safari's engine.
///
/// It shares Safari's cookies, so someone already signed in to Spotify usually
/// gets one click rather than a password prompt — and the password, when it is
/// asked for, is typed into Spotify's page, not into anything this app can see.
public final class WebAuthSession: NSObject, WebAuthenticating,
                                   ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    private let anchor: () -> NSWindow?

    /// - Parameter anchor: the window to hang the sheet on. FloatingLyric has
    ///   no Dock icon and may have no window on screen at all, so this is
    ///   allowed to return nil and fall back to a detached presentation.
    public init(anchor: @escaping () -> NSWindow?) {
        self.anchor = anchor
    }

    public func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: Self.translate(error))
                }
            }
            session.presentationContextProvider = self
            // Deliberately false: sharing the browser session is the entire
            // point. An ephemeral session would ask for the password every
            // single time.
            session.prefersEphemeralWebBrowserSession = false

            guard session.start() else {
                continuation.resume(throwing: AppError.authUnavailable)
                return
            }
        }
    }

    private static func translate(_ error: Error?) -> AppError {
        guard let error = error as? ASWebAuthenticationSessionError else {
            return .authCancelled
        }
        switch error.code {
        case .canceledLogin:
            return .authCancelled
        default:
            // presentationContextNotProvided, presentationContextInvalid: the
            // sheet never appeared, which is worth distinguishing so the
            // caller can fall back to the browser.
            return .authUnavailable
        }
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            anchor() ?? NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
        }
    }
}
