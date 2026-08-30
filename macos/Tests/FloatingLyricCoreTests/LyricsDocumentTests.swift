import XCTest
@testable import FloatingLyricCore

final class LyricsDocumentTests: XCTestCase {
    private let doc = LyricsDocument(lines: [
        LyricLine(timeMs: 1000, text: "one"),
        LyricLine(timeMs: 2000, text: "two"),
        LyricLine(timeMs: 3000, text: "three"),
    ])

    func test_exactlyOnATimestampSelectsThatLine() {
        XCTAssertEqual(doc.index(atPositionMs: 2000, offsetMs: 0), 1)
    }

    func test_betweenTimestampsSelectsTheEarlierLine() {
        XCTAssertEqual(doc.index(atPositionMs: 2500, offsetMs: 0), 1)
    }

    func test_beforeFirstTimestampSelectsNothing() {
        XCTAssertNil(doc.index(atPositionMs: 0, offsetMs: 0))
        XCTAssertNil(doc.index(atPositionMs: 999, offsetMs: 0))
    }

    func test_afterLastTimestampSelectsLastLine() {
        XCTAssertEqual(doc.index(atPositionMs: 99_000, offsetMs: 0), 2)
    }

    func test_positiveOffsetAdvancesSelection() {
        XCTAssertEqual(doc.index(atPositionMs: 1800, offsetMs: 500), 1)
    }

    func test_negativeOffsetDelaysSelection() {
        XCTAssertEqual(doc.index(atPositionMs: 2100, offsetMs: -500), 0)
    }

    func test_offsetPushingBeforeStartSelectsNothing() {
        XCTAssertNil(doc.index(atPositionMs: 1200, offsetMs: -500))
    }

    func test_emptyDocumentSelectsNothing() {
        XCTAssertNil(LyricsDocument(lines: []).index(atPositionMs: 5000, offsetMs: 0))
    }

    func test_singleLineDocument() {
        let single = LyricsDocument(lines: [LyricLine(timeMs: 500, text: "only")])
        XCTAssertNil(single.index(atPositionMs: 400, offsetMs: 0))
        XCTAssertEqual(single.index(atPositionMs: 500, offsetMs: 0), 0)
        XCTAssertEqual(single.index(atPositionMs: 900_000, offsetMs: 0), 0)
    }
}

final class LyricsDocumentRomanizationTests: XCTestCase {
    func test_everyNonLatinLineGetsAReading() {
        let doc = LyricsDocument(lines: [
            LyricLine(timeMs: 0, text: "こんにちは"),
            LyricLine(timeMs: 1000, text: "hello there"),
        ])
        XCTAssertNotNil(doc.romanization(at: 0))
        XCTAssertTrue(doc.romanization(at: 0)!.unicodeScalars.allSatisfy { $0.value < 0x0250 })
        XCTAssertNil(doc.romanization(at: 1), "Latin lines need no reading")
        XCTAssertTrue(doc.hasRomanizations)
    }

    func test_anEnglishSongHasNoReadingsAtAll() {
        let doc = LyricsDocument(lines: [
            LyricLine(timeMs: 0, text: "Blinding lights"),
            LyricLine(timeMs: 1000, text: "I said ooh"),
        ])
        XCTAssertFalse(doc.hasRomanizations)
    }

    /// Readings are built on the main thread as a track starts, so a long song
    /// in a heavy script must not cost a visible pause.
    func test_readingsForALongSongAreCheapEnoughForTheMainThread() {
        let lines = (0..<80).map { LyricLine(timeMs: $0 * 1000, text: "君の名は僕の心に残っている") }
        let start = Date()
        let doc = LyricsDocument(lines: lines)
        XCTAssertTrue(doc.hasRomanizations)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.2)
    }

    func test_indexesOutsideTheDocumentReturnNoReading() {
        let doc = LyricsDocument(lines: [LyricLine(timeMs: 0, text: "こんにちは")])
        XCTAssertNil(doc.romanization(at: -1))
        XCTAssertNil(doc.romanization(at: 99))
    }
}
