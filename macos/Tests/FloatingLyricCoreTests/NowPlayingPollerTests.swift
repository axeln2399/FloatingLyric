import XCTest
@testable import FloatingLyricCore

final class NowPlayingPollerTests: XCTestCase {
    /// `authResponses` feeds the auth client's own refresh calls, which is what a
    /// 401 retry depends on.
    private func makePoller(_ responses: [HTTPResponse],
                            authResponses: [HTTPResponse] = [])
    -> (NowPlayingPoller, StubHTTPClient) {
        let http = StubHTTPClient()
        http.responses = responses
        let authHTTP = StubHTTPClient()
        authHTTP.responses = authResponses
        let auth = SpotifyAuth(clientID: "CID", http: authHTTP,
                               store: InMemoryTokenStore(token: "RT"))
        auth.setAccessTokenForTesting("AT", expiresIn: 3600)
        return (NowPlayingPoller(auth: auth, http: http), http)
    }

    private static let playingJSON = """
    {"is_playing":true,"progress_ms":42000,
     "item":{"id":"track1","name":"Blinding Lights","duration_ms":200040,
             "artists":[{"name":"The Weeknd"},{"name":"Someone Else"}],
             "album":{"name":"After Hours","images":[{"url":"https://img/1.jpg"}]}}}
    """

    func test_parsesPlayingTrack() async {
        let (poller, _) = makePoller([.json(Self.playingJSON)])
        guard case .playing(let np) = await poller.pollOnce() else {
            return XCTFail("expected .playing")
        }
        XCTAssertEqual(np.track.id, "track1")
        XCTAssertEqual(np.track.title, "Blinding Lights")
        XCTAssertEqual(np.track.artist, "The Weeknd")
        XCTAssertEqual(np.track.album, "After Hours")
        XCTAssertEqual(np.track.durationMs, 200040)
        XCTAssertEqual(np.progressMs, 42000)
        XCTAssertEqual(np.albumArtURL?.absoluteString, "https://img/1.jpg")
    }

    func test_isPlayingFalseYieldsPausedState() async {
        let json = Self.playingJSON.replacingOccurrences(of: "\"is_playing\":true",
                                                         with: "\"is_playing\":false")
        let (poller, _) = makePoller([.json(json)])
        guard case .paused = await poller.pollOnce() else { return XCTFail("expected .paused") }
    }

    func test_noContentYieldsIdle() async {
        let (poller, _) = makePoller([HTTPResponse(status: 204, body: Data(), headers: [:])])
        let state = await poller.pollOnce()
        XCTAssertEqual(state, .idle)
    }

    func test_nullItemYieldsIdle() async {
        let (poller, _) = makePoller([.json(#"{"is_playing":false,"item":null}"#)])
        let state = await poller.pollOnce()
        XCTAssertEqual(state, .idle)
    }

    func test_episodesWithoutTrackFieldsYieldIdle() async {
        let (poller, _) = makePoller([.json(#"{"is_playing":true,"progress_ms":1,"item":{"id":"e1"}}"#)])
        let state = await poller.pollOnce()
        XCTAssertEqual(state, .idle)
    }

    func test_rateLimitReportsRetryAfter() async {
        let (poller, _) = makePoller([
            HTTPResponse(status: 429, body: Data("{}".utf8), headers: ["Retry-After": "7"])
        ])
        let state = await poller.pollOnce()
        XCTAssertEqual(state, .failed(.rateLimited(retryAfter: 7)))
    }

    /// Spotify's real 429 carries no body, which is exactly the case that
    /// used to be misread as "nothing playing".
    func test_rateLimitWithAnEmptyBodyIsStillARateLimit() async {
        let (poller, _) = makePoller([
            HTTPResponse(status: 429, body: Data(), headers: ["Retry-After": "7"])
        ])
        let state = await poller.pollOnce()
        XCTAssertEqual(state, .failed(.rateLimited(retryAfter: 7)))
    }

    func test_aServerErrorWithNoBodyIsNotMistakenForSilence() async {
        let (poller, _) = makePoller([HTTPResponse(status: 502, body: Data(), headers: [:])])
        let state = await poller.pollOnce()
        XCTAssertEqual(state, .failed(.badResponse(status: 502)))
    }

    func test_unauthorizedRefreshesThenRetriesAndSucceeds() async {
        let (poller, http) = makePoller(
            [HTTPResponse(status: 401, body: Data("{}".utf8), headers: [:]),
             .json(Self.playingJSON)],
            authResponses: [.json(#"{"access_token":"AT2","expires_in":3600}"#)])

        let state = await poller.pollOnce()

        XCTAssertEqual(http.recordedRequests.count, 2, "one original call plus one retry")
        XCTAssertEqual(http.recordedRequests[1].value(forHTTPHeaderField: "Authorization"),
                       "Bearer AT2", "the retry must use the refreshed token")
        guard case .playing = state else { return XCTFail("expected .playing after retry") }
    }

    func test_unauthorizedTwiceReportsSessionExpiredAndRetriesOnlyOnce() async {
        let (poller, http) = makePoller(
            [HTTPResponse(status: 401, body: Data("{}".utf8), headers: [:]),
             HTTPResponse(status: 401, body: Data("{}".utf8), headers: [:])],
            authResponses: [.json(#"{"access_token":"AT2","expires_in":3600}"#)])

        let state = await poller.pollOnce()

        XCTAssertEqual(http.recordedRequests.count, 2, "must not retry more than once")
        XCTAssertEqual(state, .failed(.sessionExpired))
    }

    func test_unauthorizedWithAFailedRefreshReportsSessionExpiredWithoutRetrying() async {
        let (poller, http) = makePoller(
            [HTTPResponse(status: 401, body: Data("{}".utf8), headers: [:])],
            authResponses: [.json(#"{"error":"invalid_grant"}"#, status: 400)])

        let state = await poller.pollOnce()

        XCTAssertEqual(http.recordedRequests.count, 1, "no point retrying without a token")
        XCTAssertEqual(state, .failed(.sessionExpired))
    }

    func test_networkErrorIsReported() async {
        let http = StubHTTPClient()
        http.errorToThrow = AppError.network("offline")
        let auth = SpotifyAuth(clientID: "CID", http: StubHTTPClient(),
                               store: InMemoryTokenStore(token: "RT"))
        auth.setAccessTokenForTesting("AT", expiresIn: 3600)
        let poller = NowPlayingPoller(auth: auth, http: http)
        let state = await poller.pollOnce()
        XCTAssertEqual(state, .failed(.network("offline")))
    }

    func test_requestCarriesBearerToken() async {
        let (poller, http) = makePoller([.json(Self.playingJSON)])
        _ = await poller.pollOnce()
        XCTAssertEqual(http.recordedRequests.first?.value(forHTTPHeaderField: "Authorization"),
                       "Bearer AT")
        XCTAssertEqual(http.recordedRequests.first?.url?.path,
                       "/v1/me/player/currently-playing")
    }

    func test_pollIntervalIsShorterWhilePlaying() {
        XCTAssertEqual(NowPlayingPoller.intervalMs(for: .idle), 10_000)
        XCTAssertEqual(NowPlayingPoller.intervalMs(for: .failed(.network("x"))), 10_000)
        let np = NowPlaying(track: TrackIdentity(id: "t", title: "a", artist: "b",
                                                 album: "c", durationMs: 1),
                            progressMs: 0, isPlaying: true, albumArtURL: nil)
        XCTAssertEqual(NowPlayingPoller.intervalMs(for: .playing(np)), 3_000)
        XCTAssertEqual(NowPlayingPoller.intervalMs(for: .paused(np)), 10_000)
    }
}
