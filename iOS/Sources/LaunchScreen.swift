import SwiftUI

/// Shown at launch until the first sync is done: the icon draws itself, the "+" pops in,
/// and a soft halo pulses while Viggo answers.
struct LaunchScreen: View {
    let style = IconStyle.current
    @State private var appear = false
    @State private var draw: CGFloat = 0
    @State private var badge: CGFloat = 0
    @State private var pulse = false
    @State private var step = 0
    @State private var showText = false

    private let steps = ["Henter skema", "Henter lektier", "Henter beskeder", "Næsten klar"]

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            // Coloured glow behind the icon, in the icon's own colours.
            Circle()
                .fill(RadialGradient(colors: [style.top.opacity(0.45), style.bottom.opacity(0.15), .clear],
                                     center: .center, startRadius: 0, endRadius: 260))
                .frame(width: 520, height: 520)
                .scaleEffect(appear ? 1 : 0.4)
                .opacity(appear ? 1 : 0)
                .blur(radius: 20)
                .offset(y: -40)

            VStack(spacing: 40) {
                ZStack {
                    // Halo rings that keep pulsing outwards while loading.
                    ForEach(0..<2) { i in
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .stroke(style.top.opacity(0.5), lineWidth: 2)
                            .frame(width: 128, height: 128)
                            .scaleEffect(pulse ? 1.6 : 1)
                            .opacity(pulse ? 0 : 0.8)
                            .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false).delay(Double(i) * 0.9),
                                       value: pulse)
                    }
                    IconArt(style: style, size: 128, progress: draw, badge: badge)
                        .shadow(color: style.bottom.opacity(0.45), radius: 24, y: 12)
                        .scaleEffect(appear ? 1 : 0.5)
                        .rotationEffect(.degrees(appear ? 0 : -12))
                        .opacity(appear ? 1 : 0)
                }

                VStack(spacing: 8) {
                    Text("Viggo+")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                    // One line that rolls to the next step, like a departure board.
                    ZStack {
                        Text(steps[step])
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .id(step)
                            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                    removal: .move(edge: .top).combined(with: .opacity)))
                    }
                    .frame(height: 20)
                    .clipped()
                    LoadingDots(color: style.top)
                        .padding(.top, 6)
                }
                .opacity(showText ? 1 : 0)
                .offset(y: showText ? 0 : 14)
            }
            .offset(y: -20)
        }
        .task { await run() }
    }

    private func run() async {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { appear = true }
        try? await Task.sleep(for: .milliseconds(180))
        withAnimation(.easeInOut(duration: 0.55)) { draw = 1 }
        try? await Task.sleep(for: .milliseconds(520))
        Haptic.firm()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) { badge = 1 }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.1)) { showText = true }
        pulse = true
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(1100))
            guard step < steps.count - 1 else { break }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step += 1 }
        }
    }
}

/// Three dots that bounce one after another.
struct LoadingDots: View {
    let color: Color
    @State private var on = false

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<3) { i in
                Circle().fill(color.gradient)
                    .frame(width: 8, height: 8)
                    .scaleEffect(on ? 1 : 0.5)
                    .opacity(on ? 1 : 0.35)
                    .offset(y: on ? -4 : 2)
                    .animation(.easeInOut(duration: 0.45).repeatForever().delay(Double(i) * 0.15), value: on)
            }
        }
        .onAppear { on = true }
    }
}
