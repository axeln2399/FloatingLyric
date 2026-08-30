import XCTest
@testable import FloatingLyricCore

final class ChromeVisibilityTests: XCTestCase {
    func test_timeoutIsThreeSeconds() {
        XCTAssertEqual(ChromeVisibility.idleTimeout, 3.0, accuracy: 0.0001)
    }

    func test_visibleImmediatelyAfterActivity() {
        XCTAssertTrue(ChromeVisibility.isVisible(now: 100, lastActivity: 100, isHovering: false))
    }

    func test_staysVisibleJustBeforeTheTimeout() {
        XCTAssertTrue(ChromeVisibility.isVisible(now: 102.9, lastActivity: 100, isHovering: false))
    }

    func test_hidesOnceTheTimeoutIsReached() {
        XCTAssertFalse(ChromeVisibility.isVisible(now: 103.0, lastActivity: 100, isHovering: false))
        XCTAssertFalse(ChromeVisibility.isVisible(now: 999.0, lastActivity: 100, isHovering: false))
    }

    func test_hoveringKeepsItVisibleIndefinitely() {
        XCTAssertTrue(ChromeVisibility.isVisible(now: 999.0, lastActivity: 100, isHovering: true))
    }

    func test_clockGoingBackwardsDoesNotHideIt() {
        XCTAssertTrue(ChromeVisibility.isVisible(now: 90, lastActivity: 100, isHovering: false))
    }
}
