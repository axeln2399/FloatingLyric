import XCTest
@testable import FloatingLyricCore

final class LoginPromptTests: XCTestCase {
    func test_aFirstRunGetsTheWalkthrough() {
        XCTAssertEqual(LoginPrompt.required(clientID: nil, isLoggedIn: false), .firstRun)
    }

    func test_aBlankClientIDCountsAsAFirstRun() {
        XCTAssertEqual(LoginPrompt.required(clientID: "", isLoggedIn: false), .firstRun)
        XCTAssertEqual(LoginPrompt.required(clientID: "   ", isLoggedIn: false), .firstRun)
    }

    func test_loggingOutLeavesTheClientIDBehindSoOnlyTheButtonIsNeeded() {
        XCTAssertEqual(LoginPrompt.required(clientID: "CID", isLoggedIn: false), .logIn)
    }

    func test_aLoggedInSessionIsNeverInterrupted() {
        XCTAssertNil(LoginPrompt.required(clientID: "CID", isLoggedIn: true))
    }

    /// A stored session with no Client ID cannot be refreshed, so setup wins.
    func test_setupWinsOverAStoredSessionWithNoClientID() {
        XCTAssertEqual(LoginPrompt.required(clientID: nil, isLoggedIn: true), .firstRun)
    }
}
