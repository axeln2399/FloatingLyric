import Foundation

public enum LRCParser {
    /// Matches one `[mm:ss.xx]` or `[mm:ss]` timestamp at the head of the remaining text.
    private static let timestamp = try! NSRegularExpression(
        pattern: #"^\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#)
    private static let offsetTag = try! NSRegularExpression(
        pattern: #"^\[offset:\s*([+-]?\d+)\s*\]$"#, options: .caseInsensitive)

    public static func parse(_ raw: String) -> [LyricLine] {
        var offsetMs = 0
        var lines: [LyricLine] = []

        for rawLine in raw.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if let offset = parseOffset(line) {
                offsetMs = offset
                continue
            }

            var rest = Substring(line)
            var times: [Int] = []
            while let time = takeTimestamp(&rest) { times.append(time) }
            guard !times.isEmpty else { continue }

            let text = rest.trimmingCharacters(in: .whitespaces)
            for time in times {
                lines.append(LyricLine(timeMs: max(0, time + offsetMs), text: text))
            }
        }

        return lines.sorted { $0.timeMs < $1.timeMs }
    }

    private static func parseOffset(_ line: String) -> Int? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = offsetTag.firstMatch(in: line, range: range),
              let digits = Range(match.range(at: 1), in: line) else { return nil }
        return Int(line[digits])
    }

    private static func takeTimestamp(_ rest: inout Substring) -> Int? {
        let text = String(rest)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = timestamp.firstMatch(in: text, range: range),
              let minutes = Range(match.range(at: 1), in: text).flatMap({ Int(text[$0]) }),
              let seconds = Range(match.range(at: 2), in: text).flatMap({ Int(text[$0]) })
        else { return nil }

        var fraction = 0
        if match.range(at: 3).location != NSNotFound,
           let fracRange = Range(match.range(at: 3), in: text) {
            let digits = String(text[fracRange])
            // "5" -> 500ms, "50" -> 500ms, "500" -> 500ms
            let padded = digits.padding(toLength: 3, withPad: "0", startingAt: 0)
            fraction = Int(padded) ?? 0
        }

        guard let consumed = Range(match.range, in: text) else { return nil }
        let width = text.distance(from: text.startIndex, to: consumed.upperBound)
        rest = rest[rest.index(rest.startIndex, offsetBy: width)...]
        return minutes * 60_000 + seconds * 1_000 + fraction
    }
}
