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
