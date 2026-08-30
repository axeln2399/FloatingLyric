import XCTest
@testable import FloatingLyricCore

final class LoginPromptTests: XCTestCase {
    private func prompt(clientID: String?, isLoggedIn: Bool = false,
                        hasSignedInBefore: Bool = false) -> LoginPrompt? {
        LoginPrompt.required(clientID: clientID, isLoggedIn: isLoggedIn,
                             hasSignedInBefore: hasSignedInBefore)
    }

    func test_aFirstRunWithABuiltInClientIDIsJustAButton() {
        XCTAssertEqual(prompt(clientID: "CID"), .welcome)
    }

    func test_theWalkthroughOnlyAppearsWithNoClientIDAtAll() {
        XCTAssertEqual(prompt(clientID: nil), .setup)
        XCTAssertEqual(prompt(clientID: ""), .setup)
        XCTAssertEqual(prompt(clientID: "   "), .setup)
    }

    func test_signingOutAfterSigningInAsksToLogBackIn() {
        XCTAssertEqual(prompt(clientID: "CID", hasSignedInBefore: true), .logIn)
    }

    func test_aLoggedInSessionIsNeverInterrupted() {
        XCTAssertNil(prompt(clientID: "CID", isLoggedIn: true))
        XCTAssertNil(prompt(clientID: "CID", isLoggedIn: true, hasSignedInBefore: true))
    }

    /// A stored session with no Client ID cannot be refreshed, so setup wins.
    func test_setupWinsOverAStoredSessionWithNoClientID() {
        XCTAssertEqual(prompt(clientID: nil, isLoggedIn: true, hasSignedInBefore: true), .setup)
    }

    func test_onlyTheWalkthroughNeedsMoreThanAButton() {
        XCTAssertFalse(LoginPrompt.setup.isOneClick)
        XCTAssertTrue(LoginPrompt.welcome.isOneClick)
        XCTAssertTrue(LoginPrompt.logIn.isOneClick)
    }
}
