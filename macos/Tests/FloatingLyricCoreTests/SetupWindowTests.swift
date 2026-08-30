import XCTest
import AppKit
@testable import FloatingLyricCore

@MainActor
final class SetupWindowTests: XCTestCase {
    func test_theWalkthroughIsTitledAsSetup() {
        let window = SetupWindow(prompt: .setup) { _ in }
        XCTAssertEqual(window.prompt, .setup)
        XCTAssertEqual(window.window?.title, "Set up FloatingLyric")
    }

    func test_aFirstRunIsTitledAsLoginNotSetup() {
        let window = SetupWindow(prompt: .welcome) { _ in }
        XCTAssertEqual(window.window?.title, "Log in to Spotify",
                       "a new user should never meet the developer walkthrough")
    }

    func test_loggingBackInIsTitledAsLogin() {
        let window = SetupWindow(prompt: .logIn) { _ in }
        XCTAssertEqual(window.prompt, .logIn)
        XCTAssertEqual(window.window?.title, "Log in to Spotify")
    }

    func test_itDefaultsToTheOneClickWelcome() {
        XCTAssertEqual(SetupWindow { _ in }.prompt, .welcome)
    }

    func test_closingReturnsTheAppToTheMenuBar() {
        let window = SetupWindow(prompt: .logIn) { _ in }
        window.close()
        XCTAssertEqual(NSApp.activationPolicy(), .accessory,
                       "a Dock icon must not outlive the login window")
    }
}
