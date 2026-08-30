import AppKit
import SwiftUI

/// The lyric window.
///
/// A real `NSWindow` rather than an `NSPanel`: AppKit documents panels as not
/// supporting miniaturization, so a panel's minimize button does nothing. That
/// difference only shows up against a live window server — it cannot be covered
/// by a unit test, so keep the superclass as `NSWindow` unless you have
/// re-checked minimize by hand in the running app.
@MainActor
public final class FloatingWindow: NSWindow, NSWindowDelegate {
    public init(viewModel: LyricViewModel) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 420, height: 210),
                   styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                   backing: .buffered,
                   defer: false)

        // Native traffic lights, but no title bar chrome: the content runs full
        // height and the buttons float over the blur.
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        title = "FloatingLyric"
        standardWindowButton(.zoomButton)?.isHidden = true

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        // Closing must not deallocate the window; the menu bar can reopen it.
        isReleasedWhenClosed = false
        delegate = self

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active

        let hosting = NSHostingView(rootView: LyricView(model: viewModel))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: blur.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])

        contentView = blur
        restoreFrame()
        applyPreferences()
    }

    public func applyPreferences() {
        ignoresMouseEvents = Defaults.clickThrough
        isMovableByWindowBackground = !Defaults.lockPosition && !Defaults.clickThrough
        alphaValue = PanelOpacity.alpha(forPercent: Defaults.opacityPercent)
        // Click-through would swallow clicks on the traffic lights too, so hide
        // them rather than leave dead buttons on screen.
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton] {
            standardWindowButton(button)?.isHidden = Defaults.clickThrough
        }
    }

    public func restoreFrame() {
        guard let saved = Defaults.panelFrame else {
            center()
            return
        }
        let frame = NSRectFromString(saved)
        // A saved frame can point at a display that is no longer attached.
        let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        if visible, frame.width > 100, frame.height > 60 {
            setFrame(frame, display: false)
        } else {
            center()
        }
    }

    public func saveFrame() {
        guard !isMiniaturized else { return }
        Defaults.panelFrame = NSStringFromRect(frame)
    }

    // MARK: - NSWindowDelegate

    public func windowWillMiniaturize(_ notification: Notification) {
        // A window at `.floating` level does not reliably animate into the Dock.
        // Drop to the normal level for the duration of the miniaturization.
        level = .normal
    }

    public func windowDidDeminiaturize(_ notification: Notification) {
        level = .floating
    }
}
