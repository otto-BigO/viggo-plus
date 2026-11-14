import SwiftUI
import UIKit

// The iPhone app's small animations: zoom from what you tapped, grey placeholders while loading,
// cards that settle in as you scroll, the pulsing "now" dot, the dots while a message is sent,
// and the app icon in pull to refresh.

// MARK: - Zoom from what you tapped

extension EnvironmentValues {
    /// The namespace a screen's zoom sources and destinations share. Nil turns the zoom off.
    @Entry var zoomSpace: Namespace.ID? = nil
}

extension View {
    /// Marks the view a page grows out of (an avatar, a card).
    func zoomSource<ID: Hashable>(_ id: ID) -> some View { modifier(ZoomSource(id: id)) }
    /// The page that grows out of the source with the same id, and can be dragged down to close.
    func zoomsFrom<ID: Hashable>(_ id: ID) -> some View { modifier(ZoomTarget(id: id)) }
}

extension View {
    /// A person's page grows out of their picture. Groups, threads and houses have no picture
    /// to grow out of, so they slide in as usual.
    @ViewBuilder func zoomsFromPicture(_ found: Found) -> some View {
        if case .person = found { zoomsFrom(found) } else { self }
    }
}

private struct ZoomSource<ID: Hashable>: ViewModifier {
    @Environment(\.zoomSpace) private var space
    let id: ID
    func body(content: Content) -> some View {
        if let space { content.matchedTransitionSource(id: id, in: space) } else { content }
    }
}

private struct ZoomTarget<ID: Hashable>: ViewModifier {
    @Environment(\.zoomSpace) private var space
    let id: ID
    func body(content: Content) -> some View {
        if let space { content.navigationTransition(.zoom(sourceID: id, in: space)) } else { content }
    }
}

// MARK: - Placeholders while loading

enum Skeleton {
    /// `VIGGO_SKELETON=1` keeps the placeholders up, to look at them in the simulator.
    static let forced = ProcessInfo.processInfo.environment["VIGGO_SKELETON"] != nil
}

/// A soft light that sweeps across placeholders, so a loading screen looks alive.
private struct Shimmer: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var go = false

    func body(content: Content) -> some View {
        if active, !reduce {
            content
                .overlay {
                    GeometryReader { g in
                        LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: max(120, g.size.width * 0.5))
                            .offset(x: go ? g.size.width : -max(120, g.size.width * 0.5))
                            .animation(.linear(duration: 1.25).repeatForever(autoreverses: false), value: go)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
                .onAppear { go = true }
        } else {
            content
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
        RoundedRectangle(cornerRadius: height / 2, style: .continuous).fill(Color(.systemFill))
            .frame(maxWidth: width ?? .infinity).frame(height: height)
    }
}

/// The inbox before the first messages arrive: rows the shape of the real ones.
struct SkeletonThreads: View {
    private let widths: [(CGFloat, CGFloat)] = [(120, 210), (90, 170), (150, 240), (110, 190), (130, 220), (80, 160), (140, 200), (100, 230)]
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(widths.enumerated()), id: \.offset) { _, w in
                HStack(spacing: 10) {
                    Circle().fill(.clear).frame(width: 10, height: 10)
                    Circle().fill(Color(.systemFill)).frame(width: 50, height: 50)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { SkeletonBar(width: w.0, height: 13); Spacer(); SkeletonBar(width: 34, height: 10) }
                        SkeletonBar(width: w.1, height: 11)
                        SkeletonBar(width: w.1 * 0.7, height: 11)
                    }
                }
                .padding(.vertical, 11).padding(.leading, 8).padding(.trailing, 16)
            }
        }
        .shimmer()
        .accessibilityLabel("Henter beskeder")
    }
}

/// A thread before it has loaded: bubbles on both sides.
struct SkeletonBubbles: View {
    private let rows: [(Bool, CGFloat, CGFloat)] = [(false, 210, 54), (false, 150, 36), (true, 180, 36), (false, 240, 72), (true, 220, 54), (true, 120, 36)]
    var body: some View {
        VStack(spacing: 6) {
            SkeletonBar(width: 180, height: 15).padding(.top, 16).padding(.bottom, 18)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack(alignment: .bottom, spacing: 6) {
                    if r.0 { Spacer(minLength: 0) } else { Circle().fill(Color(.systemFill)).frame(width: 28, height: 28) }
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.systemFill))
                        .frame(width: r.1, height: r.2)
                    if !r.0 { Spacer(minLength: 0) }
                }
            }
        }
        .padding(.horizontal, 12)
        .shimmer()
        .accessibilityLabel("Henter beskeden")
    }
}

/// A day's list before the schedule has arrived.
struct SkeletonDay: View {
    var rows = 5
    private let widths: [CGFloat] = [150, 110, 180, 130, 160, 120]
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { i in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) { SkeletonBar(width: 38, height: 11); SkeletonBar(width: 30, height: 9) }
                        .frame(width: 48, alignment: .leading)
                    RoundedRectangle(cornerRadius: 2).fill(Color(.systemFill)).frame(width: 4, height: 38)
                    VStack(alignment: .leading, spacing: 7) {
                        SkeletonBar(width: widths[i % widths.count], height: 13)
                        SkeletonBar(width: widths[(i + 2) % widths.count] * 0.6, height: 10)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
            }
        }
        .shimmer()
        .accessibilityLabel("Henter skema")
    }
}

/// A person or group page before the address book has loaded.
struct SkeletonProfile: View {
    var body: some View {
        VStack(spacing: 14) {
            Circle().fill(Color(.systemFill)).frame(width: 110, height: 110).padding(.top, 24)
            SkeletonBar(width: 190, height: 20)
            SkeletonBar(width: 120, height: 12)
            VStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.systemFill)).frame(height: 58)
                }
            }
            .padding(.top, 14)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .shimmer()
        .accessibilityLabel("Henter")
    }
}

// MARK: - Cards that settle in

extension View {
    /// A card coming up from below fades and grows the last bit into place.
    func cardEntrance() -> some View { modifier(CardEntrance()) }
}

private struct CardEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        let calm = reduce
        content.scrollTransition(.animated(.spring(response: 0.5, dampingFraction: 0.84)).threshold(.visible(0.04))) { c, phase in
            let below = phase == .bottomTrailing
            return c
                .opacity(below ? 0 : 1)
                .scaleEffect(below && !calm ? 0.94 : 1, anchor: .top)
                .offset(y: below && !calm ? 22 : 0)
        }
    }
}

// MARK: - Now

/// A dot with a ring that keeps spreading out from it: "this is happening now".
struct PulseDot: View {
    var color: Color = .white
    var size: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var on = false

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
            .background {
                if !reduce {
                    Circle().fill(color)
                        .scaleEffect(on ? 2.8 : 1)
                        .opacity(on ? 0 : 0.55)
                        .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: on)
                }
            }
            .onAppear { on = true }
    }
}

/// The tinted background of the lesson that is on, breathing slowly.
struct NowGlow: View {
    let color: Color
    var radius: CGFloat = 14
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var on = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(color.opacity(0.12))
            .overlay {
                if !reduce {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(color.opacity(0.13))
                        .opacity(on ? 1 : 0)
                        .animation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true), value: on)
                }
            }
            .onAppear { on = true }
    }
}

/// The line across a day's list at the current time, when nothing is on right now.
struct NowLine: View {
    let now: Date
    @ScaledMetric(relativeTo: .subheadline) private var timeW: CGFloat = 48
    var body: some View {
        HStack(spacing: 8) {
            Text(DateUtil.hm(now)).font(.caption.monospacedDigit().weight(.bold)).foregroundStyle(.red).lineLimit(1)
                .frame(width: timeW, alignment: .leading)
                .contentTransition(.numericText())
            PulseDot(color: .red, size: 7)
            Rectangle().fill(Color.red.opacity(0.7)).frame(height: 1.5)
        }
        .padding(.vertical, 5)
        .accessibilityLabel("Klokken er \(DateUtil.hm(now))")
    }
}

// MARK: - Sending

/// Three dots that bounce in turn, like someone typing in Beskeder.
struct TypingDots: View {
    var color: Color = .secondary
    var size: CGFloat = 5
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduce)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: size * 0.7) {
                ForEach(0..<3, id: \.self) { i in
                    let p = reduce ? 0.6 : (sin(t * 6 - Double(i) * 0.9) + 1) / 2
                    Circle().fill(color).frame(width: size, height: size)
                        .offset(y: -p * size * 0.7)
                        .opacity(0.4 + 0.6 * p)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Pull to refresh

/// Runs a refresh to the end. SwiftUI cancels the pull's own task when the screen redraws
/// during it, which stopped the fetch halfway with "cancelled".
@MainActor func finish(_ work: @escaping @MainActor () async -> Void) async {
    await Task { @MainActor in await work() }.value
}

extension View {
    /// Shows the app's icon in pull to refresh instead of the system spinner. Put it on the
    /// scroll view or list that has `.refreshable`.
    func refreshIcon() -> some View { background(RefreshIconHook().frame(width: 0, height: 0).accessibilityHidden(true)) }
}

/// Finds the scroll view's refresh control and puts the icon in it. The pull, the haptic and the
/// place under the title stay the system's; if the control is not found, so does the spinner.
private struct RefreshIconHook: UIViewRepresentable {
    func makeUIView(context: Context) -> Finder { Finder() }
    func updateUIView(_ v: Finder, context: Context) { v.attachSoon() }

    final class Finder: UIView {
        private weak var control: UIRefreshControl?
        private weak var scroll: UIScrollView?
        private var icon: UIImageView?
        private var watch: NSKeyValueObservation?
        private var tries = 0
        private var spinning = false
        private var style = ""

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { tries = 0; attachSoon() }
        }

        func attachSoon() {
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }

        private func attach() {
            guard window != nil else { return }
            if control != nil { paint(); return }
            guard let s = nearestScroll(), let rc = s.refreshControl else {
                // The control is made a moment after the list; look again a few times.
                tries += 1
                if tries < 12 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.attach() } }
                return
            }
            scroll = s
            control = rc
            rc.tintColor = .clear
            // In the scroll view, not in the control, which lays out its own subviews.
            let v = UIImageView(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
            v.layer.shadowColor = UIColor.black.cgColor
            v.layer.shadowOpacity = 0.18
            v.layer.shadowRadius = 4
            v.layer.shadowOffset = CGSize(width: 0, height: 2)
            v.layer.zPosition = 10
            v.alpha = 0
            v.isUserInteractionEnabled = false
            s.addSubview(v)
            icon = v
            paint()
            watch = s.observe(\.contentOffset) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.follow() }
            }
        }

        /// The scroll view with a refresh control closest to this view in the hierarchy.
        private func nearestScroll() -> UIScrollView? {
            var from: UIView = self
            var up = superview
            var steps = 0
            while let u = up, steps < 8 {
                if let s = u as? UIScrollView, s.refreshControl != nil { return s }
                if let s = Self.find(in: u, skip: from) { return s }
                from = u; up = u.superview; steps += 1
            }
            return nil
        }

        private static func find(in v: UIView, skip: UIView) -> UIScrollView? {
            for c in v.subviews where c !== skip {
                if let s = c as? UIScrollView, s.refreshControl != nil { return s }
                if let s = find(in: c, skip: skip) { return s }
            }
            return nil
        }

        /// Draws the icon the user has picked.
        private func paint() {
            let now = IconStyle.current
            guard now.id != style, let icon else { return }
            style = now.id
            let r = ImageRenderer(content: IconArt(style: now, size: 30))
            r.scale = window?.screen.scale ?? 3
            icon.image = r.uiImage
        }

        private func follow() {
            guard let s = scroll, let rc = control, let icon else { return }
            // How far the list is pulled below its resting place (the hold while refreshing included).
            let rest = s.adjustedContentInset.top - (rc.isRefreshing ? rc.bounds.height : 0)
            let pull = -(s.contentOffset.y + rest)
            // Where the system spinner sits: with a large title the control lives up under the bar,
            // not in the list, so ask it where it is.
            if rc.window != nil {
                icon.center = rc.convert(CGPoint(x: rc.bounds.midX, y: rc.bounds.midY), to: s)
            } else {
                icon.center = CGPoint(x: s.bounds.midX, y: s.contentOffset.y + rest + max(pull, 0) / 2)
            }
            if rc.isRefreshing {
                if !spinning {
                    spinning = true
                    icon.alpha = 1
                    icon.transform = .identity
                    // Turns like a coin while the new data is fetched.
                    var persp = CATransform3DIdentity
                    persp.m34 = -1 / 220
                    let a = CAKeyframeAnimation(keyPath: "transform")
                    a.values = [0, 0.25, 0.5, 0.75, 1].map { NSValue(caTransform3D: CATransform3DRotate(persp, CGFloat($0) * 2 * .pi, 0, 1, 0)) }
                    a.duration = 1.1
                    a.repeatCount = .infinity
                    a.calculationMode = .linear
                    icon.layer.add(a, forKey: "spin")
                }
                return
            }
            if spinning {
                spinning = false
                icon.layer.removeAnimation(forKey: "spin")
            }
            let p = min(1, max(0, (pull - 12) / 80))
            icon.alpha = p
            icon.transform = CGAffineTransform(rotationAngle: (1 - p) * -.pi * 0.75).scaledBy(x: 0.45 + 0.55 * p, y: 0.45 + 0.55 * p)
        }
    }
}
