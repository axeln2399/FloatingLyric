using System.Text.RegularExpressions;

namespace FloatingLyric.Core;

/// <summary>Turns an .lrc file into timed lines. A port of LRCParser.swift.</summary>
public static partial class LrcParser
{
    [GeneratedRegex(@"^\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]")]
    private static partial Regex Timestamp();

    [GeneratedRegex(@"^\[offset:\s*([+-]?\d+)\s*\]$", RegexOptions.IgnoreCase)]
    private static partial Regex OffsetTag();

    public static IReadOnlyList<LyricLine> Parse(string raw)
    {
        var offsetMs = 0;
        var lines = new List<LyricLine>();

        foreach (var rawLine in raw.Split('\n', '\r'))
        {
            var line = rawLine.Trim();
            if (line.Length == 0) continue;

            var offsetMatch = OffsetTag().Match(line);
            if (offsetMatch.Success)
            {
                offsetMs = int.Parse(offsetMatch.Groups[1].Value);
                continue;
            }

            var rest = line;
            var times = new List<int>();
            while (TakeTimestamp(ref rest) is { } time) times.Add(time);
            if (times.Count == 0) continue;

            var text = rest.Trim();
            foreach (var time in times)
                lines.Add(new LyricLine(Math.Max(0, time + offsetMs), text));
        }

        // Never assume the file is ordered.
        return lines.OrderBy(l => l.TimeMs).ToList();
    }

    private static int? TakeTimestamp(ref string rest)
    {
        var match = Timestamp().Match(rest);
        if (!match.Success) return null;

        var minutes = int.Parse(match.Groups[1].Value);
        var seconds = int.Parse(match.Groups[2].Value);

        var fraction = 0;
        if (match.Groups[3].Success)
        {
            // Left-aligned: "5" and "50" and "500" all mean 500 ms.
            var digits = match.Groups[3].Value.PadRight(3, '0');
            fraction = int.Parse(digits);
        }

        rest = rest[match.Length..];
        return minutes * 60_000 + seconds * 1_000 + fraction;
    }
}
