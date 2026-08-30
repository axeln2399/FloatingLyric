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
