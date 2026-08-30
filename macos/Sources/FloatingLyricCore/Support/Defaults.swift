import Foundation

public enum Defaults {
    private static let d = UserDefaults.standard

    public static var clientID: String? {
        get { d.string(forKey: "clientID")?.trimmingCharacters(in: .whitespaces).nilIfEmpty }
        set { d.set(newValue, forKey: "clientID") }
    }

    public static var syncOffsetMs: Int {
        get { d.object(forKey: "syncOffsetMs") as? Int ?? 0 }
        set { d.set(min(2000, max(-2000, newValue)), forKey: "syncOffsetMs") }
    }

    public static var panelFrame: String? {
        get { d.string(forKey: "panelFrame") }
        set { d.set(newValue, forKey: "panelFrame") }
    }

    public static var fontSize: Int {
        get { d.object(forKey: "fontSize") as? Int ?? 18 }
        set { d.set(newValue, forKey: "fontSize") }
    }

    /// Always within 0…100, whatever is on disk.
    public static var opacityPercent: Int {
        get { PanelOpacity.clamped(d.object(forKey: "opacityPercent") as? Int
                                   ?? PanelOpacity.defaultPercent) }
        set { d.set(PanelOpacity.clamped(newValue), forKey: "opacityPercent") }
    }

    /// Romaji (or other Latin readings) printed under non-Latin lyric lines.
    public static var showRomaji: Bool {
        get { d.object(forKey: "showRomaji") as? Bool ?? true }
        set { d.set(newValue, forKey: "showRomaji") }
    }

    /// Hide everything but the lyrics after a few idle seconds.
    public static var autoHideChrome: Bool {
        get { d.object(forKey: "autoHideChrome") as? Bool ?? true }
        set { d.set(newValue, forKey: "autoHideChrome") }
    }

    public static var clickThrough: Bool {
        get { d.bool(forKey: "clickThrough") }
        set { d.set(newValue, forKey: "clickThrough") }
    }

    public static var lockPosition: Bool {
        get { d.bool(forKey: "lockPosition") }
        set { d.set(newValue, forKey: "lockPosition") }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
