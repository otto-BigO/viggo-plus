import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// The look, borrowed from the fomo app: one dark background and one surface, no borders or
// shadows, and colours that mean something. Accent is something you can do, green is done or
// good, red is cancelled or a problem. Everything else is white or grey.

enum Fomo {
    static let bg = dynamic(light: 0xF4F4F7, dark: 0x060510)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x12111A)
    /// Tracks, placeholders and chips inside a surface.
    static let surface2 = dynamic(light: 0xE9E9EF, dark: 0x1D1C29)
    static let accent = Color(hex: 0x4F6AF8)
    static let green = Color(hex: 0x21C95E)
    static let red = Color(hex: 0xEF371F)
    static let text2 = dynamic(light: 0x6B6B76, dark: 0x9899A3)
    static let radius: CGFloat = 14
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

extension PlatformColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

extension View {
    /// A flat card on the surface colour: no border, no shadow.
    func surface(_ radius: CGFloat = Fomo.radius, fill: Color = Fomo.surface) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
    }
}

// MARK: - Status pill

/// A pill at the top that says what is happening and morphs when it is done:
/// "Markerer..." becomes "Lektie klaret ✓ Fortryd". The change shows at once; the pill confirms it.
@MainActor
final class StatusPill: ObservableObject {
    static let shared = StatusPill()
    enum Phase: Equatable { case working, done, failed }
    @Published private(set) var text = ""
    @Published private(set) var phase: Phase = .working
    @Published private(set) var shown = false
    @Published private(set) var canUndo = false
    private var undo: (() -> Void)?
    private var hide: Task<Void, Never>?

    func working(_ t: String) {
        hide?.cancel()
        undo = nil; canUndo = false
        text = t; phase = .working; shown = true
        // Never stuck: if nothing answers, it goes after a while.
        later(12)
    }

    func done(_ t: String, undo: (() -> Void)? = nil) {
        self.undo = undo; canUndo = undo != nil
        text = t; phase = .done; shown = true
        later(undo == nil ? 2.2 : 4.5)
    }

    func failed(_ t: String) {
        undo = nil; canUndo = false
        text = t; phase = .failed; shown = true
        Haptic.error()
        later(4)
    }

    func runUndo() {
        let u = undo
        undo = nil; canUndo = false
        Haptic.tap()
        u?()
    }

    func dismiss() { hide?.cancel(); shown = false }

    private func later(_ s: Double) {
        hide?.cancel()
        hide = Task { [weak self] in
            try? await Task.sleep(for: .seconds(s))
            guard !Task.isCancelled else { return }
            self?.shown = false
        }
    }
}

struct StatusPillView: View {
    @ObservedObject var pill = StatusPill.shared
    var compact = false

    var body: some View {
        ZStack {
            if pill.shown {
                HStack(spacing: 7) {
                    Group {
                        switch pill.phase {
                        case .working: SpinRing().frame(width: 12, height: 12)
                        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Fomo.green)
                        case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Fomo.red)
                        }
                    }
                    .font(.system(size: compact ? 12 : 14, weight: .semibold))
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                    Text(pill.text)
                        .font(.system(size: compact ? 12 : 14, weight: .semibold))
                        .lineLimit(1)
                        .contentTransition(.interpolate)
                    if pill.canUndo {
                        Button("Fortryd") { pill.runUndo() }
                            .buttonStyle(.plain)
                            .font(.system(size: compact ? 12 : 14, weight: .semibold))
                            .foregroundStyle(Fomo.accent)
                            .padding(.leading, 2)
                            .transition(.opacity.combined(with: .offset(x: 6)))
                    }
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, compact ? 12 : 16).padding(.vertical, compact ? 7 : 10)
                .background(Capsule().fill(Fomo.surface2))
                .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9, anchor: .top)))
                .accessibilityElement(children: .combine)
            }
        }
        .animation(Fomo.spring, value: pill.shown)
        .animation(Fomo.spring, value: pill.text)
        .animation(Fomo.spring, value: pill.phase)
        .animation(Fomo.spring, value: pill.canUndo)
    }
}

/// A small ring that turns while something is under way. Calm (a still ring) with Reduce Motion.
struct SpinRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var turn = false
    var body: some View {
        Circle().trim(from: 0, to: 0.7)
            .stroke(Fomo.text2, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            .rotationEffect(.degrees(turn ? 360 : 0))
            .animation(reduce ? nil : .linear(duration: 0.8).repeatForever(autoreverses: false), value: turn)
            .onAppear { turn = true }
    }
}

// MARK: - Placeholders while loading

enum Skeleton {
    /// `VIGGO_SKELETON=1` keeps the placeholders up, to look at them.
    static let forced = ProcessInfo.processInfo.environment["VIGGO_SKELETON"] != nil
}

/// A soft light that sweeps across placeholders, so a loading screen looks alive.
///
/// The content itself is never swapped: only the overlay comes and goes. Branching on `active`
/// around the content rebuilt the cards under it when loading ended (their state reset and their
/// own animations started over), and the sweep is driven by the clock, so it runs every time.
private struct Shimmer: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce

    func body(content: Content) -> some View {
        let on = active && !reduce
        content.overlay {
            if on {
                GeometryReader { g in
                    let w = max(120, g.size.width * 0.5)
                    TimelineView(.animation) { tl in
                        let p = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.25) / 1.25
                        LinearGradient(colors: [.clear, .white.opacity(0.18), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: w)
                            .offset(x: -w + (g.size.width + w) * p)
                    }
                }
                .mask(content)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
    }
}

extension View {
    func shimmer(_ active: Bool = true) -> some View { modifier(Shimmer(active: active)) }
}

/// A grey bar that stands in for a line of text.
struct SkeletonBar: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12
    var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous).fill(Fomo.surface2)
            .frame(maxWidth: width ?? .infinity).frame(height: height)
    }
}

/// Rows the shape of a list of people or messages: a round picture and two lines.
struct SkeletonRows: View {
    var count = 6
    var avatar: CGFloat = 32
    private let widths: [(CGFloat, CGFloat)] = [(120, 200), (90, 160), (150, 230), (110, 180), (130, 210), (80, 150), (140, 190), (100, 220)]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                let w = widths[i % widths.count]
                HStack(spacing: 10) {
                    if avatar > 0 { Circle().fill(Fomo.surface2).frame(width: avatar, height: avatar) }
                    VStack(alignment: .leading, spacing: 7) {
                        SkeletonBar(width: w.0, height: 11)
                        SkeletonBar(width: w.1, height: 9)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
            }
        }
        .shimmer()
        .accessibilityLabel("Henter")
    }
}

// MARK: - Avatar stack

/// Overlapping faces, "+2" when there are more. Used for "Fri sammen med" and "Venner nu".
struct AvatarStack: View {
    struct Face: Identifiable { let id: String; let url: URL?; let name: String }
    let faces: [Face]
    var size: CGFloat = 22
    var max = 4
    var ring: Color = Fomo.surface

    var body: some View {
        HStack(spacing: -size * 0.32) {
            ForEach(faces.prefix(max)) { f in
                Avatar(url: f.url, size: size, name: f.name)
                    .overlay(Circle().stroke(ring, lineWidth: size > 26 ? 2 : 1.5))
            }
            if faces.count > max {
                Text("+\(faces.count - max)")
                    .font(.system(size: size * 0.36, weight: .bold)).monospacedDigit()
                    .foregroundStyle(Fomo.text2)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Fomo.surface2))
                    .overlay(Circle().stroke(ring, lineWidth: size > 26 ? 2 : 1.5))
            }
        }
        .accessibilityLabel(faces.map(\.name).joined(separator: ", "))
    }
}

// MARK: - Drawing in

/// Things that draw themselves in when a screen opens: short (under 0.4 s), and only once per
/// opening. Off with Reduce Motion or under Udseende og haptik. Never decides whether something
/// is visible: if the animation does not run, the view simply sits where it belongs.
struct DrawIn: ViewModifier {
    var delay: Double = 0
    var y: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = false
    func body(content: Content) -> some View {
        let animate = !reduce && Prefs.shared.drawIn && !CommandLine.arguments.contains("--render-docs")
        content
            .opacity(animate && !shown ? 0 : 1)
            .offset(y: animate && !shown ? y : 0)
            .onAppear {
                guard animate, !shown else { return }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.86).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func drawIn(delay: Double = 0, y: CGFloat = 8) -> some View { modifier(DrawIn(delay: delay, y: y)) }
}

// MARK: - Progress

/// How far through the lesson you are. It glides at the speed of the clock instead of jumping once a
/// minute, and fills in from the left when the panel opens. Linear on purpose: it tracks real time.
struct GlideBar: View {
    let start: Date
    let end: Date
    /// The app's clock (it ticks about once a minute). The bar runs on from it second by second.
    let now: Date
    let color: Color
    var height: CGFloat = 4
    var track: Color = Fomo.surface2
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var grown = false
    /// When `now` last changed, in real time.
    @State private var anchor = Date()

    private func frac(_ t: Date) -> Double {
        min(1, max(0, t.timeIntervalSince(start) / max(1, end.timeIntervalSince(start))))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let f = frac(now.addingTimeInterval(min(120, max(0, ctx.date.timeIntervalSince(anchor)))))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(track)
                    Capsule().fill(color)
                        .frame(width: max(height, g.size.width * (grown || reduce ? f : 0)))
                        .animation(grown ? .linear(duration: 1) : nil, value: f)
                }
            }
        }
        .frame(height: height)
        .onChange(of: now) { anchor = Date() }
        .onAppear { grow() }
        // The Mac panel is kept and only ordered front, and on the iPhone the app is built under
        // the launch screen, so onAppear alone played the fill-in once, or out of sight.
        .onReceive(NotificationCenter.default.publisher(for: .viggoRevealed)) { _ in
            guard !reduce, Prefs.shared.drawIn else { return }
            grown = false
            DispatchQueue.main.async { grow() }
        }
    }

    private func grow() {
        guard !grown else { return }
        if reduce || !Prefs.shared.drawIn || CommandLine.arguments.contains("--render-docs") { grown = true; return }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.9).delay(0.08)) { grown = true }
    }
}

extension Notification.Name {
    /// Posted when the Mac panel opens and when the iPhone launch screen goes, so entrance
    /// animations play where they can be seen.
    static let viggoRevealed = Notification.Name("ViggoRevealed")
}
