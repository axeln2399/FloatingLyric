import XCTest
@testable import FloatingLyricCore

final class LRCParserTests: XCTestCase {
    func test_parsesWellFormedLines() {
        let raw = """
        [00:12.34]First line
        [00:15.00]Second line
        [01:02.50]Third line
        """
        XCTAssertEqual(LRCParser.parse(raw), [
            LyricLine(timeMs: 12340, text: "First line"),
            LyricLine(timeMs: 15000, text: "Second line"),
            LyricLine(timeMs: 62500, text: "Third line"),
        ])
    }

    func test_parsesThreeDigitMilliseconds() {
        XCTAssertEqual(LRCParser.parse("[00:01.234]Hi"),
                       [LyricLine(timeMs: 1234, text: "Hi")])
    }

    func test_repeatsTextForMultipleTimestampsOnOneLine() {
        let parsed = LRCParser.parse("[00:10.00][00:20.00]Chorus")
        XCTAssertEqual(parsed, [
            LyricLine(timeMs: 10000, text: "Chorus"),
            LyricLine(timeMs: 20000, text: "Chorus"),
        ])
    }

    func test_appliesOffsetTagAndIgnoresOtherMetadata() {
        let raw = """
        [ar:Someone]
        [ti:Some Song]
        [offset:-500]
        [00:10.00]Line
        """
        XCTAssertEqual(LRCParser.parse(raw), [LyricLine(timeMs: 9500, text: "Line")])
    }

    func test_offsetNeverProducesNegativeTimes() {
        let raw = "[offset:-5000]\n[00:01.00]Line"
        XCTAssertEqual(LRCParser.parse(raw), [LyricLine(timeMs: 0, text: "Line")])
    }

    func test_skipsMalformedLines() {
        let raw = """
        not a lyric line
        [garbage]still not
        [00:10.00]Good line
        """
        XCTAssertEqual(LRCParser.parse(raw), [LyricLine(timeMs: 10000, text: "Good line")])
    }

    func test_preservesBlankLyricLinesAsPauses() {
        let raw = "[00:10.00]Line\n[00:14.00]\n[00:18.00]Next"
        XCTAssertEqual(LRCParser.parse(raw), [
            LyricLine(timeMs: 10000, text: "Line"),
            LyricLine(timeMs: 14000, text: ""),
            LyricLine(timeMs: 18000, text: "Next"),
        ])
    }

    func test_sortsUnorderedTimestamps() {
        let raw = "[00:20.00]Second\n[00:10.00]First"
        XCTAssertEqual(LRCParser.parse(raw), [
            LyricLine(timeMs: 10000, text: "First"),
            LyricLine(timeMs: 20000, text: "Second"),
        ])
    }

    func test_emptyInputProducesNoLines() {
        XCTAssertEqual(LRCParser.parse(""), [])
        XCTAssertEqual(LRCParser.parse("   \n  \n"), [])
    }

    func test_trimsWhitespaceAroundText() {
        XCTAssertEqual(LRCParser.parse("[00:10.00]   Line   "),
                       [LyricLine(timeMs: 10000, text: "Line")])
    }
}
