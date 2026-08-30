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
