import XCTest
@testable import FloatingLyricCore

final class PanelOpacityTests: XCTestCase {
    func test_theRangeIsTheWholeZeroToOneHundredPercent() {
        XCTAssertEqual(PanelOpacity.minimumPercent, 0)
        XCTAssertEqual(PanelOpacity.maximumPercent, 100)
    }

    func test_defaultIsAReadableSixtyPercent() {
        XCTAssertEqual(PanelOpacity.defaultPercent, 60)
    }

    func test_alphaConvertsPercentToUnitInterval() {
        XCTAssertEqual(PanelOpacity.alpha(forPercent: 0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(PanelOpacity.alpha(forPercent: 37), 0.37, accuracy: 0.0001)
        XCTAssertEqual(PanelOpacity.alpha(forPercent: 100), 1.0, accuracy: 0.0001)
    }

    func test_valuesOutsideTheRangeAreClamped() {
        XCTAssertEqual(PanelOpacity.clamped(-40), 0)
        XCTAssertEqual(PanelOpacity.clamped(0), 0)
        XCTAssertEqual(PanelOpacity.clamped(73), 73)
        XCTAssertEqual(PanelOpacity.clamped(101), 100)
        XCTAssertEqual(PanelOpacity.clamped(999), 100)
    }

    func test_hoveringLiftsAnInvisibleWindowBackIntoView() {
        XCTAssertEqual(PanelOpacity.alpha(forPercent: 0, isHovering: false), 0.0, accuracy: 0.0001)
        XCTAssertEqual(PanelOpacity.alpha(forPercent: 0, isHovering: true),
                       Double(PanelOpacity.hoverFloorPercent) / 100, accuracy: 0.0001)
    }

    func test_hoveringNeverMakesAWindowMoreTransparent() {
        for percent in [40, 60, 80, 100] {
            XCTAssertEqual(PanelOpacity.alpha(forPercent: percent, isHovering: true),
                           PanelOpacity.alpha(forPercent: percent),
                           accuracy: 0.0001)
        }
    }

    func test_steppingMovesByTheNudgeAndStopsAtBothEnds() {
        XCTAssertEqual(PanelOpacity.stepped(60, by: 5), 65)
        XCTAssertEqual(PanelOpacity.stepped(60, by: -5), 55)
        XCTAssertEqual(PanelOpacity.stepped(98, by: 5), 100, "no wrap past the top")
        XCTAssertEqual(PanelOpacity.stepped(2, by: -5), 0, "no wrap past the bottom")
    }
}
