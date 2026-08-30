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

    func test_idleChromeTakesTheTrafficLightsWithIt() {
        Defaults.clickThrough = false
        let window = makeWindow()
        XCTAssertEqual(window.standardWindowButton(.closeButton)?.isHidden, false)

        window.setChrome(visible: false, isHovering: false)
        XCTAssertEqual(window.standardWindowButton(.closeButton)?.isHidden, true)
        XCTAssertEqual(window.standardWindowButton(.miniaturizeButton)?.isHidden, true)

        window.setChrome(visible: true, isHovering: true)
        XCTAssertEqual(window.standardWindowButton(.closeButton)?.isHidden, false)
    }

    func test_hoveringAnInvisibleWindowMakesItFindableAgain() {
        Defaults.opacityPercent = 0
        let window = makeWindow()
        XCTAssertEqual(window.alphaValue, 0, accuracy: 0.001)

        window.setChrome(visible: true, isHovering: true)
        XCTAssertEqual(window.alphaValue,
                       Double(PanelOpacity.hoverFloorPercent) / 100, accuracy: 0.001)

        window.setChrome(visible: false, isHovering: false)
        XCTAssertEqual(window.alphaValue, 0, accuracy: 0.001)
    }

    func test_aHiddenWindowIsNeverHovered() {
        let window = makeWindow()
        window.orderOut(nil)
        XCTAssertFalse(window.isPointerInside)
    }

    func test_theWindowCanBeResized() {
        let window = makeWindow()
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.minSize, FloatingWindow.minimumSize)
        XCTAssertEqual(window.standardWindowButton(.zoomButton)?.isHidden, true,
                       "resizing is by edge drag; zoom stays off for an overlay")
    }

    func test_resizingIsRemembered() {
        Defaults.panelFrame = nil
        let window = makeWindow()
        let resized = NSRect(x: 120, y: 140, width: 640, height: 400)
        window.setFrame(resized, display: false)
        window.windowDidResize(Notification(name: NSWindow.didResizeNotification))

        XCTAssertEqual(Defaults.panelFrame.map(NSRectFromString), resized)
    }

    func test_aSavedFrameSmallerThanTheMinimumIsIgnored() {
        Defaults.panelFrame = NSStringFromRect(NSRect(x: 0, y: 0, width: 40, height: 20))
        let window = makeWindow()
        XCTAssertGreaterThanOrEqual(window.frame.width, FloatingWindow.minimumSize.width)
        XCTAssertGreaterThanOrEqual(window.frame.height, FloatingWindow.minimumSize.height)
    }

    override func tearDown() {
        Defaults.panelFrame = nil
        Defaults.clickThrough = false
        Defaults.opacityPercent = PanelOpacity.defaultPercent
        super.tearDown()
    }
}
