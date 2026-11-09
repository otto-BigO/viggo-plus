import Foundation
#if os(macOS)
import AppKit
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformColor = UIColor
#endif

/// The few things that differ between the Mac and the iPhone app.
@MainActor
enum Platform {
    static func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }
}

extension Platform {
    /// "din Mac" or "din iPhone", for texts like "Koden gemmes kun på din Mac".
    static var deviceName: String {
        #if os(macOS)
        "din Mac"
        #else
        "din iPhone"
        #endif
    }
}
