using System.Globalization;
using System.Text;

namespace FloatingLyric.Core;

/// <summary>
/// Romanizes lyric lines written in non-Latin scripts.
///
/// Windows ships no transliteration engine — macOS gets this free from
/// CoreFoundation's ICU, and Android from android.icu. So the tables below are
/// hand-written, and the coverage is honestly narrower than the Mac build's:
/// kana, Cyrillic and Greek are complete; <b>kanji are not romanized at all</b>,
/// because reading them needs a dictionary and the surrounding words, not a
/// character map. A line still holding kanji after conversion returns null
/// rather than a half-Latin mess.
/// </summary>
public static class Transliteration
{
    public static string? Romanize(string text)
    {
        if (!NeedsRomanization(text)) return null;

        var converted = Convert(text);
        if (converted is null) return null;

        var cleaned = Normalize(converted);
        if (cleaned.Length == 0 || cleaned == text) return null;
        return cleaned;
    }

    /// <summary>True when the line contains a letter outside the Latin blocks.</summary>
    public static bool NeedsRomanization(string text) =>
        text.Any(IsNonLatinLetter);

    private static bool IsNonLatinLetter(char c)
    {
        if (!char.IsLetter(c)) return false;
        return c switch
        {
            <= 'ɏ' => false,                       // Basic Latin … Latin Extended-B
            >= 'ɐ' and <= 'ʯ' => false,       // IPA extensions
            >= 'Ḁ' and <= 'ỿ' => false,       // Latin Extended Additional
            _ => true,
        };
    }

    private static bool IsHan(char c) =>
        (c >= '一' && c <= '鿿') || (c >= '㐀' && c <= '䶿');

    private static string? Convert(string text)
    {
        var sb = new StringBuilder();
        var i = 0;

        while (i < text.Length)
        {
            var c = text[i];

            // Kanji have no single sound; a character map would invent one.
            if (IsHan(c)) return null;

            // っ / ッ doubles the next consonant.
            if (c is 'っ' or 'ッ')
            {
                var next = NextRomaji(text, i + 1);
                if (next is { Length: > 0 } && char.IsLetter(next[0]) && !"aeiou".Contains(next[0]))
                    sb.Append(next[0]);
                i++;
                continue;
            }

            // ー lengthens the previous vowel.
            if (c == 'ー')
            {
                if (sb.Length > 0 && "aeiou".Contains(char.ToLowerInvariant(sb[^1])))
                    sb.Append(sb[^1]);
                i++;
                continue;
            }

            // Two-character kana (きゃ, しゅ …) before single ones.
            if (i + 1 < text.Length &&
                KanaTable.Digraphs.TryGetValue(text.Substring(i, 2), out var digraph))
            {
                sb.Append(digraph);
                i += 2;
                continue;
            }

            if (KanaTable.Single.TryGetValue(c, out var kana)) { sb.Append(kana); i++; continue; }
            if (CyrillicTable.Map.TryGetValue(c, out var cyr)) { sb.Append(cyr); i++; continue; }
            if (GreekTable.Map.TryGetValue(c, out var gr)) { sb.Append(gr); i++; continue; }

            // Anything else non-Latin we cannot read: refuse the whole line
            // rather than emit something half-converted.
            if (IsNonLatinLetter(c)) return null;

            sb.Append(c);
            i++;
        }

        return sb.ToString();
    }

    private static string? NextRomaji(string text, int index)
    {
        if (index >= text.Length) return null;
        if (index + 1 < text.Length &&
            KanaTable.Digraphs.TryGetValue(text.Substring(index, 2), out var digraph))
            return digraph;
        return KanaTable.Single.TryGetValue(text[index], out var single) ? single : null;
    }

    private static string Normalize(string text)
    {
        var collapsed = string.Join(' ',
            text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));

        // Strip accents only if something outside plain Latin survived.
        if (collapsed.All(c => c < 'ɐ')) return collapsed;

        var decomposed = collapsed.Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder();
        foreach (var c in decomposed)
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark)
                sb.Append(c);
        return sb.ToString().Normalize(NormalizationForm.FormC).Trim();
    }
}
