import XCTest
import AppKit
@testable import FloatingLyricCore

@MainActor
final class FloatingWindowTests: XCTestCase {
    private func makeWindow() -> FloatingWindow {
        FloatingWindow(viewModel: LyricViewModel())
    }

    func test_hasNativeCloseAndMinimizeInItsStyleMask() {
        let window = makeWindow()
        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertTrue(window.styleMask.contains(.miniaturizable))
    }

    func test_nativeTrafficLightButtonsExist() {
        let window = makeWindow()
        XCTAssertNotNil(window.standardWindowButton(.closeButton))
        XCTAssertNotNil(window.standardWindowButton(.miniaturizeButton))
    }

    /// A smoke check that the buttons are live rather than decorative. Note it
    /// does NOT distinguish NSWindow from NSPanel — offscreen, a panel reports
    /// these as enabled too. Whether minimize genuinely works can only be
    /// confirmed by running the app; see the note in FloatingWindow.
    func test_trafficLightButtonsAreEnabled() {
        let window = makeWindow()
        XCTAssertEqual(window.standardWindowButton(.miniaturizeButton)?.isEnabled, true)
        XCTAssertEqual(window.standardWindowButton(.closeButton)?.isEnabled, true)
    }

    func test_closingDoesNotDeallocateTheWindow() {
        let window = makeWindow()
        // Without this, reopening from the menu bar after a close would crash.
        XCTAssertFalse(window.isReleasedWhenClosed)
    }

    func test_staysFloatingAboveOtherAppsOnEverySpace() {
        let window = makeWindow()
        XCTAssertEqual(window.level, .floating)
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    func test_titleBarIsHiddenSoOnlyTheButtonsShow() {
        let window = makeWindow()
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(window.standardWindowButton(.zoomButton)?.isHidden, true)
    }

    func test_opacityPreferenceIsAppliedToTheWindow() {
        Defaults.opacityPercent = 15
        let window = makeWindow()
        XCTAssertEqual(window.alphaValue, 0.15, accuracy: 0.001)

        Defaults.opacityPercent = 60
        window.applyPreferences()
        XCTAssertEqual(window.alphaValue, 0.60, accuracy: 0.001)
    }

    func test_clickThroughHidesTheButtonsSoTheyAreNotDeadTargets() {
        Defaults.clickThrough = true
        let window = makeWindow()
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertEqual(window.standardWindowButton(.closeButton)?.isHidden, true)
        XCTAssertEqual(window.standardWindowButton(.miniaturizeButton)?.isHidden, true)

        Defaults.clickThrough = false
        window.applyPreferences()
        XCTAssertFalse(window.ignoresMouseEvents)
        XCTAssertEqual(window.standardWindowButton(.closeButton)?.isHidden, false)
    }

    override func tearDown() {
        Defaults.clickThrough = false
        Defaults.opacityPercent = PanelOpacity.defaultPercent
        super.tearDown()
    }
}
