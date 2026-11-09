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

/// Small taps from the Taptic Engine on the iPhone. Does nothing on the Mac.
@MainActor
enum Haptic {
    static func tap() { impact(.light) }
    static func soft() { impact(.soft) }
    static func firm() { impact(.medium) }
    static func select() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
    static func success() { notify(.success) }
    static func warning() { notify(.warning) }
    static func error() { notify(.error) }

    #if os(iOS)
    private static func impact(_ s: UIImpactFeedbackGenerator.FeedbackStyle) { UIImpactFeedbackGenerator(style: s).impactOccurred() }
    private static func notify(_ t: UINotificationFeedbackGenerator.FeedbackType) { UINotificationFeedbackGenerator().notificationOccurred(t) }
    #else
    private enum Style { case light, soft, medium }
    private enum Kind { case success, warning, error }
    private static func impact(_ s: Style) {}
    private static func notify(_ t: Kind) {}
    #endif
}
