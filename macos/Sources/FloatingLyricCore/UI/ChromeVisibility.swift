import Foundation

/// Decides whether the window's furniture — track header, progress bar,
/// transport buttons, traffic lights — is on screen. After a few idle seconds
/// everything but the lyrics fades away; pointing at the window brings it back.
public enum ChromeVisibility {
    public static let idleTimeout: TimeInterval = 3.0

    public static func isVisible(now: TimeInterval,
                                 lastActivity: TimeInterval,
                                 isHovering: Bool) -> Bool {
        if isHovering { return true }
        let elapsed = now - lastActivity
        // A backwards clock (sleep, time sync) must not blank the window.
        guard elapsed >= 0 else { return true }
        return elapsed < idleTimeout
    }
}
