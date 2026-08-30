import XCTest
@testable import FloatingLyricCore

final class SpotifyAuthTests: XCTestCase {
    private let redirect = "http://127.0.0.1:8888/callback"

    private func makeAuth(store: TokenStore = InMemoryTokenStore(),
                          http: StubHTTPClient = StubHTTPClient(),
                          clock: @escaping () -> Date = { Date(timeIntervalSince1970: 1000) })
    -> (SpotifyAuth, StubHTTPClient, TokenStore) {
        (SpotifyAuth(clientID: "CID", http: http, store: store, now: clock), http, store)
    }

    func test_authorizationURLCarriesPKCEAndScope() {
        let (auth, _, _) = makeAuth()
        let url = auth.authorizationURL(challenge: "CHAL", state: "ST", redirectURI: redirect)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        XCTAssertEqual(url.host, "accounts.spotify.com")
        XCTAssertEqual(url.path, "/authorize")
        XCTAssertEqual(value("response_type"), "code")
        XCTAssertEqual(value("client_id"), "CID")
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("code_challenge"), "CHAL")
        XCTAssertEqual(value("state"), "ST")
        XCTAssertEqual(value("scope"), SpotifyAuth.scope)
        XCTAssertEqual(value("redirect_uri"), redirect)
    }

    func test_exchangeStoresRefreshTokenAndReturnsAccessToken() async throws {
        let (auth, http, store) = makeAuth()
        http.responses = [.json(#"{"access_token":"AT","refresh_token":"RT","expires_in":3600}"#)]

        try await auth.exchange(code: "CODE", verifier: "VER", redirectURI: redirect)

        XCTAssertEqual(store.readRefreshToken(), "RT")
        XCTAssertTrue(auth.isLoggedIn)
        let token = try await auth.accessToken()
        XCTAssertEqual(token, "AT")
        XCTAssertEqual(http.recordedRequests.count, 1, "cached token must not trigger a refresh")
    }

    func test_notLoggedInWithoutStoredRefreshToken() async {
        let (auth, _, _) = makeAuth()
        XCTAssertFalse(auth.isLoggedIn)
        do {
            _ = try await auth.accessToken()
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? AppError, .notLoggedIn)
        }
    }

    func test_refreshesWhenTokenIsWithinSixtySecondsOfExpiry() async throws {
        var now = Date(timeIntervalSince1970: 1000)
        let http = StubHTTPClient()
        let (auth, _, _) = makeAuth(http: http, clock: { now })
        http.responses = [
            .json(#"{"access_token":"AT1","refresh_token":"RT","expires_in":3600}"#),
            .json(#"{"access_token":"AT2","expires_in":3600}"#),
        ]
        try await auth.exchange(code: "C", verifier: "V", redirectURI: redirect)

        now = Date(timeIntervalSince1970: 1000 + 3600 - 59)
        let token = try await auth.accessToken()
        XCTAssertEqual(token, "AT2")
        XCTAssertEqual(http.recordedRequests.count, 2)
    }

    func test_refreshResponseWithoutNewRefreshTokenKeepsTheOldOne() async throws {
        var now = Date(timeIntervalSince1970: 1000)
        let store = InMemoryTokenStore()
        let http = StubHTTPClient()
        let (auth, _, _) = makeAuth(store: store, http: http, clock: { now })
        http.responses = [
            .json(#"{"access_token":"AT1","refresh_token":"RT","expires_in":3600}"#),
            .json(#"{"access_token":"AT2","expires_in":3600}"#),
        ]
        try await auth.exchange(code: "C", verifier: "V", redirectURI: redirect)
        now = Date(timeIntervalSince1970: 5000)
        _ = try await auth.accessToken()
        XCTAssertEqual(store.readRefreshToken(), "RT")
    }

    func test_failedRefreshClearsTokenAndReportsSessionExpired() async throws {
        var now = Date(timeIntervalSince1970: 1000)
        let store = InMemoryTokenStore()
        let http = StubHTTPClient()
        let (auth, _, _) = makeAuth(store: store, http: http, clock: { now })
        http.responses = [
            .json(#"{"access_token":"AT1","refresh_token":"RT","expires_in":3600}"#),
            .json(#"{"error":"invalid_grant"}"#, status: 400),
        ]
        try await auth.exchange(code: "C", verifier: "V", redirectURI: redirect)
        now = Date(timeIntervalSince1970: 99_999)

        do {
            _ = try await auth.accessToken()
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? AppError, .sessionExpired)
        }
        XCTAssertNil(store.readRefreshToken())
        XCTAssertFalse(auth.isLoggedIn)
    }

    func test_invalidateForcesTheNextCallToRefresh() async throws {
        let http = StubHTTPClient()
        let (auth, _, _) = makeAuth(http: http)
        http.responses = [
            .json(#"{"access_token":"AT1","refresh_token":"RT","expires_in":3600}"#),
            .json(#"{"access_token":"AT2","expires_in":3600}"#),
        ]
        try await auth.exchange(code: "C", verifier: "V", redirectURI: redirect)
        auth.invalidateAccessToken()
        let token = try await auth.accessToken()
        XCTAssertEqual(token, "AT2")
    }

    func test_logOutClearsEverything() async throws {
        let (auth, http, store) = makeAuth()
        http.responses = [.json(#"{"access_token":"AT","refresh_token":"RT","expires_in":3600}"#)]
        try await auth.exchange(code: "C", verifier: "V", redirectURI: redirect)
        auth.logOut()
        XCTAssertFalse(auth.isLoggedIn)
        XCTAssertNil(store.readRefreshToken())
    }
}
