import Foundation

public final class NowPlayingPoller: @unchecked Sendable {
    public static let playingIntervalMs = 3_000
    public static let idleIntervalMs = 10_000

    private static let endpoint =
        URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!

    private let auth: SpotifyAuth
    private let http: HTTPClient
    private var loop: Task<Void, Never>?

    public init(auth: SpotifyAuth, http: HTTPClient) {
        self.auth = auth
        self.http = http
    }

    public static func intervalMs(for state: PlaybackState) -> Int {
        if case .playing = state { return playingIntervalMs }
        return idleIntervalMs
    }

    public func start(onState: @escaping @Sendable (PlaybackState) -> Void) {
        stop()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let state = await self.pollOnce()
                onState(state)

                var waitMs = Self.intervalMs(for: state)
                if case .failed(.rateLimited(let retryAfter)) = state {
                    waitMs = max(waitMs, Int(retryAfter * 1000))
                }
                try? await Task.sleep(nanoseconds: UInt64(waitMs) * 1_000_000)
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    public func pollOnce() async -> PlaybackState {
        do {
            let response = try await request()
            if response.status == 401 {
                auth.invalidateAccessToken()
                let retry = try await request()
                guard retry.status != 401 else { return .failed(.sessionExpired) }
                return decode(retry)
            }
            return decode(response)
        } catch let error as AppError {
            return .failed(error)
        } catch {
            return .failed(.network(error.localizedDescription))
        }
    }

    private func request() async throws -> HTTPResponse {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(try await auth.accessToken())",
                         forHTTPHeaderField: "Authorization")
        return try await http.send(request)
    }

    private func decode(_ response: HTTPResponse) -> PlaybackState {
        if response.status == 204 || response.body.isEmpty { return .idle }
        if response.status == 429 {
            let retryAfter = TimeInterval(response.headers["Retry-After"] ?? "") ?? 5
            return .failed(.rateLimited(retryAfter: retryAfter))
        }
        guard (200..<300).contains(response.status) else {
            return .failed(.badResponse(status: response.status))
        }
        guard let payload = try? JSONDecoder().decode(CurrentlyPlaying.self, from: response.body),
              let item = payload.item,
              let id = item.id, let name = item.name, let duration = item.duration_ms,
              let artist = item.artists?.first?.name
        else { return .idle }

        let track = TrackIdentity(id: id, title: name, artist: artist,
                                  album: item.album?.name ?? "", durationMs: duration)
        let np = NowPlaying(track: track,
                            progressMs: payload.progress_ms ?? 0,
                            isPlaying: payload.is_playing ?? false,
                            albumArtURL: item.album?.images?.first?.url
                                .flatMap(URL.init(string:)))
        return np.isPlaying ? .playing(np) : .paused(np)
    }

    private struct CurrentlyPlaying: Decodable {
        struct Artist: Decodable { let name: String? }
        struct Image: Decodable { let url: String? }
        struct Album: Decodable { let name: String?; let images: [Image]? }
        struct Item: Decodable {
            let id: String?
            let name: String?
            let duration_ms: Int?
            let artists: [Artist]?
            let album: Album?
        }
        let is_playing: Bool?
        let progress_ms: Int?
        let item: Item?
    }
}
