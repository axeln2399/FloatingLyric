import Foundation

/// Play/pause and track skipping through the Spotify Web API.
///
/// Every one of these needs the `user-modify-playback-state` scope and a
/// Premium account — Spotify rejects control calls from free accounts with 403.
public final class PlaybackController: @unchecked Sendable {
    private static let base = "https://api.spotify.com/v1/me/player"

    private let auth: SpotifyAuth
    private let http: HTTPClient

    public init(auth: SpotifyAuth, http: HTTPClient) {
        self.auth = auth
        self.http = http
    }

    public func play() async -> AppError? { await send(path: "/play", method: "PUT") }
    public func pause() async -> AppError? { await send(path: "/pause", method: "PUT") }
    public func next() async -> AppError? { await send(path: "/next", method: "POST") }
    public func previous() async -> AppError? { await send(path: "/previous", method: "POST") }

    public func toggle(isPlaying: Bool) async -> AppError? {
        isPlaying ? await pause() : await play()
    }

    /// Returns nil on success, or the error to show in the panel.
    private func send(path: String, method: String) async -> AppError? {
        do {
            let response = try await request(path: path, method: method)
            if response.status == 401 {
                auth.invalidateAccessToken()
                let retry = try await request(path: path, method: method)
                return classify(retry)
            }
            return classify(response)
        } catch let error as AppError {
            return error
        } catch {
            return .network(error.localizedDescription)
        }
    }

    private func request(path: String, method: String) async throws -> HTTPResponse {
        var request = URLRequest(url: URL(string: Self.base + path)!)
        request.httpMethod = method
        request.setValue("Bearer \(try await auth.accessToken())",
                         forHTTPHeaderField: "Authorization")
        // Spotify rejects a PUT with no body and no length header.
        request.setValue("0", forHTTPHeaderField: "Content-Length")
        return try await http.send(request)
    }

    private func classify(_ response: HTTPResponse) -> AppError? {
        switch response.status {
        case 200..<300:
            return nil
        case 401:
            return .sessionExpired
        case 403:
            // 403 covers both "free account" and "token predates the control
            // scope"; the body distinguishes them.
            let body = String(decoding: response.body, as: UTF8.self).lowercased()
            if body.contains("scope") { return .controlScopeMissing }
            return .premiumRequired
        case 404:
            return .noActiveDevice
        case 429:
            let retryAfter = TimeInterval(response.headers["Retry-After"] ?? "") ?? 5
            return .rateLimited(retryAfter: retryAfter)
        default:
            return .badResponse(status: response.status)
        }
    }
}
