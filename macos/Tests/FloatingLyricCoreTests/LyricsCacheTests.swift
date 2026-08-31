import XCTest
@testable import FloatingLyricCore

final class LyricsCacheTests: XCTestCase {
    private var directory: URL!
    private var cache: LyricsCache!
    private let now = Date(timeIntervalSince1970: 1_000_000)

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyricsCacheTests-\(UUID().uuidString)")
        cache = LyricsCache(directory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func test_roundTripsSyncedLyrics() {
        let lines = [LyricLine(timeMs: 0, text: "one"), LyricLine(timeMs: 900, text: "two")]
        cache.write(.synced(lines), trackID: "t1", now: now)
        XCTAssertEqual(cache.read(trackID: "t1", now: now), .synced(lines))
    }

    func test_removeSendsTheNextLookupBackToTheNetwork() {
        cache.write(.notFound, trackID: "t1", now: now)
        XCTAssertEqual(cache.read(trackID: "t1", now: now), .notFound)

        cache.remove(trackID: "t1")
        XCTAssertNil(cache.read(trackID: "t1", now: now),
                     "Refetch Lyrics has to beat the 24-hour negative cache")
    }

    func test_removingSomethingThatWasNeverThereIsHarmless() {
        cache.remove(trackID: "never-cached")
    }

    func test_aNotFoundExpiresButLyricsDoNot() {
        cache.write(.notFound, trackID: "missing", now: now)
        cache.write(.plain("words"), trackID: "found", now: now)

        let later = now.addingTimeInterval(LyricsProvider.negativeTTL + 1)
        XCTAssertNil(cache.read(trackID: "missing", now: later))
        XCTAssertEqual(cache.read(trackID: "found", now: later), .plain("words"),
                       "lyrics do not change, so they never expire")
    }

    /// Spotify IDs are safe, but the cache must not be one odd ID away from
    /// writing outside its own directory.
    func test_aTrackIDWithASlashStaysInsideTheCacheDirectory() {
        cache.write(.plain("x"), trackID: "a/b", now: now)
        XCTAssertEqual(cache.read(trackID: "a/b", now: now), .plain("x"))

        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        XCTAssertEqual(files, ["a_b.json"])
    }
}
