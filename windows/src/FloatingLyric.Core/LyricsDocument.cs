namespace FloatingLyric.Core;

public sealed class LyricsDocument
{
    public IReadOnlyList<LyricLine> Lines { get; }

    /// <summary>
    /// A Latin reading per line, null where none is needed. Built once here
    /// rather than in the view, which redraws ten times a second.
    /// </summary>
    private readonly string?[] _romanizations;

    public LyricsDocument(IReadOnlyList<LyricLine> lines)
    {
        Lines = lines;
        _romanizations = lines.Select(l => Transliteration.Romanize(l.Text)).ToArray();
    }

    public string? RomanizationAt(int index) =>
        index >= 0 && index < _romanizations.Length ? _romanizations[index] : null;

    public bool HasRomanizations => _romanizations.Any(r => r is not null);

    /// <summary>
    /// Index of the last line at or before position + offset, or null when the
    /// song has not reached the first line yet. Binary search: this runs at
    /// 10 Hz.
    /// </summary>
    public int? IndexAt(int positionMs, int offsetMs)
    {
        if (Lines.Count == 0) return null;
        var target = positionMs + offsetMs;
        if (target < Lines[0].TimeMs) return null;

        int low = 0, high = Lines.Count - 1, answer = 0;
        while (low <= high)
        {
            var mid = (low + high) / 2;
            if (Lines[mid].TimeMs <= target) { answer = mid; low = mid + 1; }
            else high = mid - 1;
        }
        return answer;
    }
}
