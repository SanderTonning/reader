import Foundation
#if canImport(UIKit)
import UIKit
#endif

public enum DeviceInfo {
    public static var name: String {
        #if os(macOS)
        Host.current().localizedName ?? "Mac"
        #else
        ProcessInfo.processInfo.hostName
        #endif
    }
}
