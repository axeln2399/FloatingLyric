import AppKit

public enum FloatingLyricApp {
    public static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
