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
    public static let minimumSize = NSSize(width: 280, height: 150)

    public init(viewModel: LyricViewModel) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 420, height: 210),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable,
                               .fullSizeContentView],
                   backing: .buffered,
                   defer: false)

        // Native traffic lights, but no title bar chrome: the content runs full
        // height and the buttons float over the blur.
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        title = "FloatingLyric"
        // Resizing is by dragging an edge or corner. The green button is still
        // hidden: on a window pinned above everything else, zoom and full
        // screen are not behaviours anyone wants from a lyric overlay.
        standardWindowButton(.zoomButton)?.isHidden = true

        // Small enough to be a one-line strip, with no upper bound — a wide
        // window is how you stop long lines from wrapping.
        minSize = Self.minimumSize

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

    /// Whether the window furniture is currently on screen, and whether the
    /// pointer is on the window — both decided by `LyricViewModel` and pushed
    /// in here by the coordinator.
    private var chromeVisible = true
    private var isHovering = false

    /// Whether the pointer is over the window right now.
    ///
    /// Polled rather than tracked: FloatingLyric has no Dock icon and usually
    /// is not the active app, and mouse-entered/exited events are not
    /// delivered reliably to a background app's window. A hit test against the
    /// current mouse location always is.
    public var isPointerInside: Bool {
        guard isVisible, !isMiniaturized else { return false }
        return frame.contains(NSEvent.mouseLocation)
    }

    public func setChrome(visible: Bool, isHovering hovering: Bool) {
        guard chromeVisible != visible || isHovering != hovering else { return }
        chromeVisible = visible
        isHovering = hovering
        applyPreferences()
    }

    public func applyPreferences() {
        ignoresMouseEvents = Defaults.clickThrough
        isMovableByWindowBackground = !Defaults.lockPosition && !Defaults.clickThrough

        // Set straight, not through `animator()`: the value has to be readable
        // the moment it is applied, and the chrome does its own fading inside
        // the SwiftUI view.
        alphaValue = PanelOpacity.alpha(forPercent: Defaults.opacityPercent,
                                        isHovering: isHovering)

        // Click-through would swallow clicks on the traffic lights too, so hide
        // them rather than leave dead buttons on screen. They are furniture as
        // much as the header is, so they also go with the rest of the chrome.
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton] {
            standardWindowButton(button)?.isHidden = Defaults.clickThrough || !chromeVisible
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
        if visible, frame.width >= Self.minimumSize.width,
           frame.height >= Self.minimumSize.height {
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

    public func windowDidMove(_ notification: Notification) {
        saveFrame()
    }

    public func windowDidResize(_ notification: Notification) {
        saveFrame()
    }

    public func windowWillMiniaturize(_ notification: Notification) {
        // A window at `.floating` level does not reliably animate into the Dock.
        // Drop to the normal level for the duration of the miniaturization.
        level = .normal
    }

    public func windowDidDeminiaturize(_ notification: Notification) {
        level = .floating
    }
}
