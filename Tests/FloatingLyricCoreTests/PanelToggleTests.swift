import XCTest
@testable import FloatingLyricCore

final class PanelToggleTests: XCTestCase {
    func test_visibleWindowGetsHidden() {
        XCTAssertEqual(PanelToggle.action(isMiniaturized: false, isVisible: true), .hide)
    }

    func test_hiddenWindowGetsShown() {
        XCTAssertEqual(PanelToggle.action(isMiniaturized: false, isVisible: false), .show)
    }

    // AppKit reports a miniaturized window as visible, so a naive
    // `isVisible ? hide : show` would order it out instead of restoring it —
    // leaving the window stuck in the Dock with no way back.
    func test_miniaturizedWindowIsRestoredRatherThanHidden() {
        XCTAssertEqual(PanelToggle.action(isMiniaturized: true, isVisible: true), .restore)
    }

    func test_miniaturizedWindowIsRestoredEvenIfReportedHidden() {
        XCTAssertEqual(PanelToggle.action(isMiniaturized: true, isVisible: false), .restore)
    }
}
