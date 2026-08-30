import XCTest
@testable import FloatingLyricCore

final class PlaybackControllerTests: XCTestCase {
    private func make(_ responses: [HTTPResponse], authResponses: [HTTPResponse] = [])
    -> (PlaybackController, StubHTTPClient) {
        let http = StubHTTPClient()
        http.responses = responses
        let authHTTP = StubHTTPClient()
        authHTTP.responses = authResponses
        let auth = SpotifyAuth(clientID: "CID", http: authHTTP,
                               store: InMemoryTokenStore(token: "RT"))
        auth.setAccessTokenForTesting("AT", expiresIn: 3600)
        return (PlaybackController(auth: auth, http: http), http)
    }

    private static let ok = HTTPResponse(status: 204, body: Data(), headers: [:])

    func test_playUsesPutOnThePlayEndpoint() async {
        let (controller, http) = make([Self.ok])
        let error = await controller.play()
        XCTAssertNil(error)
        XCTAssertEqual(http.recordedRequests.first?.httpMethod, "PUT")
        XCTAssertEqual(http.recordedRequests.first?.url?.path, "/v1/me/player/play")
    }

    func test_pauseUsesPutOnThePauseEndpoint() async {
        let (controller, http) = make([Self.ok])
        let pauseError = await controller.pause()
        XCTAssertNil(pauseError)
        XCTAssertEqual(http.recordedRequests.first?.httpMethod, "PUT")
        XCTAssertEqual(http.recordedRequests.first?.url?.path, "/v1/me/player/pause")
    }

    func test_nextUsesPostOnTheNextEndpoint() async {
        let (controller, http) = make([Self.ok])
        let nextError = await controller.next()
        XCTAssertNil(nextError)
        XCTAssertEqual(http.recordedRequests.first?.httpMethod, "POST")
        XCTAssertEqual(http.recordedRequests.first?.url?.path, "/v1/me/player/next")
    }

    func test_previousUsesPostOnThePreviousEndpoint() async {
        let (controller, http) = make([Self.ok])
        let previousError = await controller.previous()
        XCTAssertNil(previousError)
        XCTAssertEqual(http.recordedRequests.first?.httpMethod, "POST")
        XCTAssertEqual(http.recordedRequests.first?.url?.path, "/v1/me/player/previous")
    }

    func test_toggleCallsPauseWhenPlayingAndPlayWhenPaused() async {
        let (playing, playingHTTP) = make([Self.ok])
        _ = await playing.toggle(isPlaying: true)
        XCTAssertEqual(playingHTTP.recordedRequests.first?.url?.path, "/v1/me/player/pause")

        let (paused, pausedHTTP) = make([Self.ok])
        _ = await paused.toggle(isPlaying: false)
        XCTAssertEqual(pausedHTTP.recordedRequests.first?.url?.path, "/v1/me/player/play")
    }

    func test_carriesTheBearerToken() async {
        let (controller, http) = make([Self.ok])
        _ = await controller.play()
        XCTAssertEqual(http.recordedRequests.first?.value(forHTTPHeaderField: "Authorization"),
                       "Bearer AT")
    }

    func test_freeAccountsGetAPremiumRequiredError() async {
        let (controller, _) = make([
            HTTPResponse(status: 403, body: Data(#"{"error":{"message":"Player command failed: Premium required"}}"#.utf8), headers: [:])
        ])
        let error = await controller.play()
        XCTAssertEqual(error, .premiumRequired)
    }

    func test_aTokenWithoutTheControlScopeIsDistinguishedFromAFreeAccount() async {
        let (controller, _) = make([
            HTTPResponse(status: 403, body: Data(#"{"error":{"message":"Insufficient client scope"}}"#.utf8), headers: [:])
        ])
        let error = await controller.play()
        XCTAssertEqual(error, .controlScopeMissing)
    }

    func test_noActiveDeviceIsReported() async {
        let (controller, _) = make([HTTPResponse(status: 404, body: Data(), headers: [:])])
        let error = await controller.next()
        XCTAssertEqual(error, .noActiveDevice)
    }

    func test_rateLimitIsReportedWithRetryAfter() async {
        let (controller, _) = make([
            HTTPResponse(status: 429, body: Data(), headers: ["Retry-After": "3"])
        ])
        let error = await controller.next()
        XCTAssertEqual(error, .rateLimited(retryAfter: 3))
    }

    func test_unauthorizedRefreshesAndRetriesOnce() async {
        let (controller, http) = make(
            [HTTPResponse(status: 401, body: Data(), headers: [:]), Self.ok],
            authResponses: [.json(#"{"access_token":"AT2","expires_in":3600}"#)])

        let error = await controller.play()
        XCTAssertNil(error)
        XCTAssertEqual(http.recordedRequests.count, 2)
        XCTAssertEqual(http.recordedRequests[1].value(forHTTPHeaderField: "Authorization"),
                       "Bearer AT2")
    }

    func test_networkFailureIsReported() async {
        let http = StubHTTPClient()
        http.errorToThrow = AppError.network("offline")
        let auth = SpotifyAuth(clientID: "CID", http: StubHTTPClient(),
                               store: InMemoryTokenStore(token: "RT"))
        auth.setAccessTokenForTesting("AT", expiresIn: 3600)
        let controller = PlaybackController(auth: auth, http: http)
        let error = await controller.play()
        XCTAssertEqual(error, .network("offline"))
    }

    func test_authScopeIncludesPlaybackControl() {
        XCTAssertTrue(SpotifyAuth.scope.contains("user-modify-playback-state"))
        XCTAssertTrue(SpotifyAuth.scope.contains("user-read-playback-state"))
    }
}
