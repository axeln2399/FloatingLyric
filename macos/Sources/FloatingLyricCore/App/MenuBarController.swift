import AppKit

@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let coordinator: AppCoordinator

    private let offsetSlider = NSSlider(value: Double(Defaults.syncOffsetMs),
                                        minValue: -2000, maxValue: 2000,
                                        target: nil, action: nil)
    private let opacitySlider = NSSlider(
        value: Double(Defaults.opacityPercent),
        minValue: Double(PanelOpacity.minimumPercent),
        maxValue: Double(PanelOpacity.maximumPercent),
        target: nil, action: nil)

    private var opacityLabel: NSTextField?
    private var offsetLabelField: NSTextField?
    private var transportItems: [NSMenuItem] = []
    private var playPauseItem: NSMenuItem?
    private var refetchItem: NSMenuItem?

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "music.note.list",
                                           accessibilityDescription: "FloatingLyric")
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        // Transport items are enabled by hand, once there is a session.
        menu.autoenablesItems = false
        menu.delegate = self

        menu.addItem(item("Show / Hide Lyrics", #selector(toggleLyrics), key: "l"))
        menu.addItem(item("Minimize Window", #selector(minimizeLyrics), key: "m"))
        menu.addItem(item("Close Window", #selector(closeLyrics), key: "w"))
        menu.addItem(check("Lock Position", #selector(toggleLock), on: Defaults.lockPosition))
        menu.addItem(check("Click Through", #selector(toggleClickThrough), on: Defaults.clickThrough))
        menu.addItem(.separator())

        let refetch = item("Refetch Lyrics", #selector(refetchLyrics), key: "r")
        refetchItem = refetch
        menu.addItem(refetch)
        menu.addItem(.separator())

        let playPause = item("Play / Pause", #selector(playPause), key: "p")
        let next = item("Next Track", #selector(nextTrack), key: "]")
        let previous = item("Previous Track", #selector(previousTrack), key: "[")
        playPauseItem = playPause
        transportItems = [playPause, next, previous]
        transportItems.forEach(menu.addItem)
        menu.addItem(.separator())

        let fontMenu = NSMenu()
        for (label, size) in [("Small", 14), ("Medium", 18), ("Large", 24)] {
            let entry = item(label, #selector(setFontSize(_:)))
            entry.tag = size
            entry.state = Defaults.fontSize == size ? .on : .off
            fontMenu.addItem(entry)
        }
        let fontItem = NSMenuItem(title: "Font Size", action: nil, keyEquivalent: "")
        fontItem.submenu = fontMenu
        menu.addItem(fontItem)

        menu.addItem(opacitySliderItem())
        menu.addItem(item("More Opaque", #selector(moreOpaque), key: "="))
        menu.addItem(item("More Transparent", #selector(moreTransparent), key: "-"))
        menu.addItem(.separator())

        menu.addItem(offsetSliderItem())
        menu.addItem(check("Romaji Under Lyrics", #selector(toggleRomaji), on: Defaults.showRomaji))
        menu.addItem(check("Auto-Hide Controls", #selector(toggleAutoHide), on: Defaults.autoHideChrome))
        menu.addItem(.separator())
        menu.addItem(item("Use My Own Client ID…", #selector(openSetup)))
        menu.addItem(item("Log Out", #selector(logOut)))
        menu.addItem(.separator())
        menu.addItem(item("Quit FloatingLyric", #selector(quit), key: "q"))
        return menu
    }

    // MARK: - Slider rows

    private func opacitySliderItem() -> NSMenuItem {
        let label = NSTextField(labelWithString: opacityText())
        opacityLabel = label
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged)
        // Continuous, so the window fades as the slider is dragged.
        opacitySlider.isContinuous = true
        return sliderRow(label: label, slider: opacitySlider)
    }

    private func offsetSliderItem() -> NSMenuItem {
        let label = NSTextField(labelWithString: offsetText())
        offsetLabelField = label
        offsetSlider.target = self
        offsetSlider.action = #selector(offsetChanged)
        return sliderRow(label: label, slider: offsetSlider)
    }

    private func sliderRow(label: NSTextField, slider: NSSlider) -> NSMenuItem {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 46))
        label.frame = NSRect(x: 14, y: 26, width: 190, height: 16)
        label.font = .menuFont(ofSize: 12)
        slider.frame = NSRect(x: 14, y: 4, width: 190, height: 20)
        container.addSubview(label)
        container.addSubview(slider)

        let entry = NSMenuItem()
        entry.view = container
        return entry
    }

    private func opacityText() -> String { "Opacity: \(Defaults.opacityPercent)%" }
    private func offsetText() -> String { String(format: "Sync offset: %+d ms", Defaults.syncOffsetMs) }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        return entry
    }

    private func check(_ title: String, _ action: Selector, on: Bool) -> NSMenuItem {
        let entry = item(title, action)
        entry.state = on ? .on : .off
        return entry
    }

    // MARK: - NSMenuDelegate

    /// The window and the panel can both change these behind the menu's back,
    /// so everything stateful is refreshed as the menu opens.
    public func menuWillOpen(_ menu: NSMenu) {
        opacitySlider.doubleValue = Double(Defaults.opacityPercent)
        opacityLabel?.stringValue = opacityText()
        offsetSlider.doubleValue = Double(Defaults.syncOffsetMs)
        offsetLabelField?.stringValue = offsetText()

        let canControl = coordinator.viewModel.canControl
        transportItems.forEach { $0.isEnabled = canControl }
        refetchItem?.isEnabled = coordinator.hasCurrentTrack
        playPauseItem?.title = coordinator.viewModel.isPlaying ? "Pause" : "Play"
    }

    // MARK: - Actions

    @objc private func toggleLyrics() { coordinator.togglePanel() }
    @objc private func minimizeLyrics() { coordinator.minimizePanel() }
    @objc private func closeLyrics() { coordinator.closePanel() }

    @objc private func playPause() { coordinator.playPause() }
    @objc private func refetchLyrics() { coordinator.refetchLyrics() }
    @objc private func nextTrack() { coordinator.nextTrack() }
    @objc private func previousTrack() { coordinator.previousTrack() }

    @objc private func toggleLock(_ sender: NSMenuItem) {
        Defaults.lockPosition.toggle()
        sender.state = Defaults.lockPosition ? .on : .off
        coordinator.applyPanelPreferences()
    }

    @objc private func toggleClickThrough(_ sender: NSMenuItem) {
        Defaults.clickThrough.toggle()
        sender.state = Defaults.clickThrough ? .on : .off
        coordinator.applyPanelPreferences()
    }

    @objc private func toggleRomaji(_ sender: NSMenuItem) {
        Defaults.showRomaji.toggle()
        sender.state = Defaults.showRomaji ? .on : .off
        coordinator.applyPanelPreferences()
    }

    @objc private func toggleAutoHide(_ sender: NSMenuItem) {
        Defaults.autoHideChrome.toggle()
        sender.state = Defaults.autoHideChrome ? .on : .off
        coordinator.applyPanelPreferences()
    }

    @objc private func setFontSize(_ sender: NSMenuItem) {
        Defaults.fontSize = sender.tag
        sender.menu?.items.forEach { $0.state = $0.tag == sender.tag ? .on : .off }
        coordinator.applyPanelPreferences()
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        applyOpacity(Int(sender.doubleValue.rounded()))
    }

    @objc private func moreOpaque() {
        applyOpacity(PanelOpacity.stepped(Defaults.opacityPercent, by: PanelOpacity.stepPercent))
    }

    @objc private func moreTransparent() {
        applyOpacity(PanelOpacity.stepped(Defaults.opacityPercent, by: -PanelOpacity.stepPercent))
    }

    private func applyOpacity(_ percent: Int) {
        Defaults.opacityPercent = percent
        opacitySlider.doubleValue = Double(Defaults.opacityPercent)
        opacityLabel?.stringValue = opacityText()
        coordinator.applyPanelPreferences()
    }

    @objc private func offsetChanged(_ sender: NSSlider) {
        Defaults.syncOffsetMs = Int(sender.doubleValue)
        offsetLabelField?.stringValue = offsetText()
    }

    /// Always the walkthrough: someone who reaches for "Spotify Setup…" wants
    /// the Client ID field, not the one-button login they already have.
    @objc private func openSetup() { coordinator.showSetup(.setup) }
    @objc private func logOut() { coordinator.logOut() }
    @objc private func quit() { NSApp.terminate(nil) }
}
