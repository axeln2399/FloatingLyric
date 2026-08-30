import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var menuBar: MenuBarController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        menuBar = MenuBarController(coordinator: coordinator)
        coordinator.start()
    }

    public func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

public enum FloatingLyricApp {
    @MainActor
    public static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
