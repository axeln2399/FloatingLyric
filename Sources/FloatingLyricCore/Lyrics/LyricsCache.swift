import Foundation

public protocol LyricsCaching: AnyObject, Sendable {
    func read(trackID: String, now: Date) -> LyricsResult?
    func write(_ result: LyricsResult, trackID: String, now: Date)
}

public final class LyricsCache: LyricsCaching, @unchecked Sendable {
    private struct Entry: Codable {
        enum Kind: String, Codable { case synced, plain, notFound }
        let kind: Kind
        let lines: [LyricLine]?
        let text: String?
        let fetchedAt: Date
    }

    private let directory: URL

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FloatingLyric/lyrics", isDirectory: true)
    }

    public init(directory: URL = LyricsCache.defaultDirectory) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func url(for trackID: String) -> URL {
        let safe = trackID.replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent("\(safe).json")
    }

    public func read(trackID: String, now: Date) -> LyricsResult? {
        guard let data = try? Data(contentsOf: url(for: trackID)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else { return nil }

        switch entry.kind {
        case .synced:
            return entry.lines.map { .synced($0) }
        case .plain:
            return entry.text.map { .plain($0) }
        case .notFound:
            guard now.timeIntervalSince(entry.fetchedAt) <= LyricsProvider.negativeTTL
            else { return nil }
            return .notFound
        }
    }

    public func write(_ result: LyricsResult, trackID: String, now: Date) {
        let entry: Entry
        switch result {
        case .synced(let lines): entry = Entry(kind: .synced, lines: lines, text: nil, fetchedAt: now)
        case .plain(let text):   entry = Entry(kind: .plain, lines: nil, text: text, fetchedAt: now)
        case .notFound:          entry = Entry(kind: .notFound, lines: nil, text: nil, fetchedAt: now)
        }
        try? JSONEncoder().encode(entry).write(to: url(for: trackID), options: .atomic)
    }
}
