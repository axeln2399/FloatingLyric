import XCTest
@testable import FloatingLyricCore

final class PlayheadClockTests: XCTestCase {
    func test_positionAdvancesWithWallClockWhilePlaying() {
        let clock = PlayheadClock()
        clock.anchor(progressMs: 10_000, isPlaying: true, now: 100.0)
        XCTAssertEqual(clock.positionMs(now: 100.0), 10_000)
        XCTAssertEqual(clock.positionMs(now: 102.5), 12_500)
    }

    func test_positionIsFrozenWhilePaused() {
        let clock = PlayheadClock()
        clock.anchor(progressMs: 10_000, isPlaying: false, now: 100.0)
        XCTAssertEqual(clock.positionMs(now: 105.0), 10_000)
    }

    func test_reanchoringResetsPosition() {
        let clock = PlayheadClock()
        clock.anchor(progressMs: 10_000, isPlaying: true, now: 100.0)
        clock.anchor(progressMs: 60_000, isPlaying: true, now: 103.0)
        XCTAssertEqual(clock.positionMs(now: 104.0), 61_000)
    }

    func test_positionNeverGoesNegative() {
        let clock = PlayheadClock()
        clock.anchor(progressMs: 0, isPlaying: true, now: 100.0)
        XCTAssertEqual(clock.positionMs(now: 99.0), 0)
    }

    func test_withoutAnchorPositionIsZero() {
        XCTAssertEqual(PlayheadClock().positionMs(now: 100.0), 0)
    }

    func test_smallDriftIsNotASeek() {
        let clock = PlayheadClock()
        clock.anchor(progressMs: 10_000, isPlaying: true, now: 100.0)
        XCTAssertFalse(clock.isSeek(polledProgressMs: 13_400, now: 103.0))
    }

    func test_driftAtThresholdIsNotASeekButBeyondItIs() {
        let clock = PlayheadClock()
        clock.anchor(progressMs: 10_000, isPlaying: true, now: 100.0)
        XCTAssertFalse(clock.isSeek(polledProgressMs: 14_500, now: 103.0))
        XCTAssertTrue(clock.isSeek(polledProgressMs: 14_501, now: 103.0))
        XCTAssertTrue(clock.isSeek(polledProgressMs: 11_499, now: 103.0))
    }
}
