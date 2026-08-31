import XCTest
@testable import FloatingLyricCore

final class LyricsProviderTests: XCTestCase {
    private let track = TrackIdentity(id: "t1", title: "Blinding Lights",
                                      artist: "The Weeknd", album: "After Hours",
                                      durationMs: 200_040)

    private final class MemoryCache: LyricsCaching, @unchecked Sendable {
        var stored: [String: (LyricsResult, Date)] = [:]
        func read(trackID: String, now: Date) -> LyricsResult? {
            guard let (result, date) = stored[trackID] else { return nil }
            if result == .notFound,
               now.timeIntervalSince(date) > LyricsProvider.negativeTTL { return nil }
            return result
        }
        func write(_ result: LyricsResult, trackID: String, now: Date) {
            stored[trackID] = (result, now)
        }
        func remove(trackID: String) { stored[trackID] = nil }
    }

    private func makeProvider(_ responses: [HTTPResponse],
                              cache: MemoryCache = MemoryCache(),
                              now: @escaping () -> Date = { Date(timeIntervalSince1970: 0) })
    -> (LyricsProvider, StubHTTPClient, MemoryCache) {
        let http = StubHTTPClient()
        http.responses = responses
        return (LyricsProvider(http: http, cache: cache, now: now), http, cache)
    }

    func test_returnsSyncedLyricsFromDirectLookup() async {
        let json = #"{"syncedLyrics":"[00:10.00]Hello","plainLyrics":"Hello"}"#
        let (provider, http, _) = makeProvider([.json(json)])

        let result = await provider.lyrics(for: track)

        XCTAssertEqual(result, .synced([LyricLine(timeMs: 10_000, text: "Hello")]))
        let url = http.recordedRequests[0].url!
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        func value(_ n: String) -> String? { items.first { $0.name == n }?.value }
        XCTAssertEqual(url.host, "lrclib.net")
        XCTAssertEqual(url.path, "/api/get")
        XCTAssertEqual(value("artist_name"), "The Weeknd")
        XCTAssertEqual(value("track_name"), "Blinding Lights")
        XCTAssertEqual(value("album_name"), "After Hours")
        XCTAssertEqual(value("duration"), "200", "duration must be whole seconds")
    }

    // MARK: - Choosing among search results

    private func record(duration: Double?, synced: Bool = true,
                        artist: String = "The Weeknd",
                        title: String = "Blinding Lights") -> LyricsProvider.Record {
        LyricsProvider.Record(
            duration: duration,
            syncedLyrics: synced ? "[00:10.00]Line" : nil,
            plainLyrics: "Line",
            artistName: artist,
            trackName: title)
    }

    /// track is 200.04 s.
    func test_anExactDurationMatchWins() {
        let best = LyricsProvider.bestMatch(for: track, in: [
            record(duration: 186), record(duration: 201), record(duration: 260),
        ])
        XCTAssertEqual(best?.duration, 201)
    }

    func test_fallsBackToALooserDurationRatherThanGivingUp() {
        // Nothing within 5 s; 188 is within 15 s. The old code returned nothing
        // here, which is the bug this covers.
        let best = LyricsProvider.bestMatch(for: track, in: [
            record(duration: 188), record(duration: 260),
        ])
        XCTAssertEqual(best?.duration, 188)
    }

    func test_takesTheSameSongAtAnyLengthWhenNothingElseIsClose() {
        let best = LyricsProvider.bestMatch(for: track, in: [
            record(duration: 254), record(duration: 300),
        ])
        XCTAssertEqual(best?.duration, 254, "closest of the same song")
    }

    func test_recordsWithNoDurationAreStillUsable() {
        let best = LyricsProvider.bestMatch(for: track, in: [record(duration: nil)])
        XCTAssertNotNil(best, "a missing duration is not a reason to show nothing")
    }

    /// The widest tier is name-matched, so a search that drags in another
    /// artist's song never wins by accident.
    func test_aDifferentSongIsNeverAcceptedAtTheWidestTier() {
        let best = LyricsProvider.bestMatch(for: track, in: [
            record(duration: 400, artist: "Someone Else", title: "Other Song"),
            record(duration: nil, artist: "Someone Else", title: "Other Song"),
        ])
        XCTAssertNil(best)
    }

    func test_syncedBeatsPlainWithinTheSameTier() {
        let best = LyricsProvider.bestMatch(for: track, in: [
            record(duration: 200, synced: false),
            record(duration: 203, synced: true),
        ])
        XCTAssertEqual(best?.duration, 203)
    }

    func test_namesAreComparedIgnoringCaseAndAccents() {
        let best = LyricsProvider.bestMatch(for: track, in: [
            record(duration: 400, artist: "the wéeknd", title: "BLINDING LIGHTS"),
        ])
        XCTAssertNotNil(best)
    }

    func test_emptyRecordsAreIgnored() {
        let empty = LyricsProvider.Record(duration: 200, syncedLyrics: nil,
                                          plainLyrics: nil, artistName: "The Weeknd",
                                          trackName: "Blinding Lights")
        XCTAssertNil(LyricsProvider.bestMatch(for: track, in: [empty]))
    }

    /// End to end through the HTTP path: /api/get misses, and search returns
    /// only entries the old ±5 s rule would have thrown away.
    func test_searchRescuesATrackWhoseDurationsAllDisagree() async {
        let miss = HTTPResponse(status: 404, body: Data(), headers: [:])
        let results = #"""
        [{"duration":186.0,"syncedLyrics":"[00:12.00]Found","plainLyrics":"Found",
          "artistName":"The Weeknd","trackName":"Blinding Lights"},
         {"duration":260.0,"syncedLyrics":"[00:12.00]Other","plainLyrics":"Other",
          "artistName":"The Weeknd","trackName":"Blinding Lights"}]
        """#
        let (provider, _, _) = makeProvider([miss, .json(results)])

        let result = await provider.lyrics(for: track)

        XCTAssertEqual(result, .synced([LyricLine(timeMs: 12_000, text: "Found")]))
    }

    func test_refetchingDropsWhatWasCached() async {
        let cache = MemoryCache()
        cache.write(.notFound, trackID: track.id, now: Date(timeIntervalSince1970: 0))
        XCTAssertNotNil(cache.read(trackID: track.id, now: Date(timeIntervalSince1970: 0)))

        cache.remove(trackID: track.id)
        XCTAssertNil(cache.read(trackID: track.id, now: Date(timeIntervalSince1970: 0)))
    }

    func test_sendsRequiredUserAgent() async {
        let (provider, http, _) = makeProvider([.json(#"{"syncedLyrics":"[00:01.00]x"}"#)])
        _ = await provider.lyrics(for: track)
        XCTAssertEqual(http.recordedRequests[0].value(forHTTPHeaderField: "User-Agent"),
                       "FloatingLyric/1.0 (macOS lyrics overlay; contact via app repository)")
    }

    func test_fallsBackToPlainLyricsWhenSyncedIsNull() async {
        let (provider, _, _) = makeProvider([.json(#"{"syncedLyrics":null,"plainLyrics":"Just words"}"#)])
        let result = await provider.lyrics(for: track)
        XCTAssertEqual(result, .plain("Just words"))
    }

    func test_emptySyncedStringIsTreatedAsMissing() async {
        let (provider, _, _) = makeProvider([.json(#"{"syncedLyrics":"","plainLyrics":"Words"}"#)])
        let result = await provider.lyrics(for: track)
        XCTAssertEqual(result, .plain("Words"))
    }

    func test_notFoundOnDirectLookupFallsBackToSearch() async {
        let searchJSON = """
        [{"duration":198.5,"syncedLyrics":"[00:05.00]From search","plainLyrics":"From search"}]
        """
        let (provider, http, _) = makeProvider([
            HTTPResponse(status: 404, body: Data(), headers: [:]),
            .json(searchJSON),
        ])

        let result = await provider.lyrics(for: track)

        XCTAssertEqual(result, .synced([LyricLine(timeMs: 5_000, text: "From search")]))
        XCTAssertEqual(http.recordedRequests[1].url?.path, "/api/search")
    }

    func test_searchResultOutsideDurationToleranceIsRejected() async {
        let searchJSON = """
        [{"duration":150.0,"syncedLyrics":"[00:05.00]Wrong song","plainLyrics":"Wrong"}]
        """
        let (provider, _, _) = makeProvider([
            HTTPResponse(status: 404, body: Data(), headers: [:]),
            .json(searchJSON),
        ])
        let result = await provider.lyrics(for: track)
        XCTAssertEqual(result, .notFound)
    }

    func test_searchPicksFirstResultWithinTolerance() async {
        let searchJSON = """
        [{"duration":120.0,"syncedLyrics":"[00:05.00]Wrong","plainLyrics":"w"},
         {"duration":204.0,"syncedLyrics":"[00:05.00]Right","plainLyrics":"r"}]
        """
        let (provider, _, _) = makeProvider([
            HTTPResponse(status: 404, body: Data(), headers: [:]),
            .json(searchJSON),
        ])
        let result = await provider.lyrics(for: track)
        XCTAssertEqual(result, .synced([LyricLine(timeMs: 5_000, text: "Right")]))
    }

    func test_emptySearchResultsYieldNotFound() async {
        let (provider, _, _) = makeProvider([
            HTTPResponse(status: 404, body: Data(), headers: [:]),
            .json("[]"),
        ])
        let result = await provider.lyrics(for: track)
        XCTAssertEqual(result, .notFound)
    }

    func test_networkErrorYieldsNotFoundAndIsNotCached() async {
        let http = StubHTTPClient()
        http.errorToThrow = AppError.network("offline")
        let cache = MemoryCache()
        let provider = LyricsProvider(http: http, cache: cache,
                                      now: { Date(timeIntervalSince1970: 0) })
        let result = await provider.lyrics(for: track)
        XCTAssertEqual(result, .notFound)
        XCTAssertTrue(cache.stored.isEmpty, "transient failures must not poison the cache")
    }

    func test_cacheHitSkipsTheNetwork() async {
        let cache = MemoryCache()
        cache.stored["t1"] = (.synced([LyricLine(timeMs: 1, text: "cached")]),
                              Date(timeIntervalSince1970: 0))
        let (provider, http, _) = makeProvider([], cache: cache)

        let result = await provider.lyrics(for: track)
        XCTAssertEqual(result, .synced([LyricLine(timeMs: 1, text: "cached")]))
        XCTAssertTrue(http.recordedRequests.isEmpty)
    }

    func test_successfulLookupIsWrittenToCache() async {
        let cache = MemoryCache()
        let (provider, _, _) = makeProvider([.json(#"{"syncedLyrics":"[00:10.00]Hello"}"#)],
                                            cache: cache)
        _ = await provider.lyrics(for: track)
        XCTAssertEqual(cache.stored["t1"]?.0, .synced([LyricLine(timeMs: 10_000, text: "Hello")]))
    }

    func test_notFoundIsCachedAndExpiresAfterTwentyFourHours() async {
        var now = Date(timeIntervalSince1970: 0)
        let cache = MemoryCache()
        let http = StubHTTPClient()
        http.responses = [HTTPResponse(status: 404, body: Data(), headers: [:]), .json("[]")]
        let provider = LyricsProvider(http: http, cache: cache, now: { now })

        let first = await provider.lyrics(for: track)
        XCTAssertEqual(first, .notFound)
        XCTAssertEqual(cache.stored["t1"]?.0, .notFound)

        now = Date(timeIntervalSince1970: 3600)
        _ = await provider.lyrics(for: track)
        XCTAssertEqual(http.recordedRequests.count, 2, "still inside the TTL: served from cache")

        now = Date(timeIntervalSince1970: 86_401)
        http.responses = [.json(#"{"syncedLyrics":"[00:02.00]Now here"}"#)]
        let refetched = await provider.lyrics(for: track)
        XCTAssertEqual(refetched, .synced([LyricLine(timeMs: 2_000, text: "Now here")]))
    }

    func test_diskCacheRoundTripsThroughAFileURL() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let cache = LyricsCache(directory: dir)
        let now = Date(timeIntervalSince1970: 500)
        let value = LyricsResult.synced([LyricLine(timeMs: 7, text: "disk")])

        cache.write(value, trackID: "abc", now: now)
        XCTAssertEqual(cache.read(trackID: "abc", now: now), value)
        XCTAssertNil(cache.read(trackID: "missing", now: now))
        try? FileManager.default.removeItem(at: dir)
    }

    func test_diskCacheExpiresNegativeEntries() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let cache = LyricsCache(directory: dir)
        let start = Date(timeIntervalSince1970: 0)

        cache.write(.notFound, trackID: "abc", now: start)
        XCTAssertEqual(cache.read(trackID: "abc", now: start.addingTimeInterval(3600)), .notFound)
        XCTAssertNil(cache.read(trackID: "abc", now: start.addingTimeInterval(86_401)))
        try? FileManager.default.removeItem(at: dir)
    }
}
