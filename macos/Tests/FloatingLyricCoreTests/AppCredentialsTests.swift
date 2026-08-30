import XCTest
@testable import FloatingLyricCore

final class AppCredentialsTests: XCTestCase {
    func test_theAppShipsWithAClientID() {
        XCTAssertTrue(AppCredentials.hasBuiltInClientID,
                      "without this, every user is sent to the Spotify dashboard")
        XCTAssertEqual(AppCredentials.builtInClientID.count, 32,
                       "Spotify client IDs are 32 hex characters")
    }

    func test_theBuiltInIDIsUsedWhenNobodyHasOverriddenIt() {
        let saved = Defaults.clientIDOverride
        defer { Defaults.clientIDOverride = saved }

        Defaults.clientIDOverride = nil
        XCTAssertEqual(Defaults.clientID, AppCredentials.builtInClientID)
    }

    func test_anOverrideWins() {
        let saved = Defaults.clientIDOverride
        defer { Defaults.clientIDOverride = saved }

        Defaults.clientIDOverride = "MINE"
        XCTAssertEqual(Defaults.clientID, "MINE")
    }

    func test_aBlankOverrideFallsBackRatherThanBreakingLogin() {
        let saved = Defaults.clientIDOverride
        defer { Defaults.clientIDOverride = saved }

        Defaults.clientIDOverride = "   "
        XCTAssertEqual(Defaults.clientID, AppCredentials.builtInClientID)
    }
}
