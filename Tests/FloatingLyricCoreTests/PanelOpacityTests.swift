import XCTest
@testable import FloatingLyricCore

final class PanelOpacityTests: XCTestCase {
    func test_offersExactlyTheThreeSteps() {
        XCTAssertEqual(PanelOpacity.steps, [15, 45, 60])
    }

    func test_defaultIsTheMostReadableStep() {
        XCTAssertEqual(PanelOpacity.defaultPercent, 60)
    }

    func test_alphaConvertsPercentToUnitInterval() {
        XCTAssertEqual(PanelOpacity.alpha(forPercent: 15), 0.15, accuracy: 0.0001)
        XCTAssertEqual(PanelOpacity.alpha(forPercent: 45), 0.45, accuracy: 0.0001)
        XCTAssertEqual(PanelOpacity.alpha(forPercent: 60), 0.60, accuracy: 0.0001)
    }

    func test_nearestSnapsAnArbitraryValueToAStep() {
        XCTAssertEqual(PanelOpacity.nearest(15), 15)
        XCTAssertEqual(PanelOpacity.nearest(45), 45)
        XCTAssertEqual(PanelOpacity.nearest(60), 60)
        XCTAssertEqual(PanelOpacity.nearest(20), 15)
        XCTAssertEqual(PanelOpacity.nearest(40), 45)
        XCTAssertEqual(PanelOpacity.nearest(55), 60)
    }

    func test_nearestClampsValuesOutsideTheRange() {
        XCTAssertEqual(PanelOpacity.nearest(0), 15)
        XCTAssertEqual(PanelOpacity.nearest(-100), 15)
        XCTAssertEqual(PanelOpacity.nearest(100), 60)
        XCTAssertEqual(PanelOpacity.nearest(999), 60)
    }

    func test_neverReturnsAFullyInvisibleWindow() {
        for percent in [-50, 0, 5, 15, 45, 60, 200] {
            XCTAssertGreaterThanOrEqual(PanelOpacity.alpha(forPercent: PanelOpacity.nearest(percent)),
                                        0.15)
        }
    }

    func test_cyclingAdvancesThroughTheStepsAndWrapsAround() {
        XCTAssertEqual(PanelOpacity.next(after: 15), 45)
        XCTAssertEqual(PanelOpacity.next(after: 45), 60)
        XCTAssertEqual(PanelOpacity.next(after: 60), 15)
        XCTAssertEqual(PanelOpacity.next(after: 33), 60, "an off-step value snaps first")
    }
}
