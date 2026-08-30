# FloatingLyric Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS menu-bar app showing time-synced lyrics for the track currently playing on the user's Spotify account, in a translucent always-on-top window, shipped as an unsigned `.dmg`.

**Architecture:** A `FloatingLyricCore` library holds all logic and UI; a thin `FloatingLyric` executable target boots it. Four units — `SpotifyAuth`, `NowPlayingPoller`, `LyricsProvider`, `PlayheadClock` — sit behind protocols and are wired together by `AppCoordinator`. All network access goes through an injected `HTTPClient` protocol so every test runs offline.

**Tech Stack:** Swift 5.9, SwiftUI + AppKit, Swift Package Manager, XCTest, Network.framework (loopback OAuth listener), Security.framework (Keychain). No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-08-30-floatinglyric-design.md`

## Global Constraints

- Platform floor: `.macOS(.v14)`. Built and run on macOS 26.0.1.
- swift-tools-version: 5.9.
- Zero third-party package dependencies. Apple frameworks only.
- All network access via the `HTTPClient` protocol. No test may touch the real network.
- Spotify OAuth: Authorization Code with **PKCE**, no client secret. Scope is exactly `user-read-playback-state`.
- Redirect URI: `http://127.0.0.1:8888/callback` (fallback ports 8889, 8890). `localhost` is not accepted by Spotify.
- Lyrics source: LRCLIB at `https://lrclib.net`, `User-Agent: FloatingLyric/1.0 (macOS lyrics overlay; contact via app repository)`.
- Keychain service name: `com.floatinglyric.tokens`. Bundle identifier: `com.floatinglyric.app`.
- `Info.plist` must set `LSUIElement = true` (no Dock icon).
- Sync offset range: -2000 ms to +2000 ms. Seek-detection threshold: 1500 ms.
- Poll interval: 3000 ms while playing, 10000 ms while idle or paused.
- Negative lyrics cache TTL: 24 hours.

---

## File Structure

```
Package.swift                                   SPM manifest, two targets + test target
build.sh                                        release build -> .app -> .dmg
README.md                                       setup, Spotify app registration, Gatekeeper note
Resources/Info.plist                            LSUIElement, bundle id, version
Resources/AppIcon.icns                          app icon
Sources/FloatingLyric/main.swift                thin entry point -> Core.run()
Sources/FloatingLyricCore/
  Support/HTTPClient.swift                      protocol + URLSession impl + HTTPResponse
  Support/AppError.swift                        error enum shown in the panel
  Support/Defaults.swift                        typed UserDefaults accessors
  Lyrics/LyricLine.swift                        LyricLine, LyricsResult, TrackIdentity
  Lyrics/LRCParser.swift                        LRC text -> [LyricLine]
  Lyrics/LyricsDocument.swift                   holds lines, answers "current index"
  Lyrics/LyricsCache.swift                      on-disk positive + negative cache
  Lyrics/LyricsProvider.swift                   LRCLIB get -> search -> cache
  Playback/PlayheadClock.swift                  pure position extrapolation
  Playback/NowPlaying.swift                     NowPlaying, PlaybackState
  Playback/NowPlayingPoller.swift               polls Spotify, emits PlaybackState
  Auth/PKCE.swift                               verifier/challenge/state generation
  Auth/KeychainStore.swift                      refresh token storage
  Auth/CallbackListener.swift                   one-shot loopback HTTP server
  Auth/SpotifyAuth.swift                        login, exchange, refresh, logout
  UI/FloatingPanel.swift                        NSPanel subclass
  UI/LyricView.swift                            SwiftUI lyric rendering
  UI/LyricViewModel.swift                       observable state for LyricView
  UI/SetupWindow.swift                          first-run Client ID entry
  App/MenuBarController.swift                   NSStatusItem + menu
  App/AppCoordinator.swift                      wires the units together
  App/AppDelegate.swift                         NSApplicationDelegate, Core.run()
Tests/FloatingLyricCoreTests/
  LRCParserTests.swift
  LyricsDocumentTests.swift
  PlayheadClockTests.swift
  LyricsProviderTests.swift
  NowPlayingPollerTests.swift
  SpotifyAuthTests.swift
  PKCETests.swift
  StubHTTPClient.swift                          shared test double
```

---

### Task 1: Project scaffold and HTTP seam

**Files:**
- Create: `Package.swift`
- Create: `Sources/FloatingLyricCore/Support/HTTPClient.swift`
- Create: `Sources/FloatingLyricCore/Support/AppError.swift`
- Create: `Sources/FloatingLyric/main.swift`
- Create: `Tests/FloatingLyricCoreTests/StubHTTPClient.swift`
- Test: `Tests/FloatingLyricCoreTests/StubHTTPClientTests.swift`
- Create: `.gitignore` (append `.build/`, `dist/`, `*.dmg` if not present)

**Interfaces:**
- Consumes: nothing.
- Produces: `protocol HTTPClient { func send(_ request: URLRequest) async throws -> HTTPResponse }`; `struct HTTPResponse { let status: Int; let body: Data; let headers: [String: String] }`; `enum AppError: Error, Equatable`; `final class StubHTTPClient: HTTPClient` with `var responses: [HTTPResponse]`, `var recordedRequests: [URLRequest]`, and `var errorToThrow: Error?`.

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FloatingLyric",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FloatingLyricCore"),
        .executableTarget(name: "FloatingLyric", dependencies: ["FloatingLyricCore"]),
        .testTarget(name: "FloatingLyricCoreTests", dependencies: ["FloatingLyricCore"]),
    ]
)
```

- [ ] **Step 2: Write the failing test**

`Tests/FloatingLyricCoreTests/StubHTTPClientTests.swift`:

```swift
import XCTest
@testable import FloatingLyricCore

final class StubHTTPClientTests: XCTestCase {
    func test_stubReturnsQueuedResponsesInOrderAndRecordsRequests() async throws {
        let stub = StubHTTPClient()
        stub.responses = [
            HTTPResponse(status: 200, body: Data("first".utf8), headers: [:]),
            HTTPResponse(status: 404, body: Data(), headers: [:]),
        ]
        let request = URLRequest(url: URL(string: "https://example.com/a")!)

        let first = try await stub.send(request)
        let second = try await stub.send(request)

        XCTAssertEqual(first.status, 200)
        XCTAssertEqual(String(decoding: first.body, as: UTF8.self), "first")
        XCTAssertEqual(second.status, 404)
        XCTAssertEqual(stub.recordedRequests.count, 2)
    }

    func test_stubThrowsConfiguredError() async {
        let stub = StubHTTPClient()
        stub.errorToThrow = AppError.network("offline")
        do {
            _ = try await stub.send(URLRequest(url: URL(string: "https://example.com")!))
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? AppError, AppError.network("offline"))
        }
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test 2>&1 | tail -20`
Expected: FAIL — `cannot find 'StubHTTPClient' in scope`.

- [ ] **Step 4: Implement `AppError.swift`**

```swift
import Foundation

public enum AppError: Error, Equatable {
    case notConfigured
    case notLoggedIn
    case sessionExpired
    case network(String)
    case rateLimited(retryAfter: TimeInterval)
    case badResponse(status: Int)
    case portUnavailable
    case authCancelled

    public var displayMessage: String {
        switch self {
        case .notConfigured:   return "Set up Spotify to begin"
        case .notLoggedIn:     return "Log in to Spotify"
        case .sessionExpired:  return "Session expired — log in again"
        case .network:         return "Offline"
        case .rateLimited:     return "Spotify is rate limiting — retrying"
        case .badResponse:     return "Spotify returned an unexpected response"
        case .portUnavailable: return "Port 8888–8890 in use. Free one and retry."
        case .authCancelled:   return "Login cancelled"
        }
    }
}
```

- [ ] **Step 5: Implement `HTTPClient.swift`**

```swift
import Foundation

public struct HTTPResponse: Sendable {
    public let status: Int
    public let body: Data
    public let headers: [String: String]

    public init(status: Int, body: Data, headers: [String: String]) {
        self.status = status
        self.body = body
        self.headers = headers
    }
}

public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AppError.network("Not an HTTP response")
            }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                if let k = key as? String, let v = value as? String { headers[k] = v }
            }
            return HTTPResponse(status: http.statusCode, body: data, headers: headers)
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.network(error.localizedDescription)
        }
    }
}
```

- [ ] **Step 6: Implement `StubHTTPClient.swift`**

```swift
import Foundation
@testable import FloatingLyricCore

final class StubHTTPClient: HTTPClient, @unchecked Sendable {
    var responses: [HTTPResponse] = []
    var errorToThrow: Error?
    private(set) var recordedRequests: [URLRequest] = []

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        recordedRequests.append(request)
        if let errorToThrow { throw errorToThrow }
        guard !responses.isEmpty else {
            return HTTPResponse(status: 200, body: Data(), headers: [:])
        }
        return responses.removeFirst()
    }
}

extension HTTPResponse {
    static func json(_ string: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, body: Data(string.utf8),
                     headers: ["Content-Type": "application/json"])
    }
}
```

- [ ] **Step 7: Implement `main.swift` placeholder**

```swift
import FloatingLyricCore

FloatingLyricApp.run()
```

Add to `Sources/FloatingLyricCore/App/AppDelegate.swift` a minimal stand-in so the target compiles; Task 11 fills it in:

```swift
import AppKit

public enum FloatingLyricApp {
    public static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -20`
Expected: PASS, 2 tests.

- [ ] **Step 9: Commit**

```bash
git add Package.swift Sources Tests .gitignore
git commit -m "feat: project scaffold with HTTP client seam"
```

---

### Task 2: LRC parser

**Files:**
- Create: `Sources/FloatingLyricCore/Lyrics/LyricLine.swift`
- Create: `Sources/FloatingLyricCore/Lyrics/LRCParser.swift`
- Test: `Tests/FloatingLyricCoreTests/LRCParserTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `struct LyricLine: Equatable, Codable, Sendable { let timeMs: Int; let text: String }`; `enum LRCParser { static func parse(_ raw: String) -> [LyricLine] }`; `struct TrackIdentity: Equatable, Sendable { let id: String; let title: String; let artist: String; let album: String; let durationMs: Int }`; `enum LyricsResult: Equatable, Sendable { case synced([LyricLine]); case plain(String); case notFound }`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import FloatingLyricCore

final class LRCParserTests: XCTestCase {
    func test_parsesWellFormedLines() {
        let raw = """
        [00:12.34]First line
        [00:15.00]Second line
        [01:02.50]Third line
        """
        XCTAssertEqual(LRCParser.parse(raw), [
            LyricLine(timeMs: 12340, text: "First line"),
            LyricLine(timeMs: 15000, text: "Second line"),
            LyricLine(timeMs: 62500, text: "Third line"),
        ])
    }

    func test_parsesThreeDigitMilliseconds() {
        XCTAssertEqual(LRCParser.parse("[00:01.234]Hi"),
                       [LyricLine(timeMs: 1234, text: "Hi")])
    }

    func test_repeatsTextForMultipleTimestampsOnOneLine() {
        let parsed = LRCParser.parse("[00:10.00][00:20.00]Chorus")
        XCTAssertEqual(parsed, [
            LyricLine(timeMs: 10000, text: "Chorus"),
            LyricLine(timeMs: 20000, text: "Chorus"),
        ])
    }

    func test_appliesOffsetTagAndIgnoresOtherMetadata() {
        let raw = """
        [ar:Someone]
        [ti:Some Song]
        [offset:-500]
        [00:10.00]Line
        """
        XCTAssertEqual(LRCParser.parse(raw), [LyricLine(timeMs: 9500, text: "Line")])
    }

    func test_offsetNeverProducesNegativeTimes() {
        let raw = "[offset:-5000]\n[00:01.00]Line"
        XCTAssertEqual(LRCParser.parse(raw), [LyricLine(timeMs: 0, text: "Line")])
    }

    func test_skipsMalformedLines() {
        let raw = """
        not a lyric line
        [garbage]still not
        [00:10.00]Good line
        """
        XCTAssertEqual(LRCParser.parse(raw), [LyricLine(timeMs: 10000, text: "Good line")])
    }

    func test_preservesBlankLyricLinesAsPauses() {
        let raw = "[00:10.00]Line\n[00:14.00]\n[00:18.00]Next"
        XCTAssertEqual(LRCParser.parse(raw), [
            LyricLine(timeMs: 10000, text: "Line"),
            LyricLine(timeMs: 14000, text: ""),
            LyricLine(timeMs: 18000, text: "Next"),
        ])
    }

    func test_sortsUnorderedTimestamps() {
        let raw = "[00:20.00]Second\n[00:10.00]First"
        XCTAssertEqual(LRCParser.parse(raw), [
            LyricLine(timeMs: 10000, text: "First"),
            LyricLine(timeMs: 20000, text: "Second"),
        ])
    }

    func test_emptyInputProducesNoLines() {
        XCTAssertEqual(LRCParser.parse(""), [])
        XCTAssertEqual(LRCParser.parse("   \n  \n"), [])
    }

    func test_trimsWhitespaceAroundText() {
        XCTAssertEqual(LRCParser.parse("[00:10.00]   Line   "),
                       [LyricLine(timeMs: 10000, text: "Line")])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LRCParserTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'LRCParser' in scope`.

- [ ] **Step 3: Implement `LyricLine.swift`**

```swift
import Foundation

public struct LyricLine: Equatable, Codable, Sendable {
    public let timeMs: Int
    public let text: String

    public init(timeMs: Int, text: String) {
        self.timeMs = timeMs
        self.text = text
    }
}

public struct TrackIdentity: Equatable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String
    public let durationMs: Int

    public init(id: String, title: String, artist: String, album: String, durationMs: Int) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.durationMs = durationMs
    }
}

public enum LyricsResult: Equatable, Sendable {
    case synced([LyricLine])
    case plain(String)
    case notFound
}
```

- [ ] **Step 4: Implement `LRCParser.swift`**

```swift
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
        rest = rest[rest.index(rest.startIndex, offsetBy: text.distance(from: text.startIndex, to: consumed.upperBound))...]
        return minutes * 60_000 + seconds * 1_000 + fraction
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter LRCParserTests 2>&1 | tail -20`
Expected: PASS, 10 tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/FloatingLyricCore/Lyrics Tests/FloatingLyricCoreTests/LRCParserTests.swift
git commit -m "feat: LRC parser with offset, multi-timestamp and malformed-line handling"
```

---

### Task 3: Current-line selection

**Files:**
- Create: `Sources/FloatingLyricCore/Lyrics/LyricsDocument.swift`
- Test: `Tests/FloatingLyricCoreTests/LyricsDocumentTests.swift`

**Interfaces:**
- Consumes: `LyricLine` (Task 2).
- Produces: `struct LyricsDocument { let lines: [LyricLine]; init(lines: [LyricLine]); func index(atPositionMs: Int, offsetMs: Int) -> Int? }`. Returns `nil` before the first timestamp.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import FloatingLyricCore

final class LyricsDocumentTests: XCTestCase {
    private let doc = LyricsDocument(lines: [
        LyricLine(timeMs: 1000, text: "one"),
        LyricLine(timeMs: 2000, text: "two"),
        LyricLine(timeMs: 3000, text: "three"),
    ])

    func test_exactlyOnATimestampSelectsThatLine() {
        XCTAssertEqual(doc.index(atPositionMs: 2000, offsetMs: 0), 1)
    }

    func test_betweenTimestampsSelectsTheEarlierLine() {
        XCTAssertEqual(doc.index(atPositionMs: 2500, offsetMs: 0), 1)
    }

    func test_beforeFirstTimestampSelectsNothing() {
        XCTAssertNil(doc.index(atPositionMs: 0, offsetMs: 0))
        XCTAssertNil(doc.index(atPositionMs: 999, offsetMs: 0))
    }

    func test_afterLastTimestampSelectsLastLine() {
        XCTAssertEqual(doc.index(atPositionMs: 99_000, offsetMs: 0), 2)
    }

    func test_positiveOffsetAdvancesSelection() {
        XCTAssertEqual(doc.index(atPositionMs: 1800, offsetMs: 500), 1)
    }

    func test_negativeOffsetDelaysSelection() {
        XCTAssertEqual(doc.index(atPositionMs: 2100, offsetMs: -500), 0)
    }

    func test_offsetPushingBeforeStartSelectsNothing() {
        XCTAssertNil(doc.index(atPositionMs: 1200, offsetMs: -500))
    }

    func test_emptyDocumentSelectsNothing() {
        XCTAssertNil(LyricsDocument(lines: []).index(atPositionMs: 5000, offsetMs: 0))
    }

    func test_singleLineDocument() {
        let single = LyricsDocument(lines: [LyricLine(timeMs: 500, text: "only")])
        XCTAssertNil(single.index(atPositionMs: 400, offsetMs: 0))
        XCTAssertEqual(single.index(atPositionMs: 500, offsetMs: 0), 0)
        XCTAssertEqual(single.index(atPositionMs: 900_000, offsetMs: 0), 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LyricsDocumentTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'LyricsDocument' in scope`.

- [ ] **Step 3: Implement `LyricsDocument.swift`**

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LyricsDocumentTests 2>&1 | tail -20`
Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/FloatingLyricCore/Lyrics/LyricsDocument.swift Tests/FloatingLyricCoreTests/LyricsDocumentTests.swift
git commit -m "feat: binary-search current lyric line selection with sync offset"
```

---

### Task 4: Playhead clock

**Files:**
- Create: `Sources/FloatingLyricCore/Playback/PlayheadClock.swift`
- Test: `Tests/FloatingLyricCoreTests/PlayheadClockTests.swift`

**Interfaces:**
- Consumes: nothing. Pure, no `Date()` inside — every method takes an explicit `now: TimeInterval` (seconds, monotonic-ish).
- Produces: `final class PlayheadClock { static let seekThresholdMs = 1500; func anchor(progressMs: Int, isPlaying: Bool, now: TimeInterval); func positionMs(now: TimeInterval) -> Int; func isSeek(polledProgressMs: Int, now: TimeInterval) -> Bool }`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import FloatingLyricCore

final class PlayheadClockTests: XCTestCase {
    func test_positionAdvancesWithWallClockWhilePlaying() {
        let clock = PlayheadClock()
        clock.anchor(progressMs: 10_000, isPlaying: true, now: 100.0)
        XCTAssertEqual(clock.positionMs(now: 100.0), 10_000)
        XCTAssertEqual(clock.positionMs(now: 102.5), 12_500)
    }

    func test_positionIsFrozenWhilePaused() {
        let clock = PlayheadClock()
        clock.anchor(progressMs: 10_000, isPlaying: false, now: 100.0)
        XCTAssertEqual(clock.positionMs(now: 105.0), 10_000)
    }

    func test_reanchoringResetsPosition() {
        let clock = PlayheadClock()
        clock.anchor(progressMs: 10_000, isPlaying: true, now: 100.0)
        clock.anchor(progressMs: 60_000, isPlaying: true, now: 103.0)
        XCTAssertEqual(clock.positionMs(now: 104.0), 61_000)
    }

    func test_positionNeverGoesNegative() {
        let clock = PlayheadClock()
        clock.anchor(progressMs: 0, isPlaying: true, now: 100.0)
        XCTAssertEqual(clock.positionMs(now: 99.0), 0)
    }

    func test_withoutAnchorPositionIsZero() {
        XCTAssertEqual(PlayheadClock().positionMs(now: 100.0), 0)
    }

    func test_smallDriftIsNotASeek() {
        let clock = PlayheadClock()
        clock.anchor(progressMs: 10_000, isPlaying: true, now: 100.0)
        // 3s later we expect 13000; Spotify says 13400 -> 400ms drift.
        XCTAssertFalse(clock.isSeek(polledProgressMs: 13_400, now: 103.0))
    }

    func test_driftAtThresholdIsNotASeekButBeyondItIs() {
        let clock = PlayheadClock()
        clock.anchor(progressMs: 10_000, isPlaying: true, now: 100.0)
        XCTAssertFalse(clock.isSeek(polledProgressMs: 14_500, now: 103.0)) // exactly 1500
        XCTAssertTrue(clock.isSeek(polledProgressMs: 14_501, now: 103.0))  // 1501
        XCTAssertTrue(clock.isSeek(polledProgressMs: 11_499, now: 103.0))  // -1501
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PlayheadClockTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'PlayheadClock' in scope`.

- [ ] **Step 3: Implement `PlayheadClock.swift`**

```swift
import Foundation

/// Extrapolates the playback position between polls. Pure: callers supply `now`.
public final class PlayheadClock: @unchecked Sendable {
    public static let seekThresholdMs = 1500

    private var anchorProgressMs: Int = 0
    private var anchorTime: TimeInterval?
    private var playing = false

    public init() {}

    public func anchor(progressMs: Int, isPlaying: Bool, now: TimeInterval) {
        anchorProgressMs = max(0, progressMs)
        anchorTime = now
        playing = isPlaying
    }

    public func positionMs(now: TimeInterval) -> Int {
        guard let anchorTime else { return 0 }
        guard playing else { return anchorProgressMs }
        let elapsedMs = Int(((now - anchorTime) * 1000).rounded())
        return max(0, anchorProgressMs + elapsedMs)
    }

    /// True when a freshly polled progress differs from the extrapolated
    /// position by more than `seekThresholdMs`.
    public func isSeek(polledProgressMs: Int, now: TimeInterval) -> Bool {
        guard anchorTime != nil else { return false }
        return abs(polledProgressMs - positionMs(now: now)) > Self.seekThresholdMs
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PlayheadClockTests 2>&1 | tail -20`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/FloatingLyricCore/Playback/PlayheadClock.swift Tests/FloatingLyricCoreTests/PlayheadClockTests.swift
git commit -m "feat: playhead clock with pause freeze and seek detection"
```

---

### Task 5: PKCE and Keychain storage

**Files:**
- Create: `Sources/FloatingLyricCore/Auth/PKCE.swift`
- Create: `Sources/FloatingLyricCore/Auth/KeychainStore.swift`
- Test: `Tests/FloatingLyricCoreTests/PKCETests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `struct PKCEPair { let verifier: String; let challenge: String }`; `enum PKCE { static func generate() -> PKCEPair; static func randomState() -> String }`; `protocol TokenStore { func readRefreshToken() -> String?; func writeRefreshToken(_ token: String); func deleteRefreshToken() }`; `final class KeychainStore: TokenStore` (service `com.floatinglyric.tokens`, account `refresh-token`); `final class InMemoryTokenStore: TokenStore` for tests (ship it in the library so Task 6's tests can use it).

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import CryptoKit
@testable import FloatingLyricCore

final class PKCETests: XCTestCase {
    func test_verifierLengthIsWithinSpecRange() {
        let pair = PKCE.generate()
        XCTAssertGreaterThanOrEqual(pair.verifier.count, 43)
        XCTAssertLessThanOrEqual(pair.verifier.count, 128)
    }

    func test_verifierUsesOnlyUnreservedCharacters() {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let pair = PKCE.generate()
        XCTAssertTrue(pair.verifier.unicodeScalars.allSatisfy { allowed.contains($0) })
    }

    func test_challengeIsBase64URLEncodedSHA256OfVerifier() {
        let pair = PKCE.generate()
        let digest = SHA256.hash(data: Data(pair.verifier.utf8))
        let expected = Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(pair.challenge, expected)
    }

    func test_challengeHasNoPaddingOrURLUnsafeCharacters() {
        let challenge = PKCE.generate().challenge
        XCTAssertFalse(challenge.contains("="))
        XCTAssertFalse(challenge.contains("+"))
        XCTAssertFalse(challenge.contains("/"))
    }

    func test_eachGenerationIsUnique() {
        XCTAssertNotEqual(PKCE.generate().verifier, PKCE.generate().verifier)
        XCTAssertNotEqual(PKCE.randomState(), PKCE.randomState())
    }

    func test_inMemoryTokenStoreRoundTrips() {
        let store = InMemoryTokenStore()
        XCTAssertNil(store.readRefreshToken())
        store.writeRefreshToken("abc")
        XCTAssertEqual(store.readRefreshToken(), "abc")
        store.deleteRefreshToken()
        XCTAssertNil(store.readRefreshToken())
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PKCETests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'PKCE' in scope`.

- [ ] **Step 3: Implement `PKCE.swift`**

```swift
import Foundation
import CryptoKit

public struct PKCEPair: Sendable {
    public let verifier: String
    public let challenge: String
}

public enum PKCE {
    private static let unreserved = Array(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    public static func generate() -> PKCEPair {
        let verifier = randomString(length: 64)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return PKCEPair(verifier: verifier, challenge: base64URL(Data(digest)))
    }

    public static func randomState() -> String {
        randomString(length: 32)
    }

    private static func randomString(length: Int) -> String {
        String((0..<length).map { _ in unreserved.randomElement()! })
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
```

- [ ] **Step 4: Implement `KeychainStore.swift`**

```swift
import Foundation
import Security

public protocol TokenStore: AnyObject, Sendable {
    func readRefreshToken() -> String?
    func writeRefreshToken(_ token: String)
    func deleteRefreshToken()
}

public final class KeychainStore: TokenStore, @unchecked Sendable {
    private let service = "com.floatinglyric.tokens"
    private let account = "refresh-token"

    public init() {}

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func readRefreshToken() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func writeRefreshToken(_ token: String) {
        deleteRefreshToken()
        var query = baseQuery
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    public func deleteRefreshToken() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private var token: String?
    public init(token: String? = nil) { self.token = token }
    public func readRefreshToken() -> String? { token }
    public func writeRefreshToken(_ token: String) { self.token = token }
    public func deleteRefreshToken() { token = nil }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter PKCETests 2>&1 | tail -20`
Expected: PASS, 6 tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/FloatingLyricCore/Auth Tests/FloatingLyricCoreTests/PKCETests.swift
git commit -m "feat: PKCE generation and Keychain-backed token store"
```

---

### Task 6: Spotify auth — token exchange and refresh

**Files:**
- Create: `Sources/FloatingLyricCore/Auth/SpotifyAuth.swift`
- Create: `Sources/FloatingLyricCore/Support/Defaults.swift`
- Test: `Tests/FloatingLyricCoreTests/SpotifyAuthTests.swift`

**Interfaces:**
- Consumes: `HTTPClient`, `HTTPResponse`, `AppError` (Task 1); `TokenStore`, `PKCE` (Task 5).
- Produces: `final class SpotifyAuth { init(clientID: String, http: HTTPClient, store: TokenStore, now: @escaping () -> Date = Date.init); var isLoggedIn: Bool; func accessToken() async throws -> String; func exchange(code: String, verifier: String, redirectURI: String) async throws; func authorizationURL(challenge: String, state: String, redirectURI: String) -> URL; func logOut() }` and `enum Defaults` with static `clientID: String?`, `syncOffsetMs: Int`, `panelFrame: String?`, `fontSize: Int`.
- Token freshness rule: `accessToken()` returns the cached token when more than 60 s remain before expiry; otherwise it refreshes first.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import FloatingLyricCore

final class SpotifyAuthTests: XCTestCase {
    private let redirect = "http://127.0.0.1:8888/callback"

    private func makeAuth(store: TokenStore = InMemoryTokenStore(),
                          http: StubHTTPClient = StubHTTPClient(),
                          clock: @escaping () -> Date = { Date(timeIntervalSince1970: 1000) })
    -> (SpotifyAuth, StubHTTPClient, TokenStore) {
        (SpotifyAuth(clientID: "CID", http: http, store: store, now: clock), http, store)
    }

    func test_authorizationURLCarriesPKCEAndScope() {
        let (auth, _, _) = makeAuth()
        let url = auth.authorizationURL(challenge: "CHAL", state: "ST", redirectURI: redirect)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        XCTAssertEqual(url.host, "accounts.spotify.com")
        XCTAssertEqual(url.path, "/authorize")
        XCTAssertEqual(value("response_type"), "code")
        XCTAssertEqual(value("client_id"), "CID")
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("code_challenge"), "CHAL")
        XCTAssertEqual(value("state"), "ST")
        XCTAssertEqual(value("scope"), "user-read-playback-state")
        XCTAssertEqual(value("redirect_uri"), redirect)
    }

    func test_exchangeStoresRefreshTokenAndReturnsAccessToken() async throws {
        let (auth, http, store) = makeAuth()
        http.responses = [.json(#"{"access_token":"AT","refresh_token":"RT","expires_in":3600}"#)]

        try await auth.exchange(code: "CODE", verifier: "VER", redirectURI: redirect)

        XCTAssertEqual(store.readRefreshToken(), "RT")
        XCTAssertTrue(auth.isLoggedIn)
        let token = try await auth.accessToken()
        XCTAssertEqual(token, "AT")
        XCTAssertEqual(http.recordedRequests.count, 1, "cached token must not trigger a refresh")
    }

    func test_notLoggedInWithoutStoredRefreshToken() async {
        let (auth, _, _) = makeAuth()
        XCTAssertFalse(auth.isLoggedIn)
        do {
            _ = try await auth.accessToken()
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? AppError, .notLoggedIn)
        }
    }

    func test_refreshesWhenTokenIsWithinSixtySecondsOfExpiry() async throws {
        var now = Date(timeIntervalSince1970: 1000)
        let http = StubHTTPClient()
        let (auth, _, _) = makeAuth(http: http, clock: { now })
        http.responses = [
            .json(#"{"access_token":"AT1","refresh_token":"RT","expires_in":3600}"#),
            .json(#"{"access_token":"AT2","expires_in":3600}"#),
        ]
        try await auth.exchange(code: "C", verifier: "V", redirectURI: redirect)

        now = Date(timeIntervalSince1970: 1000 + 3600 - 59) // inside the 60s window
        XCTAssertEqual(try await auth.accessToken(), "AT2")
        XCTAssertEqual(http.recordedRequests.count, 2)
    }

    func test_refreshResponseWithoutNewRefreshTokenKeepsTheOldOne() async throws {
        var now = Date(timeIntervalSince1970: 1000)
        let store = InMemoryTokenStore()
        let http = StubHTTPClient()
        let (auth, _, _) = makeAuth(store: store, http: http, clock: { now })
        http.responses = [
            .json(#"{"access_token":"AT1","refresh_token":"RT","expires_in":3600}"#),
            .json(#"{"access_token":"AT2","expires_in":3600}"#),
        ]
        try await auth.exchange(code: "C", verifier: "V", redirectURI: redirect)
        now = Date(timeIntervalSince1970: 5000)
        _ = try await auth.accessToken()
        XCTAssertEqual(store.readRefreshToken(), "RT")
    }

    func test_failedRefreshClearsTokenAndReportsSessionExpired() async throws {
        var now = Date(timeIntervalSince1970: 1000)
        let store = InMemoryTokenStore()
        let http = StubHTTPClient()
        let (auth, _, _) = makeAuth(store: store, http: http, clock: { now })
        http.responses = [
            .json(#"{"access_token":"AT1","refresh_token":"RT","expires_in":3600}"#),
            .json(#"{"error":"invalid_grant"}"#, status: 400),
        ]
        try await auth.exchange(code: "C", verifier: "V", redirectURI: redirect)
        now = Date(timeIntervalSince1970: 99_999)

        do {
            _ = try await auth.accessToken()
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? AppError, .sessionExpired)
        }
        XCTAssertNil(store.readRefreshToken())
        XCTAssertFalse(auth.isLoggedIn)
    }

    func test_invalidateForcesTheNextCallToRefresh() async throws {
        let http = StubHTTPClient()
        let (auth, _, _) = makeAuth(http: http)
        http.responses = [
            .json(#"{"access_token":"AT1","refresh_token":"RT","expires_in":3600}"#),
            .json(#"{"access_token":"AT2","expires_in":3600}"#),
        ]
        try await auth.exchange(code: "C", verifier: "V", redirectURI: redirect)
        auth.invalidateAccessToken()
        XCTAssertEqual(try await auth.accessToken(), "AT2")
    }

    func test_logOutClearsEverything() async throws {
        let (auth, http, store) = makeAuth()
        http.responses = [.json(#"{"access_token":"AT","refresh_token":"RT","expires_in":3600}"#)]
        try await auth.exchange(code: "C", verifier: "V", redirectURI: redirect)
        auth.logOut()
        XCTAssertFalse(auth.isLoggedIn)
        XCTAssertNil(store.readRefreshToken())
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SpotifyAuthTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'SpotifyAuth' in scope`.

- [ ] **Step 3: Implement `Defaults.swift`**

```swift
import Foundation

public enum Defaults {
    private static let d = UserDefaults.standard

    public static var clientID: String? {
        get { d.string(forKey: "clientID")?.trimmingCharacters(in: .whitespaces).nilIfEmpty }
        set { d.set(newValue, forKey: "clientID") }
    }

    public static var syncOffsetMs: Int {
        get { d.object(forKey: "syncOffsetMs") as? Int ?? 0 }
        set { d.set(min(2000, max(-2000, newValue)), forKey: "syncOffsetMs") }
    }

    public static var panelFrame: String? {
        get { d.string(forKey: "panelFrame") }
        set { d.set(newValue, forKey: "panelFrame") }
    }

    public static var fontSize: Int {
        get { d.object(forKey: "fontSize") as? Int ?? 18 }
        set { d.set(newValue, forKey: "fontSize") }
    }

    public static var clickThrough: Bool {
        get { d.bool(forKey: "clickThrough") }
        set { d.set(newValue, forKey: "clickThrough") }
    }

    public static var lockPosition: Bool {
        get { d.bool(forKey: "lockPosition") }
        set { d.set(newValue, forKey: "lockPosition") }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
```

- [ ] **Step 4: Implement `SpotifyAuth.swift`**

```swift
import Foundation

public final class SpotifyAuth: @unchecked Sendable {
    public static let scope = "user-read-playback-state"
    private static let authorizeURL = URL(string: "https://accounts.spotify.com/authorize")!
    private static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
    private static let refreshMarginSeconds: TimeInterval = 60

    private let clientID: String
    private let http: HTTPClient
    private let store: TokenStore
    private let now: () -> Date

    private var accessTokenValue: String?
    private var expiresAt: Date?

    public init(clientID: String,
                http: HTTPClient,
                store: TokenStore,
                now: @escaping () -> Date = Date.init) {
        self.clientID = clientID
        self.http = http
        self.store = store
        self.now = now
    }

    public var isLoggedIn: Bool { store.readRefreshToken() != nil }

    public func authorizationURL(challenge: String, state: String, redirectURI: String) -> URL {
        var components = URLComponents(url: Self.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientID),
            .init(name: "scope", value: Self.scope),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "state", value: state),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
        ]
        return components.url!
    }

    public func exchange(code: String, verifier: String, redirectURI: String) async throws {
        try await requestToken(form: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ], failureError: .authCancelled)
    }

    public func accessToken() async throws -> String {
        if let token = accessTokenValue, let expiresAt,
           expiresAt.timeIntervalSince(now()) > Self.refreshMarginSeconds {
            return token
        }
        guard let refreshToken = store.readRefreshToken() else { throw AppError.notLoggedIn }
        try await requestToken(form: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ], failureError: .sessionExpired)
        guard let token = accessTokenValue else { throw AppError.sessionExpired }
        return token
    }

    /// Drops the cached access token so the next `accessToken()` refreshes.
    public func invalidateAccessToken() {
        accessTokenValue = nil
        expiresAt = nil
    }

    public func logOut() {
        invalidateAccessToken()
        store.deleteRefreshToken()
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
    }

    private func requestToken(form: [String: String], failureError: AppError) async throws {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncode(form).utf8)

        let response = try await http.send(request)
        guard (200..<300).contains(response.status),
              let decoded = try? JSONDecoder().decode(TokenResponse.self, from: response.body)
        else {
            if failureError == .sessionExpired { logOut() }
            throw failureError
        }

        accessTokenValue = decoded.access_token
        expiresAt = now().addingTimeInterval(TimeInterval(decoded.expires_in))
        if let refresh = decoded.refresh_token { store.writeRefreshToken(refresh) }
    }

    private func formEncode(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter SpotifyAuthTests 2>&1 | tail -20`
Expected: PASS, 8 tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/FloatingLyricCore Tests/FloatingLyricCoreTests/SpotifyAuthTests.swift
git commit -m "feat: Spotify PKCE token exchange and refresh with expiry margin"
```

---

### Task 7: OAuth callback listener

**Files:**
- Create: `Sources/FloatingLyricCore/Auth/CallbackListener.swift`
- Test: `Tests/FloatingLyricCoreTests/CallbackListenerTests.swift`

**Interfaces:**
- Consumes: `AppError` (Task 1).
- Produces: `struct CallbackResult { let code: String?; let state: String?; let error: String? }`; `enum CallbackListener { static let candidatePorts = [8888, 8889, 8890]; static func parseRequestLine(_ line: String) -> CallbackResult?; static func waitForCallback(port: UInt16) async throws -> CallbackResult }`.
- The parsing half is pure and tested; the socket half is exercised by one round-trip test against a real loopback connection.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import FloatingLyricCore

final class CallbackListenerTests: XCTestCase {
    func test_parsesCodeAndStateFromRequestLine() {
        let result = CallbackListener.parseRequestLine("GET /callback?code=ABC&state=XYZ HTTP/1.1")
        XCTAssertEqual(result?.code, "ABC")
        XCTAssertEqual(result?.state, "XYZ")
        XCTAssertNil(result?.error)
    }

    func test_parsesErrorWhenUserDeniesAccess() {
        let result = CallbackListener.parseRequestLine("GET /callback?error=access_denied&state=XYZ HTTP/1.1")
        XCTAssertEqual(result?.error, "access_denied")
        XCTAssertNil(result?.code)
    }

    func test_percentDecodesParameters() {
        let result = CallbackListener.parseRequestLine("GET /callback?code=a%2Bb%2Fc&state=S HTTP/1.1")
        XCTAssertEqual(result?.code, "a+b/c")
    }

    func test_ignoresRequestsForOtherPaths() {
        XCTAssertNil(CallbackListener.parseRequestLine("GET /favicon.ico HTTP/1.1"))
    }

    func test_ignoresNonGetRequests() {
        XCTAssertNil(CallbackListener.parseRequestLine("POST /callback?code=A HTTP/1.1"))
    }

    func test_ignoresGarbage() {
        XCTAssertNil(CallbackListener.parseRequestLine(""))
        XCTAssertNil(CallbackListener.parseRequestLine("hello"))
    }

    func test_listenerReceivesARealLoopbackRedirect() async throws {
        let port: UInt16 = 8899
        let task = Task { try await CallbackListener.waitForCallback(port: port) }
        try await Task.sleep(nanoseconds: 300_000_000)

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/callback?code=REAL&state=S")!)
        request.timeoutInterval = 5
        _ = try? await URLSession.shared.data(for: request)

        let result = try await task.value
        XCTAssertEqual(result.code, "REAL")
        XCTAssertEqual(result.state, "S")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CallbackListenerTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'CallbackListener' in scope`.

- [ ] **Step 3: Implement `CallbackListener.swift`**

```swift
import Foundation
import Network

public struct CallbackResult: Equatable, Sendable {
    public let code: String?
    public let state: String?
    public let error: String?
}

public enum CallbackListener {
    public static let candidatePorts: [UInt16] = [8888, 8889, 8890]

    public static func redirectURI(port: UInt16) -> String {
        "http://127.0.0.1:\(port)/callback"
    }

    /// Parses the first line of an HTTP request, e.g.
    /// `GET /callback?code=ABC&state=XYZ HTTP/1.1`.
    public static func parseRequestLine(_ line: String) -> CallbackResult? {
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return nil }
        guard let components = URLComponents(string: "http://127.0.0.1" + parts[1]),
              components.path == "/callback" else { return nil }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        let result = CallbackResult(code: value("code"), state: value("state"),
                                    error: value("error"))
        guard result.code != nil || result.error != nil else { return nil }
        return result
    }

    /// Serves exactly one `/callback` request, then shuts down.
    public static func waitForCallback(port: UInt16) async throws -> CallbackResult {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw AppError.portUnavailable }
        let listener = try NWListener(using: .tcp, on: nwPort)

        return try await withCheckedThrowingContinuation { continuation in
            let finished = Finished()

            listener.stateUpdateHandler = { state in
                if case .failed = state, finished.claim() {
                    listener.cancel()
                    continuation.resume(throwing: AppError.portUnavailable)
                }
            }

            listener.newConnectionHandler = { connection in
                connection.start(queue: .global())
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                    let text = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
                    let firstLine = text.components(separatedBy: "\r\n").first ?? ""
                    let parsed = parseRequestLine(firstLine)

                    let body = parsed?.code != nil
                        ? "<h2>FloatingLyric is connected.</h2><p>You can close this tab.</p>"
                        : "<h2>Login failed.</h2><p>Return to FloatingLyric and try again.</p>"
                    let response = """
                    HTTP/1.1 200 OK\r
                    Content-Type: text/html; charset=utf-8\r
                    Content-Length: \(body.utf8.count)\r
                    Connection: close\r
                    \r
                    \(body)
                    """
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                        guard let parsed, finished.claim() else { return }
                        listener.cancel()
                        continuation.resume(returning: parsed)
                    })
                }
            }

            listener.start(queue: .global())
        }
    }

    /// One-shot guard so the continuation is resumed exactly once.
    private final class Finished: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func claim() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CallbackListenerTests 2>&1 | tail -20`
Expected: PASS, 7 tests. (The loopback test binds port 8899; if the machine blocks it, the test fails loudly rather than silently passing.)

- [ ] **Step 5: Commit**

```bash
git add Sources/FloatingLyricCore/Auth/CallbackListener.swift Tests/FloatingLyricCoreTests/CallbackListenerTests.swift
git commit -m "feat: one-shot loopback listener for the OAuth redirect"
```

---

### Task 8: Now-playing poller

**Files:**
- Create: `Sources/FloatingLyricCore/Playback/NowPlaying.swift`
- Create: `Sources/FloatingLyricCore/Playback/NowPlayingPoller.swift`
- Test: `Tests/FloatingLyricCoreTests/NowPlayingPollerTests.swift`

**Interfaces:**
- Consumes: `HTTPClient`, `AppError` (Task 1); `SpotifyAuth` (Task 6); `TrackIdentity` (Task 2).
- Produces: `struct NowPlaying: Equatable, Sendable { let track: TrackIdentity; let progressMs: Int; let isPlaying: Bool; let albumArtURL: URL? }`; `enum PlaybackState: Equatable, Sendable { case idle; case playing(NowPlaying); case paused(NowPlaying); case failed(AppError) }`; `final class NowPlayingPoller { static let playingIntervalMs = 3000; static let idleIntervalMs = 10000; init(auth: SpotifyAuth, http: HTTPClient); func pollOnce() async -> PlaybackState; func start(onState: @escaping (PlaybackState) -> Void); func stop() }`.
- `pollOnce()` is the tested unit; `start()` just schedules it on a `Task` loop using `intervalMs(for:)`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import FloatingLyricCore

final class NowPlayingPollerTests: XCTestCase {
    private func makePoller(_ responses: [HTTPResponse]) -> (NowPlayingPoller, StubHTTPClient) {
        let http = StubHTTPClient()
        http.responses = responses
        let auth = SpotifyAuth(clientID: "CID", http: StubHTTPClient(),
                               store: InMemoryTokenStore(token: "RT"))
        // Prime a valid access token without a network round-trip.
        auth.setAccessTokenForTesting("AT", expiresIn: 3600)
        return (NowPlayingPoller(auth: auth, http: http), http)
    }

    private static let playingJSON = """
    {"is_playing":true,"progress_ms":42000,
     "item":{"id":"track1","name":"Blinding Lights","duration_ms":200040,
             "artists":[{"name":"The Weeknd"},{"name":"Someone Else"}],
             "album":{"name":"After Hours","images":[{"url":"https://img/1.jpg"}]}}}
    """

    func test_parsesPlayingTrack() async {
        let (poller, _) = makePoller([.json(Self.playingJSON)])
        guard case .playing(let np) = await poller.pollOnce() else {
            return XCTFail("expected .playing")
        }
        XCTAssertEqual(np.track.id, "track1")
        XCTAssertEqual(np.track.title, "Blinding Lights")
        XCTAssertEqual(np.track.artist, "The Weeknd")   // first artist only
        XCTAssertEqual(np.track.album, "After Hours")
        XCTAssertEqual(np.track.durationMs, 200040)
        XCTAssertEqual(np.progressMs, 42000)
        XCTAssertEqual(np.albumArtURL?.absoluteString, "https://img/1.jpg")
    }

    func test_isPlayingFalseYieldsPausedState() async {
        let json = Self.playingJSON.replacingOccurrences(of: "\"is_playing\":true",
                                                         with: "\"is_playing\":false")
        let (poller, _) = makePoller([.json(json)])
        guard case .paused = await poller.pollOnce() else { return XCTFail("expected .paused") }
    }

    func test_noContentYieldsIdle() async {
        let (poller, _) = makePoller([HTTPResponse(status: 204, body: Data(), headers: [:])])
        XCTAssertEqual(await poller.pollOnce(), .idle)
    }

    func test_nullItemYieldsIdle() async {
        let (poller, _) = makePoller([.json(#"{"is_playing":false,"item":null}"#)])
        XCTAssertEqual(await poller.pollOnce(), .idle)
    }

    func test_episodesWithoutTrackFieldsYieldIdle() async {
        let (poller, _) = makePoller([.json(#"{"is_playing":true,"progress_ms":1,"item":{"id":"e1"}}"#)])
        XCTAssertEqual(await poller.pollOnce(), .idle)
    }

    func test_rateLimitReportsRetryAfter() async {
        let (poller, _) = makePoller([
            HTTPResponse(status: 429, body: Data(), headers: ["Retry-After": "7"])
        ])
        XCTAssertEqual(await poller.pollOnce(), .failed(.rateLimited(retryAfter: 7)))
    }

    func test_unauthorizedInvalidatesTokenAndRetriesExactlyOnce() async {
        let (poller, http) = makePoller([
            HTTPResponse(status: 401, body: Data(), headers: [:]),
            HTTPResponse(status: 401, body: Data(), headers: [:]),
        ])
        let state = await poller.pollOnce()
        XCTAssertEqual(http.recordedRequests.count, 2, "one original call plus one retry")
        XCTAssertEqual(state, .failed(.sessionExpired))
    }

    func test_networkErrorIsReported() async {
        let http = StubHTTPClient()
        http.errorToThrow = AppError.network("offline")
        let auth = SpotifyAuth(clientID: "CID", http: StubHTTPClient(),
                               store: InMemoryTokenStore(token: "RT"))
        auth.setAccessTokenForTesting("AT", expiresIn: 3600)
        let poller = NowPlayingPoller(auth: auth, http: http)
        XCTAssertEqual(await poller.pollOnce(), .failed(.network("offline")))
    }

    func test_requestCarriesBearerToken() async {
        let (poller, http) = makePoller([.json(Self.playingJSON)])
        _ = await poller.pollOnce()
        XCTAssertEqual(http.recordedRequests.first?.value(forHTTPHeaderField: "Authorization"),
                       "Bearer AT")
        XCTAssertEqual(http.recordedRequests.first?.url?.path,
                       "/v1/me/player/currently-playing")
    }

    func test_pollIntervalIsShorterWhilePlaying() {
        XCTAssertEqual(NowPlayingPoller.intervalMs(for: .idle), 10_000)
        XCTAssertEqual(NowPlayingPoller.intervalMs(for: .failed(.network("x"))), 10_000)
        let np = NowPlaying(track: TrackIdentity(id: "t", title: "a", artist: "b",
                                                 album: "c", durationMs: 1),
                            progressMs: 0, isPlaying: true, albumArtURL: nil)
        XCTAssertEqual(NowPlayingPoller.intervalMs(for: .playing(np)), 3_000)
        XCTAssertEqual(NowPlayingPoller.intervalMs(for: .paused(np)), 10_000)
    }
}
```

- [ ] **Step 2: Add the test hook to `SpotifyAuth`**

Append to `SpotifyAuth`:

```swift
    /// Test seam: installs an access token without a network round-trip.
    public func setAccessTokenForTesting(_ token: String, expiresIn: TimeInterval) {
        accessTokenValue = token
        expiresAt = now().addingTimeInterval(expiresIn)
    }
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter NowPlayingPollerTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'NowPlayingPoller' in scope`.

- [ ] **Step 4: Implement `NowPlaying.swift`**

```swift
import Foundation

public struct NowPlaying: Equatable, Sendable {
    public let track: TrackIdentity
    public let progressMs: Int
    public let isPlaying: Bool
    public let albumArtURL: URL?

    public init(track: TrackIdentity, progressMs: Int, isPlaying: Bool, albumArtURL: URL?) {
        self.track = track
        self.progressMs = progressMs
        self.isPlaying = isPlaying
        self.albumArtURL = albumArtURL
    }
}

public enum PlaybackState: Equatable, Sendable {
    case idle
    case playing(NowPlaying)
    case paused(NowPlaying)
    case failed(AppError)

    public var nowPlaying: NowPlaying? {
        switch self {
        case .playing(let np), .paused(let np): return np
        case .idle, .failed: return nil
        }
    }
}
```

- [ ] **Step 5: Implement `NowPlayingPoller.swift`**

```swift
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
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter NowPlayingPollerTests 2>&1 | tail -20`
Expected: PASS, 10 tests.

- [ ] **Step 7: Commit**

```bash
git add Sources/FloatingLyricCore/Playback Sources/FloatingLyricCore/Auth/SpotifyAuth.swift Tests/FloatingLyricCoreTests/NowPlayingPollerTests.swift
git commit -m "feat: now-playing poller with 401 retry, 429 backoff and idle handling"
```

---

### Task 9: Lyrics cache and LRCLIB provider

**Files:**
- Create: `Sources/FloatingLyricCore/Lyrics/LyricsCache.swift`
- Create: `Sources/FloatingLyricCore/Lyrics/LyricsProvider.swift`
- Test: `Tests/FloatingLyricCoreTests/LyricsProviderTests.swift`

**Interfaces:**
- Consumes: `HTTPClient` (Task 1); `TrackIdentity`, `LyricsResult`, `LRCParser` (Task 2).
- Produces: `protocol LyricsCaching { func read(trackID: String, now: Date) -> LyricsResult?; func write(_ result: LyricsResult, trackID: String, now: Date) }`; `final class LyricsCache: LyricsCaching` (directory-backed, `init(directory: URL)`, default `~/Library/Application Support/FloatingLyric/lyrics`); `final class LyricsProvider { static let negativeTTL: TimeInterval = 86_400; init(http: HTTPClient, cache: LyricsCaching, now: @escaping () -> Date = Date.init); func lyrics(for track: TrackIdentity) async -> LyricsResult }`.
- Search-result acceptance: absolute duration difference ≤ 5 seconds.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import FloatingLyricCore

final class LyricsProviderTests: XCTestCase {
    private let track = TrackIdentity(id: "t1", title: "Blinding Lights",
                                      artist: "The Weeknd", album: "After Hours",
                                      durationMs: 200_040)

    private final class MemoryCache: LyricsCaching, @unchecked Sendable {
        var stored: [String: (LyricsResult, Date)] = [:]
        var readCount = 0
        func read(trackID: String, now: Date) -> LyricsResult? {
            readCount += 1
            guard let (result, date) = stored[trackID] else { return nil }
            if result == .notFound,
               now.timeIntervalSince(date) > LyricsProvider.negativeTTL { return nil }
            return result
        }
        func write(_ result: LyricsResult, trackID: String, now: Date) {
            stored[trackID] = (result, now)
        }
    }

    private func makeProvider(_ responses: [HTTPResponse],
                              cache: MemoryCache = MemoryCache(),
                              now: @escaping () -> Date = { Date(timeIntervalSince1970: 0) })
    -> (LyricsProvider, StubHTTPClient, MemoryCache) {
        let http = StubHTTPClient()
        http.responses = responses
        return (LyricsProvider(http: http, cache: cache, now: now), http, cache)
    }

    func test_returnsSyncedLyricsFromDirectLookup() async {
        let json = #"{"syncedLyrics":"[00:10.00]Hello","plainLyrics":"Hello"}"#
        let (provider, http, _) = makeProvider([.json(json)])

        let result = await provider.lyrics(for: track)

        XCTAssertEqual(result, .synced([LyricLine(timeMs: 10_000, text: "Hello")]))
        let url = http.recordedRequests[0].url!
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        func value(_ n: String) -> String? { items.first { $0.name == n }?.value }
        XCTAssertEqual(url.host, "lrclib.net")
        XCTAssertEqual(url.path, "/api/get")
        XCTAssertEqual(value("artist_name"), "The Weeknd")
        XCTAssertEqual(value("track_name"), "Blinding Lights")
        XCTAssertEqual(value("album_name"), "After Hours")
        XCTAssertEqual(value("duration"), "200", "duration must be whole seconds")
    }

    func test_sendsRequiredUserAgent() async {
        let (provider, http, _) = makeProvider([.json(#"{"syncedLyrics":"[00:01.00]x"}"#)])
        _ = await provider.lyrics(for: track)
        XCTAssertEqual(http.recordedRequests[0].value(forHTTPHeaderField: "User-Agent"),
                       "FloatingLyric/1.0 (macOS lyrics overlay; contact via app repository)")
    }

    func test_fallsBackToPlainLyricsWhenSyncedIsNull() async {
        let (provider, _, _) = makeProvider([.json(#"{"syncedLyrics":null,"plainLyrics":"Just words"}"#)])
        XCTAssertEqual(await provider.lyrics(for: track), .plain("Just words"))
    }

    func test_emptySyncedStringIsTreatedAsMissing() async {
        let (provider, _, _) = makeProvider([.json(#"{"syncedLyrics":"","plainLyrics":"Words"}"#)])
        XCTAssertEqual(await provider.lyrics(for: track), .plain("Words"))
    }

    func test_notFoundOnDirectLookupFallsBackToSearch() async {
        let searchJSON = """
        [{"duration":198.5,"syncedLyrics":"[00:05.00]From search","plainLyrics":"From search"}]
        """
        let (provider, http, _) = makeProvider([
            HTTPResponse(status: 404, body: Data(), headers: [:]),
            .json(searchJSON),
        ])

        let result = await provider.lyrics(for: track)

        XCTAssertEqual(result, .synced([LyricLine(timeMs: 5_000, text: "From search")]))
        XCTAssertEqual(http.recordedRequests[1].url?.path, "/api/search")
    }

    func test_searchResultOutsideDurationToleranceIsRejected() async {
        let searchJSON = """
        [{"duration":150.0,"syncedLyrics":"[00:05.00]Wrong song","plainLyrics":"Wrong"}]
        """
        let (provider, _, _) = makeProvider([
            HTTPResponse(status: 404, body: Data(), headers: [:]),
            .json(searchJSON),
        ])
        XCTAssertEqual(await provider.lyrics(for: track), .notFound)
    }

    func test_searchPicksFirstResultWithinTolerance() async {
        let searchJSON = """
        [{"duration":120.0,"syncedLyrics":"[00:05.00]Wrong","plainLyrics":"w"},
         {"duration":204.0,"syncedLyrics":"[00:05.00]Right","plainLyrics":"r"}]
        """
        let (provider, _, _) = makeProvider([
            HTTPResponse(status: 404, body: Data(), headers: [:]),
            .json(searchJSON),
        ])
        XCTAssertEqual(await provider.lyrics(for: track),
                       .synced([LyricLine(timeMs: 5_000, text: "Right")]))
    }

    func test_emptySearchResultsYieldNotFound() async {
        let (provider, _, _) = makeProvider([
            HTTPResponse(status: 404, body: Data(), headers: [:]),
            .json("[]"),
        ])
        XCTAssertEqual(await provider.lyrics(for: track), .notFound)
    }

    func test_networkErrorYieldsNotFoundAndIsNotCached() async {
        let http = StubHTTPClient()
        http.errorToThrow = AppError.network("offline")
        let cache = MemoryCache()
        let provider = LyricsProvider(http: http, cache: cache,
                                      now: { Date(timeIntervalSince1970: 0) })
        XCTAssertEqual(await provider.lyrics(for: track), .notFound)
        XCTAssertTrue(cache.stored.isEmpty, "transient failures must not poison the cache")
    }

    func test_cacheHitSkipsTheNetwork() async {
        let cache = MemoryCache()
        cache.stored["t1"] = (.synced([LyricLine(timeMs: 1, text: "cached")]),
                              Date(timeIntervalSince1970: 0))
        let (provider, http, _) = makeProvider([], cache: cache)

        XCTAssertEqual(await provider.lyrics(for: track),
                       .synced([LyricLine(timeMs: 1, text: "cached")]))
        XCTAssertTrue(http.recordedRequests.isEmpty)
    }

    func test_successfulLookupIsWrittenToCache() async {
        let cache = MemoryCache()
        let (provider, _, _) = makeProvider([.json(#"{"syncedLyrics":"[00:10.00]Hello"}"#)],
                                            cache: cache)
        _ = await provider.lyrics(for: track)
        XCTAssertEqual(cache.stored["t1"]?.0, .synced([LyricLine(timeMs: 10_000, text: "Hello")]))
    }

    func test_notFoundIsCachedAndExpiresAfterTwentyFourHours() async {
        var now = Date(timeIntervalSince1970: 0)
        let cache = MemoryCache()
        let http = StubHTTPClient()
        http.responses = [HTTPResponse(status: 404, body: Data(), headers: [:]), .json("[]")]
        let provider = LyricsProvider(http: http, cache: cache, now: { now })

        XCTAssertEqual(await provider.lyrics(for: track), .notFound)
        XCTAssertEqual(cache.stored["t1"]?.0, .notFound)

        // Within the TTL: served from cache, no new requests.
        now = Date(timeIntervalSince1970: 3600)
        _ = await provider.lyrics(for: track)
        XCTAssertEqual(http.recordedRequests.count, 2)

        // Past the TTL: refetched.
        now = Date(timeIntervalSince1970: 86_401)
        http.responses = [.json(#"{"syncedLyrics":"[00:02.00]Now here"}"#)]
        XCTAssertEqual(await provider.lyrics(for: track),
                       .synced([LyricLine(timeMs: 2_000, text: "Now here")]))
    }

    func test_diskCacheRoundTripsThroughAFileURL() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let cache = LyricsCache(directory: dir)
        let now = Date(timeIntervalSince1970: 500)
        let value = LyricsResult.synced([LyricLine(timeMs: 7, text: "disk")])

        cache.write(value, trackID: "abc", now: now)
        XCTAssertEqual(cache.read(trackID: "abc", now: now), value)
        XCTAssertNil(cache.read(trackID: "missing", now: now))
        try? FileManager.default.removeItem(at: dir)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LyricsProviderTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'LyricsProvider' in scope`.

- [ ] **Step 3: Implement `LyricsCache.swift`**

```swift
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
```

- [ ] **Step 4: Implement `LyricsProvider.swift`**

```swift
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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter LyricsProviderTests 2>&1 | tail -20`
Expected: PASS, 13 tests.

- [ ] **Step 6: Run the whole suite**

Run: `swift test 2>&1 | tail -10`
Expected: PASS, all tests from Tasks 1–9.

- [ ] **Step 7: Commit**

```bash
git add Sources/FloatingLyricCore/Lyrics Tests/FloatingLyricCoreTests/LyricsProviderTests.swift
git commit -m "feat: LRCLIB provider with search fallback and cached negative results"
```

---

### Task 10: Floating panel and lyric view

**Files:**
- Create: `Sources/FloatingLyricCore/UI/LyricViewModel.swift`
- Create: `Sources/FloatingLyricCore/UI/LyricView.swift`
- Create: `Sources/FloatingLyricCore/UI/FloatingPanel.swift`
- Create: `Sources/FloatingLyricCore/UI/SetupWindow.swift`

**Interfaces:**
- Consumes: `LyricsDocument` (Task 3), `LyricsResult`/`LyricLine` (Task 2), `PlaybackState`/`NowPlaying` (Task 8), `AppError` (Task 1), `Defaults` (Task 6).
- Produces: `@MainActor final class LyricViewModel: ObservableObject` with `@Published var title: String`, `@Published var artist: String`, `@Published var display: Display`, `@Published var positionMs: Int`, `@Published var durationMs: Int`, `@Published var fontSize: Int`, and `func apply(state: PlaybackState)`, `func apply(lyrics: LyricsResult)`, `func tick(positionMs: Int)`. `enum Display { case message(String); case synced(LyricsDocument, currentIndex: Int?); case plain(String) }`.
- Produces: `@MainActor final class FloatingPanel: NSPanel` with `init(viewModel: LyricViewModel)`, `func applyPreferences()`, `func restoreFrame()`, `func saveFrame()`.
- Produces: `@MainActor final class SetupWindow: NSWindowController` with `init(onSave: @escaping (String) -> Void)`.

No unit tests here: this task is rendering. Its logic (`index(atPositionMs:offsetMs:)`) was tested in Task 3. Verification is by running the app in Task 11.

- [ ] **Step 1: Implement `LyricViewModel.swift`**

```swift
import Foundation
import SwiftUI

@MainActor
public final class LyricViewModel: ObservableObject {
    public enum Display: Equatable {
        case message(String)
        case synced(LyricsDocument, currentIndex: Int?)
        case plain(String)
    }

    @Published public var title: String = "FloatingLyric"
    @Published public var artist: String = ""
    @Published public var display: Display = .message("Set up Spotify to begin")
    @Published public var positionMs: Int = 0
    @Published public var durationMs: Int = 0
    @Published public var fontSize: Int = Defaults.fontSize
    @Published public var isOffline: Bool = false

    private var document: LyricsDocument?

    public init() {}

    public func apply(state: PlaybackState) {
        switch state {
        case .idle:
            title = "Nothing playing"
            artist = ""
            document = nil
            display = .message("Nothing playing")
            isOffline = false
        case .playing(let np), .paused(let np):
            title = np.track.title
            artist = np.track.artist
            durationMs = np.track.durationMs
            isOffline = false
        case .failed(let error):
            switch error {
            case .notConfigured, .notLoggedIn, .sessionExpired:
                document = nil
                display = .message(error.displayMessage)
            case .network:
                isOffline = true       // keep whatever lyrics are on screen
            case .rateLimited, .badResponse, .portUnavailable, .authCancelled:
                break                  // transient; leave the current display alone
            }
        }
    }

    public func apply(lyrics: LyricsResult) {
        switch lyrics {
        case .synced(let lines):
            let doc = LyricsDocument(lines: lines)
            document = doc
            display = .synced(doc, currentIndex: doc.index(atPositionMs: positionMs,
                                                           offsetMs: Defaults.syncOffsetMs))
        case .plain(let text):
            document = nil
            display = .plain(text)
        case .notFound:
            document = nil
            display = .message("No lyrics found")
        }
    }

    public func tick(positionMs newPosition: Int) {
        positionMs = newPosition
        guard let document else { return }
        let index = document.index(atPositionMs: newPosition, offsetMs: Defaults.syncOffsetMs)
        if case .synced(_, let current) = display, current == index { return }
        display = .synced(document, currentIndex: index)
    }
}
```

- [ ] **Step 2: Implement `LyricView.swift`**

```swift
import SwiftUI

public struct LyricView: View {
    @ObservedObject var model: LyricViewModel

    public init(model: LyricViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
                .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
            footer
        }
        .padding(16)
        .frame(minWidth: 360, minHeight: 180)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.system(size: 10))
            Text(model.title).fontWeight(.semibold).lineLimit(1)
            if !model.artist.isEmpty {
                Text("— \(model.artist)").lineLimit(1)
            }
            Spacer()
            if model.isOffline {
                Image(systemName: "wifi.slash").font(.system(size: 10))
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var content: some View {
        switch model.display {
        case .message(let text):
            Text(text)
                .font(.system(size: CGFloat(model.fontSize), weight: .medium))
                .foregroundStyle(.secondary)
        case .plain(let text):
            ScrollView {
                Text(text)
                    .font(.system(size: CGFloat(model.fontSize) - 2))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .synced(let document, let currentIndex):
            syncedLines(document: document, currentIndex: currentIndex)
        }
    }

    private func syncedLines(document: LyricsDocument, currentIndex: Int?) -> some View {
        let center = currentIndex ?? -1
        let window = (center - 1)...(center + 2)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(window), id: \.self) { index in
                if document.lines.indices.contains(index) {
                    Text(document.lines[index].text)
                        .font(.system(size: CGFloat(model.fontSize),
                                      weight: index == center ? .bold : .regular))
                        .foregroundStyle(index == center ? AnyShapeStyle(.primary)
                                                         : AnyShapeStyle(.tertiary))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: currentIndex)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            ProgressView(value: progressFraction)
                .progressViewStyle(.linear)
            HStack {
                Text(timecode(model.positionMs))
                Spacer()
                Text(timecode(model.durationMs))
            }
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var progressFraction: Double {
        guard model.durationMs > 0 else { return 0 }
        return min(1, Double(model.positionMs) / Double(model.durationMs))
    }

    private func timecode(_ ms: Int) -> String {
        let total = max(0, ms) / 1000
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
```

- [ ] **Step 3: Implement `FloatingPanel.swift`**

```swift
import AppKit
import SwiftUI

@MainActor
public final class FloatingPanel: NSPanel {
    public init(viewModel: LyricViewModel) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.masksToBounds = true

        let hosting = NSHostingView(rootView: LyricView(model: viewModel))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: blur.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])

        contentView = blur
        restoreFrame()
        applyPreferences()
    }

    public func applyPreferences() {
        ignoresMouseEvents = Defaults.clickThrough
        isMovableByWindowBackground = !Defaults.lockPosition && !Defaults.clickThrough
    }

    public func restoreFrame() {
        guard let saved = Defaults.panelFrame else {
            center()
            return
        }
        let frame = NSRectFromString(saved)
        // A saved frame can point at a display that is no longer attached.
        let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        if visible, frame.width > 100, frame.height > 60 {
            setFrame(frame, display: false)
        } else {
            center()
        }
    }

    public func saveFrame() {
        Defaults.panelFrame = NSStringFromRect(frame)
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}
```

- [ ] **Step 4: Implement `SetupWindow.swift`**

```swift
import AppKit
import SwiftUI

@MainActor
public final class SetupWindow: NSWindowController {
    public init(onSave: @escaping (String) -> Void) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Set up FloatingLyric"
        window.center()
        super.init(window: window)

        let view = SetupView(initialClientID: Defaults.clientID ?? "") { [weak self] clientID in
            onSave(clientID)
            self?.close()
        }
        window.contentView = NSHostingView(rootView: view)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    public func present() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    public override func close() {
        super.close()
        NSApp.setActivationPolicy(.accessory)
    }
}

private struct SetupView: View {
    @State var clientID: String
    let onSave: (String) -> Void

    init(initialClientID: String, onSave: @escaping (String) -> Void) {
        _clientID = State(initialValue: initialClientID)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect your Spotify account").font(.title2.bold())

            VStack(alignment: .leading, spacing: 8) {
                step(1, "Open developer.spotify.com/dashboard and click Create app.")
                step(2, "Name it anything, e.g. FloatingLyric.")
                step(3, "Set the Redirect URI to exactly:")
                Text("http://127.0.0.1:8888/callback")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(6)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                step(4, "Tick “Web API”, save, then copy the Client ID below.")
            }
            .font(.callout)

            TextField("Client ID", text: $clientID)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            HStack {
                Link("Open Spotify Dashboard",
                     destination: URL(string: "https://developer.spotify.com/dashboard")!)
                Spacer()
                Button("Save and Log In") { onSave(clientID.trimmingCharacters(in: .whitespaces)) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(clientID.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).").monospacedDigit().foregroundStyle(.secondary)
            Text(text)
        }
    }
}
```

- [ ] **Step 5: Verify it builds**

Run: `swift build 2>&1 | tail -20`
Expected: build succeeds with no errors.

- [ ] **Step 6: Commit**

```bash
git add Sources/FloatingLyricCore/UI
git commit -m "feat: floating lyric panel, view model and first-run setup window"
```

---

### Task 11: Menu bar, coordinator, and a running app

**Files:**
- Create: `Sources/FloatingLyricCore/App/MenuBarController.swift`
- Create: `Sources/FloatingLyricCore/App/AppCoordinator.swift`
- Modify: `Sources/FloatingLyricCore/App/AppDelegate.swift` (replace the Task 1 stand-in)
- Create: `Resources/Info.plist`

**Interfaces:**
- Consumes: everything from Tasks 1–10.
- Produces: `@MainActor final class AppCoordinator` with `func start()`, `func logIn()`, `func logOut()`, `func reconfigure(clientID: String)`, `var viewModel: LyricViewModel`; `@MainActor final class MenuBarController` with `init(coordinator: AppCoordinator)`; `enum FloatingLyricApp { static func run() }`.

- [ ] **Step 1: Implement `AppCoordinator.swift`**

```swift
import AppKit
import Foundation

@MainActor
public final class AppCoordinator {
    public let viewModel = LyricViewModel()

    private let http: HTTPClient = URLSessionHTTPClient()
    private let store: TokenStore = KeychainStore()
    private let cache: LyricsCaching = LyricsCache()
    private let clock = PlayheadClock()

    private var auth: SpotifyAuth?
    private var poller: NowPlayingPoller?
    private var lyricsProvider: LyricsProvider?
    private var panel: FloatingPanel?
    private var setupWindow: SetupWindow?
    private var tickTimer: Timer?
    private var currentTrackID: String?
    private var lyricsTask: Task<Void, Never>?

    public init() {}

    public func start() {
        let panel = FloatingPanel(viewModel: viewModel)
        panel.orderFrontRegardless()
        self.panel = panel

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak panel] _ in
            MainActor.assumeIsolated { panel?.saveFrame() }
        }

        lyricsProvider = LyricsProvider(http: http, cache: cache)
        startTicking()
        buildSession()
    }

    // MARK: - Session

    private func buildSession() {
        poller?.stop()

        guard let clientID = Defaults.clientID else {
            viewModel.apply(state: .failed(.notConfigured))
            showSetup()
            return
        }

        let auth = SpotifyAuth(clientID: clientID, http: http, store: store)
        self.auth = auth

        guard auth.isLoggedIn else {
            viewModel.apply(state: .failed(.notLoggedIn))
            return
        }

        let poller = NowPlayingPoller(auth: auth, http: http)
        self.poller = poller
        poller.start { [weak self] state in
            Task { @MainActor in self?.handle(state) }
        }
    }

    public func reconfigure(clientID: String) {
        Defaults.clientID = clientID
        buildSession()
        logIn()
    }

    public func logIn() {
        guard let auth else {
            showSetup()
            return
        }
        Task { @MainActor in
            let pkce = PKCE.generate()
            let state = PKCE.randomState()

            for port in CallbackListener.candidatePorts {
                let redirect = CallbackListener.redirectURI(port: port)
                let listener = Task { try await CallbackListener.waitForCallback(port: port) }
                try? await Task.sleep(nanoseconds: 200_000_000)

                guard !listener.isCancelled else { continue }
                NSWorkspace.shared.open(auth.authorizationURL(challenge: pkce.challenge,
                                                              state: state,
                                                              redirectURI: redirect))
                do {
                    let result = try await listener.value
                    guard result.state == state, let code = result.code else {
                        viewModel.apply(state: .failed(.authCancelled))
                        return
                    }
                    try await auth.exchange(code: code, verifier: pkce.verifier,
                                            redirectURI: redirect)
                    buildSession()
                    return
                } catch AppError.portUnavailable {
                    continue                       // try the next candidate port
                } catch {
                    viewModel.apply(state: .failed(.authCancelled))
                    return
                }
            }
            viewModel.apply(state: .failed(.portUnavailable))
        }
    }

    public func logOut() {
        poller?.stop()
        poller = nil
        auth?.logOut()
        currentTrackID = nil
        viewModel.apply(state: .failed(.notLoggedIn))
    }

    public func showSetup() {
        let window = SetupWindow { [weak self] clientID in
            self?.reconfigure(clientID: clientID)
        }
        setupWindow = window
        window.present()
    }

    public func togglePanel() {
        guard let panel else { return }
        panel.isVisible ? panel.orderOut(nil) : panel.orderFrontRegardless()
    }

    public func applyPanelPreferences() {
        panel?.applyPreferences()
        viewModel.fontSize = Defaults.fontSize
    }

    // MARK: - State plumbing

    private func handle(_ state: PlaybackState) {
        viewModel.apply(state: state)

        guard let np = state.nowPlaying else {
            if case .idle = state { currentTrackID = nil }
            return
        }

        // Every poll re-anchors, which covers ordinary drift, pause and seek alike.
        let now = Date().timeIntervalSinceReferenceDate
        clock.anchor(progressMs: np.progressMs, isPlaying: np.isPlaying, now: now)

        guard np.track.id != currentTrackID else { return }
        currentTrackID = np.track.id
        fetchLyrics(for: np.track)
    }

    private func fetchLyrics(for track: TrackIdentity) {
        lyricsTask?.cancel()
        viewModel.apply(lyrics: .notFound)
        guard let provider = lyricsProvider else { return }
        lyricsTask = Task { @MainActor [weak self] in
            let result = await provider.lyrics(for: track)
            guard !Task.isCancelled, self?.currentTrackID == track.id else { return }
            self?.viewModel.apply(lyrics: result)
        }
    }

    private func startTicking() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.viewModel.tick(positionMs: self.clock.positionMs(
                    now: Date().timeIntervalSinceReferenceDate))
            }
        }
    }
}
```

- [ ] **Step 2: Implement `MenuBarController.swift`**

```swift
import AppKit

@MainActor
public final class MenuBarController {
    private let statusItem: NSStatusItem
    private let coordinator: AppCoordinator
    private let offsetSlider = NSSlider(value: Double(Defaults.syncOffsetMs),
                                        minValue: -2000, maxValue: 2000,
                                        target: nil, action: nil)

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "music.note.list",
                                           accessibilityDescription: "FloatingLyric")
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(item("Show / Hide Lyrics", #selector(toggleLyrics), key: "l"))
        menu.addItem(check("Lock Position", #selector(toggleLock), on: Defaults.lockPosition))
        menu.addItem(check("Click Through", #selector(toggleClickThrough), on: Defaults.clickThrough))
        menu.addItem(.separator())

        let fontMenu = NSMenu()
        for (label, size) in [("Small", 14), ("Medium", 18), ("Large", 24)] {
            let entry = item(label, #selector(setFontSize(_:)))
            entry.tag = size
            entry.state = Defaults.fontSize == size ? .on : .off
            fontMenu.addItem(entry)
        }
        let fontItem = NSMenuItem(title: "Font Size", action: nil, keyEquivalent: "")
        fontItem.submenu = fontMenu
        menu.addItem(fontItem)

        menu.addItem(sliderItem())
        menu.addItem(.separator())
        menu.addItem(item("Spotify Setup…", #selector(openSetup)))
        menu.addItem(item("Log Out", #selector(logOut)))
        menu.addItem(.separator())
        menu.addItem(item("Quit FloatingLyric", #selector(quit), key: "q"))
        return menu
    }

    private func sliderItem() -> NSMenuItem {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 44))
        let label = NSTextField(labelWithString: offsetLabel())
        label.frame = NSRect(x: 14, y: 24, width: 190, height: 16)
        label.font = .menuFont(ofSize: 12)
        label.tag = 99

        offsetSlider.frame = NSRect(x: 14, y: 4, width: 190, height: 20)
        offsetSlider.target = self
        offsetSlider.action = #selector(offsetChanged)

        container.addSubview(label)
        container.addSubview(offsetSlider)

        let entry = NSMenuItem()
        entry.view = container
        return entry
    }

    private func offsetLabel() -> String {
        String(format: "Sync offset: %+d ms", Defaults.syncOffsetMs)
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        return entry
    }

    private func check(_ title: String, _ action: Selector, on: Bool) -> NSMenuItem {
        let entry = item(title, action)
        entry.state = on ? .on : .off
        return entry
    }

    // MARK: - Actions

    @objc private func toggleLyrics() { coordinator.togglePanel() }

    @objc private func toggleLock(_ sender: NSMenuItem) {
        Defaults.lockPosition.toggle()
        sender.state = Defaults.lockPosition ? .on : .off
        coordinator.applyPanelPreferences()
    }

    @objc private func toggleClickThrough(_ sender: NSMenuItem) {
        Defaults.clickThrough.toggle()
        sender.state = Defaults.clickThrough ? .on : .off
        coordinator.applyPanelPreferences()
    }

    @objc private func setFontSize(_ sender: NSMenuItem) {
        Defaults.fontSize = sender.tag
        sender.menu?.items.forEach { $0.state = $0.tag == sender.tag ? .on : .off }
        coordinator.applyPanelPreferences()
    }

    @objc private func offsetChanged(_ sender: NSSlider) {
        Defaults.syncOffsetMs = Int(sender.doubleValue)
        if let label = sender.superview?.viewWithTag(99) as? NSTextField {
            label.stringValue = offsetLabel()
        }
    }

    @objc private func openSetup() { coordinator.showSetup() }
    @objc private func logOut() { coordinator.logOut() }
    @objc private func quit() { NSApp.terminate(nil) }
}
```

- [ ] **Step 3: Replace `AppDelegate.swift`**

```swift
import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var menuBar: MenuBarController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        menuBar = MenuBarController(coordinator: coordinator)
        coordinator.start()
    }

    public func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

public enum FloatingLyricApp {
    @MainActor
    public static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
```

- [ ] **Step 4: Update `main.swift`**

```swift
import FloatingLyricCore

FloatingLyricApp.run()
```

- [ ] **Step 5: Write `Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>FloatingLyric</string>
    <key>CFBundleDisplayName</key>       <string>FloatingLyric</string>
    <key>CFBundleExecutable</key>        <string>FloatingLyric</string>
    <key>CFBundleIdentifier</key>        <string>com.floatinglyric.app</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key>           <string>1</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>LSUIElement</key>               <true/>
    <key>NSHumanReadableCopyright</key>  <string>FloatingLyric</string>
</dict>
</plist>
```

- [ ] **Step 6: Verify the whole suite still passes and the app builds**

Run: `swift test 2>&1 | tail -5 && swift build 2>&1 | tail -5`
Expected: all tests pass; build succeeds.

- [ ] **Step 7: Commit**

```bash
git add Sources Resources/Info.plist
git commit -m "feat: menu bar controller, coordinator and running app"
```

---

### Task 12: App bundle, DMG, and README

**Files:**
- Create: `build.sh`
- Create: `Resources/AppIcon.icns`
- Create: `README.md`

**Interfaces:**
- Consumes: the executable produced by Task 11 and `Resources/Info.plist`.
- Produces: `dist/FloatingLyric.app` and `dist/FloatingLyric.dmg`.

- [ ] **Step 1: Generate the app icon**

Generate the icon set directly with Python (no SVG rasterizer needed), then
convert it with `iconutil`. Run:

```bash
mkdir -p /tmp/AppIcon.iconset Resources
python3 - <<'PY'
import struct, zlib

def pixels(size):
    """Spotify-green rounded square with a dark eighth note, as raw RGBA rows."""
    px = bytearray()
    r = size * 0.22
    cx, cy = size / 2, size / 2
    for y in range(size):
        px.append(0)  # PNG filter byte: none
        for x in range(size):
            dx = max(r - x, x - (size - r), 0)
            dy = max(r - y, y - (size - r), 0)
            if dx * dx + dy * dy > r * r:
                px += bytes((0, 0, 0, 0))          # rounded corner: transparent
                continue
            stem = (cx + size * 0.06 <= x <= cx + size * 0.11
                    and cy - size * 0.26 <= y <= cy + size * 0.16)
            hx, hy = x - (cx - size * 0.02), y - (cy + size * 0.16)
            head = (hx / (size * 0.13)) ** 2 + (hy / (size * 0.10)) ** 2 <= 1
            flag = (cx + size * 0.11 <= x <= cx + size * 0.24
                    and cy - size * 0.26 <= y <= cy - size * 0.26 + (x - cx) * 0.5)
            px += bytes((11, 11, 11, 255)) if (stem or head or flag) else bytes((29, 185, 84, 255))
    return bytes(px)

def write_png(path, size):
    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
           + chunk(b"IDAT", zlib.compress(pixels(size), 9)) + chunk(b"IEND", b""))
    open(path, "wb").write(png)

for size in (16, 32, 128, 256, 512):
    write_png(f"/tmp/AppIcon.iconset/icon_{size}x{size}.png", size)
    write_png(f"/tmp/AppIcon.iconset/icon_{size}x{size}@2x.png", size * 2)
print("iconset written")
PY
iconutil -c icns /tmp/AppIcon.iconset -o Resources/AppIcon.icns
```

Verify: `ls -la Resources/AppIcon.icns` shows a non-empty file (a few hundred KB).
If `iconutil` rejects the set, fall back to a single-size icon:

```bash
sips -s format icns /tmp/AppIcon.iconset/icon_512x512.png --out Resources/AppIcon.icns
```

- [ ] **Step 2: Write `build.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

APP_NAME="FloatingLyric"
DIST="dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME.dmg"

echo "==> Building universal release binary"
swift build -c release --arch arm64 --arch x86_64

BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME
test -f "$BIN" || { echo "build produced no binary at $BIN"; exit 1; }

echo "==> Assembling $APP"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"

echo "==> Building $DMG"
STAGE="$DIST/stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo
echo "Done: $DMG"
echo "Install: open the DMG, drag $APP_NAME to Applications."
echo "First launch is blocked by Gatekeeper (unsigned). Fix it with either:"
echo "  right-click $APP_NAME in Applications -> Open -> Open"
echo "  xattr -cr /Applications/$APP_NAME.app"
```

Then: `chmod +x build.sh`

- [ ] **Step 3: Run the build and verify the artifacts**

Run:

```bash
./build.sh && ls -la dist/ && hdiutil imageinfo dist/FloatingLyric.dmg | head -5
```

Expected: `dist/FloatingLyric.app` and `dist/FloatingLyric.dmg` exist; `codesign --verify` printed no errors.

- [ ] **Step 4: Verify the app actually launches**

Run:

```bash
open dist/FloatingLyric.app
sleep 3
pgrep -x FloatingLyric && echo "RUNNING" || echo "NOT RUNNING"
```

Expected: `RUNNING`, a `music.note.list` icon appears in the menu bar, and the setup window opens (no Client ID configured yet). Then `pkill -x FloatingLyric`.

- [ ] **Step 5: Write `README.md`**

````markdown
# FloatingLyric

Time-synced lyrics for whatever you're playing on Spotify, in a translucent
always-on-top window on macOS. Lyrics follow your Spotify account, so they work
whether you're playing on this Mac, your phone, or a speaker.

![menu bar app · macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)

## Install

1. Download or build `FloatingLyric.dmg` (see Build below).
2. Open the DMG and drag **FloatingLyric** into **Applications**.
3. The app is unsigned, so macOS blocks the first launch. Either:
   - right-click **FloatingLyric** in Applications → **Open** → **Open**, or
   - run `xattr -cr /Applications/FloatingLyric.app`

## Set up Spotify (one time, ~2 minutes)

FloatingLyric talks to your own Spotify developer app, so no credentials are
shared with anyone.

1. Go to <https://developer.spotify.com/dashboard> and click **Create app**.
2. Name it anything (e.g. `FloatingLyric`).
3. Set **Redirect URI** to exactly:

   ```
   http://127.0.0.1:8888/callback
   ```

4. Tick **Web API**, save, then copy the **Client ID**.
5. Paste the Client ID into FloatingLyric's setup window and click
   **Save and Log In**. Your browser opens once to authorize.

Reading playback works on free Spotify accounts — Premium is not required. The
app only requests the `user-read-playback-state` scope; it can never control
playback or see anything else about your account.

## Using it

- The floating window shows the current line bright and its neighbours dimmed.
- Drag it anywhere. It stays above other apps and follows you across Spaces.
- Menu bar icon (♪ list):
  - **Show / Hide Lyrics** (⌘L)
  - **Lock Position** — stop accidental dragging
  - **Click Through** — make the window purely visual, clicks pass to what's behind
  - **Font Size** — Small / Medium / Large
  - **Sync offset** — nudge ±2000 ms if the highlight runs early or late
  - **Log Out**, **Quit** (⌘Q)

## Where lyrics come from

[LRCLIB](https://lrclib.net) — a free, community-maintained database of
time-synced lyrics. No API key needed. Songs without an entry show
"No lyrics found"; songs with only plain lyrics show the full text without
highlighting. Fetched lyrics are cached in
`~/Library/Application Support/FloatingLyric/lyrics/`.

## Build from source

```bash
swift test     # run the test suite
./build.sh     # -> dist/FloatingLyric.app and dist/FloatingLyric.dmg
```

Requires macOS 14+ and the Xcode command line tools. No third-party
dependencies.

## Troubleshooting

| Symptom | Fix |
|---|---|
| "App is damaged and can't be opened" | `xattr -cr /Applications/FloatingLyric.app` |
| Login browser page never returns | Redirect URI must be `http://127.0.0.1:8888/callback` exactly — not `localhost` |
| "Port 8888–8890 in use" | Quit whatever holds those ports, then log in again |
| Highlight runs early or late | Adjust **Sync offset** in the menu bar |
| "Session expired" | Menu bar → **Log Out**, then log in again |

## Privacy

The refresh token lives in your macOS Keychain. The Client ID lives in
`UserDefaults`. Nothing is sent anywhere except Spotify's API and LRCLIB.
````

- [ ] **Step 6: Commit**

```bash
git add build.sh README.md Resources/AppIcon.icns
git commit -m "feat: universal build script, DMG packaging and README"
```

---

## Final verification

- [ ] `swift test` — all tests pass, no network access required.
- [ ] `./build.sh` — produces `dist/FloatingLyric.dmg`.
- [ ] Install from the DMG, clear quarantine, launch, complete Spotify setup.
- [ ] Play a well-known song; lyrics appear and the highlight tracks the vocal.
- [ ] Pause — highlight freezes. Seek — highlight jumps within ~3 seconds.
- [ ] Change track — new lyrics load.
- [ ] Play a song with no LRCLIB entry — "No lyrics found", no crash.
- [ ] Toggle Lock Position, Click Through, each font size, and the sync offset.
- [ ] Quit and relaunch — still logged in, panel returns to its saved position.
