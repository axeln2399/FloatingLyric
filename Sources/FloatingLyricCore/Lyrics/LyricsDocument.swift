import Foundation

public struct LyricsDocument: Equatable, Sendable {
    public let lines: [LyricLine]

    public init(lines: [LyricLine]) {
        self.lines = lines
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
