import Foundation
#if canImport(UIKit)
import UIKit
#endif

public enum DeviceInfo {
    private static let idKey = "device.id"
    private static let nameKey = "device.name"

    /// Stabil ID for denne installasjonen, brukt som filnavn i synkmappen.
    public static var id: String {
        if let existing = UserDefaults.standard.string(forKey: idKey) { return existing }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: idKey)
        return new
    }

    /// Navnet som vises når en posisjon kommer fra en annen enhet.
    public static var name: String {
        get {
            if let saved = UserDefaults.standard.string(forKey: nameKey), !saved.isEmpty { return saved }
            #if os(macOS)
            return Host.current().localizedName ?? "Mac"
            #else
            return "iPhone"
            #endif
        }
        set { UserDefaults.standard.set(newValue, forKey: nameKey) }
    }

    /// Setter et fornuftig standardnavn første gang appen starter.
    @MainActor
    public static func prepare() {
        guard UserDefaults.standard.string(forKey: nameKey) == nil else { return }
        #if os(iOS)
        name = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #else
        name = Host.current().localizedName ?? "Mac"
        #endif
    }
}
