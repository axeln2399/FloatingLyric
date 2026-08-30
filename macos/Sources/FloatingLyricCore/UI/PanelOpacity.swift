import Foundation

/// The floating window's transparency, as a free 0–100% setting.
public enum PanelOpacity {
    public static let minimumPercent = 0
    public static let maximumPercent = 100
    public static let defaultPercent = 60

    /// How far the slider moves per keyboard nudge.
    public static let stepPercent = 5

    /// 0% is a genuinely invisible window, which would also be an unfindable
    /// one. Pointing at it lifts it back to at least this much, so the setting
    /// can always be undone — see `alpha(forPercent:isHovering:)`.
    public static let hoverFloorPercent = 35

    public static func clamped(_ percent: Int) -> Int {
        min(maximumPercent, max(minimumPercent, percent))
    }

    public static func alpha(forPercent percent: Int) -> Double {
        Double(clamped(percent)) / 100
    }

    /// The alpha actually applied to the window. Hovering never makes a window
    /// more transparent than it already is — it only raises a near-invisible
    /// one back to something you can see and grab.
    public static func alpha(forPercent percent: Int, isHovering: Bool) -> Double {
        let effective = isHovering ? max(clamped(percent), hoverFloorPercent)
                                   : clamped(percent)
        return Double(effective) / 100
    }

    /// One keyboard nudge, clamped at both ends (no wrap-around: wrapping from
    /// 100% straight to invisible is never what the shortcut was for).
    public static func stepped(_ percent: Int, by delta: Int) -> Int {
        clamped(clamped(percent) + delta)
    }
}
