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
