import Foundation

public enum Defaults {
    private static let d = UserDefaults.standard

    /// A Client ID the user entered by hand, replacing the built-in one.
    /// Almost nobody sets this — it exists for people who would rather run
    /// against their own Spotify app.
    public static var clientIDOverride: String? {
        get { d.string(forKey: "clientID")?.trimmingCharacters(in: .whitespaces).nilIfEmpty }
        set { d.set(newValue?.trimmingCharacters(in: .whitespaces).nilIfEmpty, forKey: "clientID") }
    }

    /// The Client ID to actually authenticate with.
    public static var clientID: String? {
        clientIDOverride ?? AppCredentials.builtInClientID.nilIfEmpty
    }

    /// Whether a Spotify session has ever been established on this Mac, which
    /// is the difference between "welcome" and "you're logged out".
    public static var hasSignedInBefore: Bool {
        get { d.bool(forKey: "hasSignedInBefore") }
        set { d.set(newValue, forKey: "hasSignedInBefore") }
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
