import Foundation

public final class SpotifyAuth: @unchecked Sendable {
    public static let scope = "user-read-playback-state user-modify-playback-state"
    private static let authorizeURL = URL(string: "https://accounts.spotify.com/authorize")!
    private static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
    private static let refreshMarginSeconds: TimeInterval = 60

    private let clientID: String
    private let http: HTTPClient
    private let store: TokenStore
    private let now: () -> Date

    private var accessTokenValue: String?
    private var expiresAt: Date?

    public init(clientID: String,
                http: HTTPClient,
                store: TokenStore,
                now: @escaping () -> Date = Date.init) {
        self.clientID = clientID
        self.http = http
        self.store = store
        self.now = now
    }

    public var isLoggedIn: Bool { store.readRefreshToken() != nil }

    public func authorizationURL(challenge: String, state: String, redirectURI: String) -> URL {
        var components = URLComponents(url: Self.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientID),
            .init(name: "scope", value: Self.scope),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "state", value: state),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
        ]
        return components.url!
    }

    public func exchange(code: String, verifier: String, redirectURI: String) async throws {
        try await requestToken(form: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ], failureError: .authCancelled)
    }

    public func accessToken() async throws -> String {
        if let token = accessTokenValue, let expiresAt,
           expiresAt.timeIntervalSince(now()) > Self.refreshMarginSeconds {
            return token
        }
        guard let refreshToken = store.readRefreshToken() else { throw AppError.notLoggedIn }
        try await requestToken(form: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ], failureError: .sessionExpired)
        guard let token = accessTokenValue else { throw AppError.sessionExpired }
        return token
    }

    /// Drops the cached access token so the next `accessToken()` refreshes.
    public func invalidateAccessToken() {
        accessTokenValue = nil
        expiresAt = nil
    }

    public func logOut() {
        invalidateAccessToken()
        store.deleteRefreshToken()
    }

    /// Test seam: installs an access token without a network round-trip.
    public func setAccessTokenForTesting(_ token: String, expiresIn: TimeInterval) {
        accessTokenValue = token
        expiresAt = now().addingTimeInterval(expiresIn)
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
    }

    private func requestToken(form: [String: String], failureError: AppError) async throws {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncode(form).utf8)

        let response = try await http.send(request)
        guard (200..<300).contains(response.status),
              let decoded = try? JSONDecoder().decode(TokenResponse.self, from: response.body)
        else {
            if failureError == .sessionExpired { logOut() }
            throw failureError
        }

        accessTokenValue = decoded.access_token
        expiresAt = now().addingTimeInterval(TimeInterval(decoded.expires_in))
        if let refresh = decoded.refresh_token { store.writeRefreshToken(refresh) }
    }

    private func formEncode(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }
}
