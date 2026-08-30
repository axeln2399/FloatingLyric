import Foundation

/// Romanizes lyric lines written in non-Latin scripts, so a Japanese, Korean,
/// Chinese or Cyrillic line can be sung along to.
public enum Transliteration {
    /// Returns a Latin reading of `text`, or nil when the line is already
    /// readable (Latin script, punctuation, or numbers only).
    public static func romanize(_ text: String) -> String? {
        guard needsRomanization(text) else { return nil }

        // Kanji have no single "sound" — only the tokenizer knows that 名 is
        // "na" here and "mei" elsewhere, so it gets first refusal.
        if let transcribed = tokenizerTranscription(text) {
            let cleaned = normalized(transcribed)
            if !cleaned.isEmpty, cleaned != text { return cleaned }
        }

        // Everything else (Hangul, Cyrillic, Greek, Thai …) romanizes fine with
        // a plain ICU transform.
        if let transformed = transformToLatin(text) {
            let cleaned = normalized(transformed)
            if !cleaned.isEmpty, cleaned != text { return cleaned }
        }

        return nil
    }

    /// True when the line contains a letter outside the Latin blocks.
    public static func needsRomanization(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isNonLatinLetter)
    }

    private static func isNonLatinLetter(_ scalar: Unicode.Scalar) -> Bool {
        guard scalar.properties.isAlphabetic else { return false }
        switch scalar.value {
        case 0x0000...0x024F:   return false   // Basic Latin … Latin Extended-B
        case 0x0250...0x02AF:   return false   // IPA extensions
        case 0x1E00...0x1EFF:   return false   // Latin Extended Additional
        default:                return true
        }
    }

    private static func tokenizerTranscription(_ text: String) -> String? {
        let cf = text as CFString
        let range = CFRangeMake(0, CFStringGetLength(cf))

        // Reading kanji correctly depends on the language, so ask ICU which one
        // this line is rather than assuming Japanese.
        var locale: CFLocale?
        if let language = CFStringTokenizerCopyBestStringLanguage(cf, range) as String? {
            locale = NSLocale(localeIdentifier: language) as CFLocale
        }

        let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault, cf, range, kCFStringTokenizerUnitWordBoundary, locale)

        var pieces: [String] = []
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let tokenRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let original = substring(of: text, cfRange: tokenRange)

            if let latin = CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String,
               !latin.isEmpty {
                pieces.append(latin)
            } else if let original, !original.isEmpty {
                // Words already in Latin script carry no transcription; keep them.
                pieces.append(original)
            }
        }

        guard !pieces.isEmpty else { return nil }
        return pieces.joined(separator: " ")
    }

    private static func transformToLatin(_ text: String) -> String? {
        let mutable = NSMutableString(string: text)
        guard CFStringTransform(mutable, nil, kCFStringTransformToLatin, false) else { return nil }
        return mutable as String
    }

    /// Collapses whitespace and guarantees the result is plain Latin, stripping
    /// combining accents only when something outside the Latin blocks survives.
    private static func normalized(_ text: String) -> String {
        let precomposed = text.precomposedStringWithCanonicalMapping
        let collapsed = precomposed
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if collapsed.unicodeScalars.allSatisfy({ $0.value < 0x0250 }) { return collapsed }

        let mutable = NSMutableString(string: collapsed)
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
        return (mutable as String).trimmingCharacters(in: .whitespaces)
    }

    private static func substring(of text: String, cfRange: CFRange) -> String? {
        guard cfRange.location >= 0, cfRange.length > 0 else { return nil }
        let ns = text as NSString
        let location = cfRange.location
        let length = cfRange.length
        guard location + length <= ns.length else { return nil }
        return ns.substring(with: NSRange(location: location, length: length))
    }
}
