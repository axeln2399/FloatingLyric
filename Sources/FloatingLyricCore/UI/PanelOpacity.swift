import Foundation

/// The three transparency steps offered for the floating window.
public enum PanelOpacity {
    public static let steps = [15, 45, 60]
    public static let defaultPercent = 60

    public static func alpha(forPercent percent: Int) -> Double {
        Double(percent) / 100
    }

    /// Snaps an arbitrary percentage onto the nearest step, clamping outliers.
    /// A stored value can be anything (hand-edited defaults, an older build), so
    /// nothing downstream ever sees a percentage outside `steps`.
    public static func nearest(_ percent: Int) -> Int {
        steps.min { abs($0 - percent) < abs($1 - percent) } ?? defaultPercent
    }

    /// The next step up, wrapping back to the most transparent one.
    public static func next(after percent: Int) -> Int {
        let current = nearest(percent)
        let index = steps.firstIndex(of: current) ?? steps.count - 1
        return steps[(index + 1) % steps.count]
    }
}
