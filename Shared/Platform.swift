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

/// Small taps from the Taptic Engine on the iPhone. On the Mac only a tick and a success are felt,
/// through a Force Touch trackpad, and only while you are clicking. Off under Udseende og haptik.
@MainActor
enum Haptic {
    static var on: Bool { Prefs.shared.haptics }
    static func tap() { impact(.light) }
    static func soft() { impact(.soft) }
    static func firm() { impact(.medium) }
    static func select() {
        #if os(iOS)
        if on { UISelectionFeedbackGenerator().selectionChanged() }
        #endif
    }
    static func success() { notify(.success) }
    static func warning() { notify(.warning) }
    static func error() { notify(.error) }

    #if os(iOS)
    private static func impact(_ s: UIImpactFeedbackGenerator.FeedbackStyle) { if on { UIImpactFeedbackGenerator(style: s).impactOccurred() } }
    private static func notify(_ t: UINotificationFeedbackGenerator.FeedbackType) { if on { UINotificationFeedbackGenerator().notificationOccurred(t) } }
    #else
    private enum Style { case light, soft, medium }
    private enum Kind { case success, warning, error }
    private static func impact(_ s: Style) {
        guard on, s == .light else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
    private static func notify(_ t: Kind) {
        guard on, t == .success else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
    #endif
}
