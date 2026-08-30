import XCTest
@testable import FloatingLyricCore

final class TransliterationTests: XCTestCase {
    private func isLatinish(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy { $0.value < 0x0250 }
    }

    // MARK: - When romanization is not wanted

    func test_plainEnglishNeedsNoRomanization() {
        XCTAssertNil(Transliteration.romanize("Blinding Lights"))
        XCTAssertNil(Transliteration.romanize("I'm going through withdrawals"))
    }

    func test_accentedLatinNeedsNoRomanization() {
        XCTAssertNil(Transliteration.romanize("Café déjà vu"))
        XCTAssertNil(Transliteration.romanize("Björk Guðmundsdóttir"))
    }

    func test_emptyAndPunctuationOnlyLinesAreSkipped() {
        XCTAssertNil(Transliteration.romanize(""))
        XCTAssertNil(Transliteration.romanize("   "))
        XCTAssertNil(Transliteration.romanize("♪ ♪ ♪"))
        XCTAssertNil(Transliteration.romanize("- - -"))
        XCTAssertNil(Transliteration.romanize("123 456"))
    }

    // MARK: - Japanese

    func test_hiraganaIsRomanized() {
        let result = Transliteration.romanize("こんにちは")
        XCTAssertNotNil(result)
        XCTAssertTrue(isLatinish(result ?? ""), "got: \(result ?? "nil")")
    }

    func test_katakanaIsRomanized() {
        let result = Transliteration.romanize("カタカナ")
        XCTAssertNotNil(result)
        XCTAssertTrue(isLatinish(result ?? ""), "got: \(result ?? "nil")")
    }

    func test_kanjiIsRomanized() {
        let result = Transliteration.romanize("君の名は")
        XCTAssertNotNil(result)
        XCTAssertTrue(isLatinish(result ?? ""), "got: \(result ?? "nil")")
    }

    func test_mixedJapaneseAndLatinIsRomanized() {
        let result = Transliteration.romanize("君の name は")
        XCTAssertNotNil(result)
        XCTAssertTrue(isLatinish(result ?? ""), "got: \(result ?? "nil")")
    }

    // MARK: - Other scripts

    func test_koreanIsRomanized() {
        let result = Transliteration.romanize("안녕하세요")
        XCTAssertNotNil(result)
        XCTAssertTrue(isLatinish(result ?? ""), "got: \(result ?? "nil")")
    }

    func test_cyrillicIsRomanized() {
        let result = Transliteration.romanize("Привет мир")
        XCTAssertNotNil(result)
        XCTAssertTrue(isLatinish(result ?? ""), "got: \(result ?? "nil")")
    }

    func test_chineseIsRomanized() {
        let result = Transliteration.romanize("你好世界")
        XCTAssertNotNil(result)
        XCTAssertTrue(isLatinish(result ?? ""), "got: \(result ?? "nil")")
    }

    // MARK: - Contract

    func test_resultNeverEqualsTheInput() {
        for text in ["こんにちは", "안녕하세요", "Привет"] {
            XCTAssertNotEqual(Transliteration.romanize(text), text)
        }
    }

    func test_resultIsTrimmedAndNeverBlank() {
        for text in ["こんにちは", "君の名は", "안녕하세요"] {
            let result = Transliteration.romanize(text) ?? ""
            XCTAssertEqual(result, result.trimmingCharacters(in: .whitespaces))
            XCTAssertFalse(result.isEmpty)
        }
    }

    func test_isRepeatable() {
        XCTAssertEqual(Transliteration.romanize("こんにちは"),
                       Transliteration.romanize("こんにちは"))
    }
}

