import Foundation

public enum PanelAction: Equatable {
    case show
    case hide
    case restore
}

/// Decides what the "Show / Hide Lyrics" command should do.
public enum PanelToggle {
    /// AppKit reports a miniaturized window as visible, so miniaturization has
    /// to be checked before visibility or the window gets ordered out while
    /// still in the Dock — unreachable from either place.
    public static func action(isMiniaturized: Bool, isVisible: Bool) -> PanelAction {
        if isMiniaturized { return .restore }
        return isVisible ? .hide : .show
    }
}
