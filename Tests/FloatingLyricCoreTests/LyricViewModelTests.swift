import XCTest
@testable import FloatingLyricCore

@MainActor
final class LyricViewModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Defaults.autoHideChrome = true
        Defaults.showRomaji = true
    }

    override func tearDown() {
        Defaults.autoHideChrome = true
        Defaults.showRomaji = true
        super.tearDown()
    }

    private func makeModel() -> LyricViewModel {
        let model = LyricViewModel()
        model.noteActivity(now: 0)
        return model
    }

    // MARK: - Chrome visibility

    func test_chromeHidesOnceTheWindowHasBeenIdle() {
        let model = makeModel()
        XCTAssertTrue(model.chromeVisible)

        model.refreshChrome(now: 2.9)
        XCTAssertTrue(model.chromeVisible)

        model.refreshChrome(now: 3.1)
        XCTAssertFalse(model.chromeVisible)
    }

    func test_hoveringBringsTheChromeBackAndKeepsIt() {
        let model = makeModel()
        model.refreshChrome(now: 10)
        XCTAssertFalse(model.chromeVisible)

        model.setHovering(true, now: 10)
        XCTAssertTrue(model.chromeVisible)
        model.refreshChrome(now: 300)
        XCTAssertTrue(model.chromeVisible, "hover holds it open however long it lasts")

        model.setHovering(false, now: 300)
        model.refreshChrome(now: 304)
        XCTAssertFalse(model.chromeVisible)
    }

    func test_aNewTrackWakesTheChromeUp() {
        let model = makeModel()
        model.refreshChrome(now: 10)
        XCTAssertFalse(model.chromeVisible)

        model.apply(lyrics: .synced([LyricLine(timeMs: 0, text: "hello")]))
        XCTAssertTrue(model.chromeVisible)
    }

    func test_autoHideCanBeTurnedOff() {
        Defaults.autoHideChrome = false
        let model = makeModel()
        model.refreshChrome(now: 9_999)
        XCTAssertTrue(model.chromeVisible)
    }

    // MARK: - Transport

    func test_playPauseFlipsImmediatelyAndCallsOut() {
        let model = makeModel()
        var calls = 0
        model.onPlayPause = { calls += 1 }

        model.playPauseTapped()
        XCTAssertTrue(model.isPlaying, "the button must not wait for the next poll")
        XCTAssertEqual(calls, 1)

        model.playPauseTapped()
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(calls, 2)
    }

    func test_skipButtonsCallOut() {
        let model = makeModel()
        var next = 0, previous = 0
        model.onNext = { next += 1 }
        model.onPrevious = { previous += 1 }

        model.nextTapped()
        model.previousTapped()
        XCTAssertEqual(next, 1)
        XCTAssertEqual(previous, 1)
    }

    func test_pollingCorrectsTheButtonState() {
        let model = makeModel()
        let track = TrackIdentity(id: "1", title: "T", artist: "A", album: "", durationMs: 1000)
        let np = NowPlaying(track: track, progressMs: 0, isPlaying: true, albumArtURL: nil)

        model.apply(state: .playing(np))
        XCTAssertTrue(model.isPlaying)

        let stopped = NowPlaying(track: track, progressMs: 0, isPlaying: false, albumArtURL: nil)
        model.apply(state: .paused(stopped))
        XCTAssertFalse(model.isPlaying)
    }

    func test_controlErrorIsShownThenClearsItself() {
        let model = makeModel()
        model.report(controlError: .premiumRequired, now: 0)
        XCTAssertEqual(model.controlMessage, AppError.premiumRequired.displayMessage)

        model.refreshChrome(now: 1)
        XCTAssertNotNil(model.controlMessage)

        model.refreshChrome(now: ChromeVisibility.idleTimeout + 0.1)
        XCTAssertNil(model.controlMessage)
    }

    func test_nothingIsPlayingClearsTheTransportState() {
        let model = makeModel()
        model.playPauseTapped()
        XCTAssertTrue(model.isPlaying)

        model.apply(state: .idle)
        XCTAssertFalse(model.isPlaying)
    }

    // MARK: - Romaji

    func test_plainLyricsGainAReadingUnderEachNonLatinLine() {
        let model = makeModel()
        model.apply(lyrics: .plain("こんにちは\nhello"))

        guard case .plain(let text) = model.display else { return XCTFail("expected plain") }
        let lines = text.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 3, "one reading line, and English left alone: \(lines)")
        XCTAssertEqual(lines[0], "こんにちは")
        XCTAssertTrue(lines[1].unicodeScalars.allSatisfy { $0.value < 0x0250 })
        XCTAssertEqual(lines[2], "hello")
    }

    func test_turningRomajiOffRestoresThePlainLyrics() {
        let model = makeModel()
        model.apply(lyrics: .plain("こんにちは"))
        model.setShowRomaji(false)

        guard case .plain(let text) = model.display else { return XCTFail("expected plain") }
        XCTAssertEqual(text, "こんにちは")
    }
}
