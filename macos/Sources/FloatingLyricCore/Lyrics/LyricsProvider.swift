import Foundation

public final class LyricsProvider: @unchecked Sendable {
    public static let negativeTTL: TimeInterval = 86_400
    public static let userAgent =
        "FloatingLyric/1.0 (macOS lyrics overlay; contact via app repository)"
    private static let durationToleranceSeconds = 5.0
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

        let wanted = Double(track.durationMs) / 1000
        let match = records.first { record in
            guard let duration = record.duration else { return false }
            return abs(duration - wanted) <= Self.durationToleranceSeconds
        }
        return match?.asResult ?? .notFound
    }

    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private struct Record: Decodable {
        let duration: Double?
        let syncedLyrics: String?
        let plainLyrics: String?

        var asResult: LyricsResult {
            if let synced = syncedLyrics, !synced.isEmpty {
                let lines = LRCParser.parse(synced)
                if !lines.isEmpty { return .synced(lines) }
            }
            if let plain = plainLyrics, !plain.isEmpty { return .plain(plain) }
            return .notFound
        }
    }
}
