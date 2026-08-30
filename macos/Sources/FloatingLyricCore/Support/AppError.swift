import Foundation

public enum AppError: Error, Equatable {
    case notConfigured
    case notLoggedIn
    case sessionExpired
    case network(String)
    case rateLimited(retryAfter: TimeInterval)
    case badResponse(status: Int)
    case portUnavailable
    case authCancelled
    case authUnavailable
    case authStateMismatch
    case premiumRequired
    case noActiveDevice
    case controlScopeMissing

    public var displayMessage: String {
        switch self {
        case .notConfigured:   return "Set up Spotify to begin"
        case .notLoggedIn:     return "Log in to Spotify"
        case .sessionExpired:  return "Session expired — log in again"
        case .network:         return "Offline"
        case .rateLimited:     return "Spotify is rate limiting — retrying"
        case .badResponse:     return "Spotify returned an unexpected response"
        case .portUnavailable: return "Port 8888–8890 in use. Free one and retry."
        case .authCancelled:   return "Login cancelled"
        case .authUnavailable: return "Could not open the Spotify login window"
        case .authStateMismatch:
            return "Login response did not match this request — try again"
        case .premiumRequired: return "Spotify Premium required to control playback"
        case .noActiveDevice:  return "No active Spotify device"
        case .controlScopeMissing:
            return "Log out and back in to enable playback controls"
        }
    }
}
