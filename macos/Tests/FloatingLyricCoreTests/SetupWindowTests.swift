import XCTest
import AppKit
@testable import FloatingLyricCore

@MainActor
final class SetupWindowTests: XCTestCase {
    func test_aFirstRunIsTitledAsSetup() {
        let window = SetupWindow(prompt: .firstRun) { _ in }
        XCTAssertEqual(window.prompt, .firstRun)
        XCTAssertEqual(window.window?.title, "Set up FloatingLyric")
    }

    func test_loggingBackInIsTitledAsLogin() {
        let window = SetupWindow(prompt: .logIn) { _ in }
        XCTAssertEqual(window.prompt, .logIn)
        XCTAssertEqual(window.window?.title, "Log in to Spotify")
    }

    func test_itDefaultsToTheWalkthrough() {
        XCTAssertEqual(SetupWindow { _ in }.prompt, .firstRun)
    }

    func test_closingReturnsTheAppToTheMenuBar() {
        let window = SetupWindow(prompt: .logIn) { _ in }
        window.close()
        XCTAssertEqual(NSApp.activationPolicy(), .accessory,
                       "a Dock icon must not outlive the login window")
    }
}
