import AppKit

@MainActor
public final class MenuBarController {
    private let statusItem: NSStatusItem
    private let coordinator: AppCoordinator
    private var opacityMenuRef: NSMenu?
    private let offsetSlider = NSSlider(value: Double(Defaults.syncOffsetMs),
                                        minValue: -2000, maxValue: 2000,
                                        target: nil, action: nil)

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "music.note.list",
                                           accessibilityDescription: "FloatingLyric")
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(item("Show / Hide Lyrics", #selector(toggleLyrics), key: "l"))
        menu.addItem(item("Minimize Window", #selector(minimizeLyrics), key: "m"))
        menu.addItem(item("Close Window", #selector(closeLyrics), key: "w"))
        menu.addItem(check("Lock Position", #selector(toggleLock), on: Defaults.lockPosition))
        menu.addItem(check("Click Through", #selector(toggleClickThrough), on: Defaults.clickThrough))
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

        let opacityMenu = NSMenu()
        for percent in PanelOpacity.steps {
            let entry = item("\(percent)%", #selector(setOpacity(_:)))
            entry.tag = percent
            entry.state = Defaults.opacityPercent == percent ? .on : .off
            opacityMenu.addItem(entry)
        }
        opacityMenu.addItem(.separator())
        opacityMenu.addItem(item("Cycle", #selector(cycleOpacity), key: "t"))
        let opacityItem = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
        opacityItem.submenu = opacityMenu
        opacityMenuRef = opacityMenu
        menu.addItem(opacityItem)

        menu.addItem(sliderItem())
        menu.addItem(.separator())
        menu.addItem(item("Spotify Setup…", #selector(openSetup)))
        menu.addItem(item("Log Out", #selector(logOut)))
        menu.addItem(.separator())
        menu.addItem(item("Quit FloatingLyric", #selector(quit), key: "q"))
        return menu
    }

    private func sliderItem() -> NSMenuItem {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 46))
        let label = NSTextField(labelWithString: offsetLabel())
        label.frame = NSRect(x: 14, y: 26, width: 190, height: 16)
        label.font = .menuFont(ofSize: 12)
        label.tag = 99

        offsetSlider.frame = NSRect(x: 14, y: 4, width: 190, height: 20)
        offsetSlider.target = self
        offsetSlider.action = #selector(offsetChanged)

        container.addSubview(label)
        container.addSubview(offsetSlider)

        let entry = NSMenuItem()
        entry.view = container
        return entry
    }

    private func offsetLabel() -> String {
        String(format: "Sync offset: %+d ms", Defaults.syncOffsetMs)
    }

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

    // MARK: - Actions

    @objc private func toggleLyrics() { coordinator.togglePanel() }
    @objc private func minimizeLyrics() { coordinator.minimizePanel() }
    @objc private func closeLyrics() { coordinator.closePanel() }

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

    @objc private func setFontSize(_ sender: NSMenuItem) {
        Defaults.fontSize = sender.tag
        sender.menu?.items.forEach { $0.state = $0.tag == sender.tag ? .on : .off }
        coordinator.applyPanelPreferences()
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        applyOpacity(sender.tag)
    }

    @objc private func cycleOpacity() {
        applyOpacity(PanelOpacity.next(after: Defaults.opacityPercent))
    }

    private func applyOpacity(_ percent: Int) {
        Defaults.opacityPercent = percent
        let selected = Defaults.opacityPercent
        opacityMenuRef?.items.forEach { $0.state = $0.tag == selected ? .on : .off }
        coordinator.applyPanelPreferences()
    }

    @objc private func offsetChanged(_ sender: NSSlider) {
        Defaults.syncOffsetMs = Int(sender.doubleValue)
        if let label = sender.superview?.viewWithTag(99) as? NSTextField {
            label.stringValue = offsetLabel()
        }
    }

    @objc private func openSetup() { coordinator.showSetup() }
    @objc private func logOut() { coordinator.logOut() }
    @objc private func quit() { NSApp.terminate(nil) }
}
