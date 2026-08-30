import Foundation

public struct LyricsDocument: Equatable, Sendable {
    public let lines: [LyricLine]

    /// A Latin reading per line, `nil` where the line needs none. Built once
    /// here rather than in the view, which redraws ten times a second.
    /// Romanizing is only attempted for lines that actually carry non-Latin
    /// letters, so an English song pays no more than a scan of its text.
    public let romanizations: [String?]

    public init(lines: [LyricLine]) {
        self.lines = lines
        self.romanizations = lines.map { Transliteration.romanize($0.text) }
    }

    /// The Latin reading for a line, or nil when there is none to show.
    public func romanization(at index: Int) -> String? {
        guard romanizations.indices.contains(index) else { return nil }
        return romanizations[index]
    }

    /// True when at least one line has a reading worth showing — used to keep
    /// the layout unchanged for songs that are already in Latin script.
    public var hasRomanizations: Bool {
        romanizations.contains { $0 != nil }
    }

    /// Index of the last line whose timestamp is <= position + offset, or nil if
    /// the adjusted position falls before the first line.
    public func index(atPositionMs positionMs: Int, offsetMs: Int) -> Int? {
        guard !lines.isEmpty else { return nil }
        let target = positionMs + offsetMs
        guard target >= lines[0].timeMs else { return nil }

        var low = 0
        var high = lines.count - 1
        var answer = 0
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].timeMs <= target {
                answer = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return answer
    }
}
