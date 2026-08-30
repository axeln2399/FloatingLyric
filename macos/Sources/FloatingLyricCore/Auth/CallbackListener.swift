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
