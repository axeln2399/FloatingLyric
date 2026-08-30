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
