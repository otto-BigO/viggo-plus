import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// The look, borrowed from the fomo app: one dark background and one surface, no borders or
// shadows, and colours that mean something. Accent is something you can do, green is done or
// good, red is cancelled or a problem, orange is "look at this" (deadlines, homework).
// Everything else is white or grey.
//
// This file is also compiled into the widget target, so the widgets and the Live Activity use
// the same colours. Keep it free of anything else from the app.

enum Fomo {
    static let bg = dynamic(light: 0xF4F4F7, dark: 0x060510)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x12111A)
    /// Tracks, placeholders and chips inside a surface.
    static let surface2 = dynamic(light: 0xE9E9EF, dark: 0x1D1C29)
    static let accent = Color(hex: 0x4F6AF8)
    /// Darker in light mode, so green text on a white card is readable (about 5:1 instead of 2:1).
    static let green = dynamic(light: 0x15803D, dark: 0x21C95E)
    static let red = Color(hex: 0xEF371F)
    /// Deadlines, homework and other things to look at. Darker in light mode for the same reason as green.
    static let warn = dynamic(light: 0xC2410C, dark: 0xFF9F0A)
    /// Text on a green fill: white on the dark light-mode green, black on the bright dark-mode one.
    static let onGreen = dynamic(light: 0xFFFFFF, dark: 0x06240F)
    static let text2 = dynamic(light: 0x6B6B76, dark: 0x9899A3)
    static let radius: CGFloat = 14
    /// Small things inside a card: chips, fields, thumbnails.
    static let radiusSmall: CGFloat = 10
    /// The pill and other things that move into place.
    static let spring = Animation.spring(response: 0.4, dampingFraction: 0.8)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil ? NSColor(hex: dark) : NSColor(hex: light)
        })
        #else
        Color(uiColor: UIColor { t in t.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
        #endif
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

#if os(macOS)
extension NSColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}
#else
extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}
#endif

extension View {
    /// A flat card on the surface colour: no border, no shadow.
    func surface(_ radius: CGFloat = Fomo.radius, fill: Color = Fomo.surface) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
    }

    /// A list or form on the app background instead of the system grey. On the Mac the
    /// settings forms keep the native look, so this does nothing there.
    @ViewBuilder func fomoList() -> some View {
        #if os(iOS)
        scrollContentBackground(.hidden).background(Fomo.bg)
        #else
        self
        #endif
    }

    /// The rows of a list section on the surface colour, to go with `fomoList()`.
    @ViewBuilder func fomoRows() -> some View {
        #if os(iOS)
        listRowBackground(Fomo.surface)
        #else
        self
        #endif
    }
}
