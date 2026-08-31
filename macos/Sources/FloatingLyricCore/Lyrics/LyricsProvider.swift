import Foundation

public final class LyricsProvider: @unchecked Sendable {
    public static let negativeTTL: TimeInterval = 86_400
    public static let userAgent =
        "FloatingLyric/1.0 (macOS lyrics overlay; contact via app repository)"
    /// How far a candidate's duration may sit from the track's before it stops
    /// being the same recording. Widened in stages rather than all at once —
    /// see `bestMatch(for:in:)`.
    static let closeToleranceSeconds = 5.0
    static let looseToleranceSeconds = 15.0
    private static let base = "https://lrclib.net"

    private let http: HTTPClient
    private let cache: LyricsCaching
    private let now: () -> Date

    public init(http: HTTPClient, cache: LyricsCaching, now: @escaping () -> Date = Date.init) {
        self.http = http
        self.cache = cache
        self.now = now
    }

    public func lyrics(for track: TrackIdentity) async -> LyricsResult {
        if let cached = cache.read(trackID: track.id, now: now()) { return cached }
        do {
            let result = try await fetch(track)
            cache.write(result, trackID: track.id, now: now())
            return result
        } catch {
            // Transient failure: report nothing found, but never cache it.
            return .notFound
        }
    }

    private func fetch(_ track: TrackIdentity) async throws -> LyricsResult {
        if let direct = try await directLookup(track) { return direct }
        return try await searchLookup(track)
    }

    private func directLookup(_ track: TrackIdentity) async throws -> LyricsResult? {
        var components = URLComponents(string: Self.base + "/api/get")!
        components.queryItems = [
            .init(name: "artist_name", value: track.artist),
            .init(name: "track_name", value: track.title),
            .init(name: "album_name", value: track.album),
            .init(name: "duration", value: String(track.durationMs / 1000)),
        ]
        let response = try await http.send(request(components.url!))
        guard (200..<300).contains(response.status) else { return nil }
        guard let record = try? JSONDecoder().decode(Record.self, from: response.body)
        else { return nil }
        return record.asResult
    }

    private func searchLookup(_ track: TrackIdentity) async throws -> LyricsResult {
        var components = URLComponents(string: Self.base + "/api/search")!
        components.queryItems = [
            .init(name: "artist_name", value: track.artist),
            .init(name: "track_name", value: track.title),
        ]
        let response = try await http.send(request(components.url!))
        guard (200..<300).contains(response.status),
              let records = try? JSONDecoder().decode([Record].self, from: response.body)
        else { return .notFound }

        return Self.bestMatch(for: track, in: records)?.asResult ?? .notFound
    }

    /// Picks the best of LRCLIB's search results, widening in stages.
    ///
    /// A remaster, a regional release and a single edit of the same song
    /// routinely differ by more than a few seconds, and LRCLIB stores several
    /// of each. Demanding a close duration match throws all of them away and
    /// leaves the user with nothing — where being seconds out is something the
    /// sync offset slider already fixes. So: an exact-ish duration if one
    /// exists, then a loose one, and only then any entry that is unambiguously
    /// the same song by name.
    static func bestMatch(for track: TrackIdentity, in records: [Record]) -> Record? {
        let wanted = Double(track.durationMs) / 1000
        let usable = records.filter { $0.asResult != .notFound }
        guard !usable.isEmpty else { return nil }

        func within(_ tolerance: Double) -> [Record] {
            usable.filter { record in
                guard let duration = record.duration else { return false }
                return abs(duration - wanted) <= tolerance
            }
        }

        // Last resort only: a search for one song can return another, so the
        // widest tier insists the names actually match. Records with no
        // duration at all reach the user only here.
        let sameSong = usable.filter { $0.isSameSong(as: track) }

        for tier in [within(Self.closeToleranceSeconds),
                     within(Self.looseToleranceSeconds),
                     sameSong] where !tier.isEmpty {
            return preferred(in: tier, wanted: wanted)
        }
        return nil
    }

    /// Synced lyrics beat plain ones; after that, the closest duration wins.
    private static func preferred(in records: [Record], wanted: Double) -> Record? {
        records.min { a, b in
            if a.hasSynced != b.hasSynced { return a.hasSynced }
            return a.distance(from: wanted) < b.distance(from: wanted)
        }
    }

    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    struct Record: Decodable {
        let duration: Double?
        let syncedLyrics: String?
        let plainLyrics: String?
        let artistName: String?
        let trackName: String?

        var asResult: LyricsResult {
            if let synced = syncedLyrics, !synced.isEmpty {
                let lines = LRCParser.parse(synced)
                if !lines.isEmpty { return .synced(lines) }
            }
            if let plain = plainLyrics, !plain.isEmpty { return .plain(plain) }
            return .notFound
        }

        var hasSynced: Bool {
            if case .synced = asResult { return true }
            return false
        }

        /// A record with no duration is infinitely far away, so it sorts last
        /// wherever something better exists.
        func distance(from seconds: Double) -> Double {
            guard let duration else { return .greatestFiniteMagnitude }
            return abs(duration - seconds)
        }

        func isSameSong(as track: TrackIdentity) -> Bool {
            Record.normalized(artistName) == Record.normalized(track.artist)
                && Record.normalized(trackName) == Record.normalized(track.title)
        }

        private static func normalized(_ text: String?) -> String {
            (text ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive],
                                 locale: nil)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
