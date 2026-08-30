import AppKit
import SwiftUI

@MainActor
public final class FloatingPanel: NSPanel {
    public init(viewModel: LyricViewModel) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.masksToBounds = true

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
        Defaults.panelFrame = NSStringFromRect(frame)
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}
