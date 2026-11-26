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

/// The three looks you can pick under Udseende og haptik (Mac). The widgets and the iPhone
/// always use .modern.
enum Look: String, CaseIterable, Identifiable {
    /// Soft graphite, warm off-white text, calmer colours and rounded type. Easy on the eyes,
    /// made for someone opening Viggo+ for the first time. The default.
    case calm = "rolig"
    /// Near-black background and bright colours, from the fomo app (1.28).
    case modern = "nyt"
    /// From before 1.28: the Mac's own greys, system blue and a frosted panel.
    case classic = "klassisk"
    var id: String { rawValue }
    var title: String {
        switch self { case .calm: "Rolig"; case .modern: "Kontrast"; case .classic: "Klassisk" }
    }
    var blurb: String {
        switch self {
        case .calm: "Blød grafit, varm hvid tekst og rolige farver. Nemt for øjnene, også om aftenen."
        case .modern: "Næsten sort baggrund og stærke farver, der springer i øjnene."
        case .classic: "Mac'ens egne grå farver, systemblå og et mat glas-panel. Som før 1.28."
        }
    }
}

enum Fomo {
    nonisolated(unsafe) static var look: Look = .modern
    static var classic: Bool { look == .classic }
    /// Rolig uses SF Rounded: softer and friendlier to read in small sizes.
    static var design: Font.Design { look == .calm ? .rounded : .default }

    private static var p: Palette { switch look { case .calm: Calm.p; case .modern: Modern.p; case .classic: Classic.p } }
    static func palette(_ l: Look) -> Palette { switch l { case .calm: Calm.p; case .modern: Modern.p; case .classic: Classic.p } }

    static var bg: Color { p.bg }
    static var surface: Color { p.surface }
    /// Tracks, placeholders and chips inside a surface.
    static var surface2: Color { p.surface2 }
    static var accent: Color { p.accent }
    /// Darker in light mode, so green text on a white card is readable (about 5:1 instead of 2:1).
    static var green: Color { p.green }
    static var red: Color { p.red }
    /// Deadlines, homework and other things to look at. Darker in light mode for the same reason as green.
    static var warn: Color { p.warn }
    /// Text on a green fill: white on the dark light-mode green, black on the bright dark-mode one.
    static var onGreen: Color { p.onGreen }
    static var text2: Color { p.text2 }

    struct Palette {
        let bg, surface, surface2, accent, green, red, warn, onGreen, text2: Color
        var text: Color? = nil
    }

    private enum Modern {
        static let p = Palette(
            bg: dynamic(light: 0xF4F4F7, dark: 0x060510),
            surface: dynamic(light: 0xFFFFFF, dark: 0x12111A),
            surface2: dynamic(light: 0xE9E9EF, dark: 0x1D1C29),
            accent: Color(hex: 0x4F6AF8),
            green: dynamic(light: 0x15803D, dark: 0x21C95E),
            red: Color(hex: 0xEF371F),
            warn: dynamic(light: 0xC2410C, dark: 0xFF9F0A),
            onGreen: dynamic(light: 0xFFFFFF, dark: 0x06240F),
            text2: dynamic(light: 0x6B6B76, dark: 0x9899A3))
    }

    /// Rolig. Contrast checked against WCAG: main text 13-16:1, grey text 5-7:1, coloured text
    /// at least 4.4:1 on both the background and the cards. No pure black or pure white, which
    /// glare on a screen in a dark room.
    private enum Calm {
        static let p = Palette(
            bg: dynamic(light: 0xF2F1EE, dark: 0x16171B),
            surface: dynamic(light: 0xFFFFFF, dark: 0x202127),
            surface2: dynamic(light: 0xE7E5E0, dark: 0x2C2D34),
            accent: dynamic(light: 0x3A66D4, dark: 0x5B83E8),
            green: dynamic(light: 0x1D7F4E, dark: 0x4FC08A),
            red: dynamic(light: 0xC23B2F, dark: 0xEE6E62),
            warn: dynamic(light: 0x9E5A00, dark: 0xEDA84D),
            onGreen: dynamic(light: 0xFFFFFF, dark: 0x0C2A1C),
            text2: dynamic(light: 0x67655F, dark: 0xA2A2AA),
            text: dynamic(light: 0x23221F, dark: 0xE8E7E3))
    }

    private enum Classic {
        #if os(macOS)
        static let bg = Color(nsColor: .windowBackgroundColor)
        #else
        static let bg = Color(uiColor: .systemBackground)
        #endif
        static let p = Palette(bg: bg, surface: Color.primary.opacity(0.06), surface2: Color.primary.opacity(0.1),
                               accent: .accentColor, green: .green, red: .red, warn: .orange, onGreen: .white, text2: .secondary)
    }

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
    /// The type of the current look (rounded in Rolig) for text without its own font.
    /// Put it on the root of each window.
    func looked() -> some View { fontDesign(Fomo.design) }

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
