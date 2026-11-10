import SwiftUI

/// Soft northern lights in the app icon's colours: a mesh gradient whose points drift slowly,
/// a few stars, and the title rising out of it.
struct AuroraIntro: View {
    private let style = IconStyle.current
    @State private var shown = LaunchScreen.frozen != nil

    var body: some View {
        ZStack {
            IntroClock(still: 2) { t in
                ZStack {
                    MeshGradient(width: 3, height: 3, points: points(t), colors: colors)
                    stars(t)
                }
                .opacity(min(1, t / 0.5))
            }
            VStack(spacing: 14) {
                (Text("Viggo") + Text("+").foregroundStyle(style.top.mix(with: .white, by: 0.55)))
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: style.top.opacity(0.8), radius: 24)
                StepTicker(color: .white.opacity(0.75))
                LoadingDots(color: .white.opacity(0.9))
                    .padding(.top, 2)
            }
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.9)
            .blur(radius: shown ? 0 : 8)
            .offset(y: -40)
        }
        .background(IconStyle.hex(0x05060F))
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .task {
            guard !shown else { return }
            try? await Task.sleep(for: .milliseconds(450))
            Haptic.soft()
            withAnimation(.spring(response: 0.9, dampingFraction: 0.85)) { shown = true }
        }
    }

    private var colors: [Color] {
        let night = IconStyle.hex(0x05060F)
        let a = style.top, b = style.bottom
        return [
            night, a.mix(with: night, by: 0.55), night,
            b.mix(with: night, by: 0.2), a.mix(with: .white, by: 0.1), b.mix(with: night, by: 0.4),
            night, b.mix(with: night, by: 0.6), a.mix(with: night, by: 0.7),
        ]
    }

    /// Corners stay put, the edge points slide along their edges, the middle wanders.
    private func points(_ t: Double) -> [SIMD2<Float>] {
        func s(_ k: Double, _ p: Double) -> Float { Float(sin(t * k + p)) }
        return [
            [0, 0], [0.5 + 0.2 * s(0.7, 0), 0], [1, 0],
            [0, 0.45 + 0.15 * s(0.6, 1)], [0.5 + 0.18 * s(0.5, 2), 0.42 + 0.14 * s(0.8, 3)], [1, 0.55 + 0.15 * s(0.55, 4)],
            [0, 1], [0.5 + 0.2 * s(0.65, 5), 1], [1, 1],
        ]
    }

    private func stars(_ t: Double) -> some View {
        Canvas { ctx, size in
            for i in 0..<60 {
                let x = hash(i, 1) * size.width, y = hash(i, 2) * size.height * 0.75
                let tw = 0.5 + 0.5 * sin(t * (0.8 + hash(i, 3) * 2) + Double(i))
                let r = 0.6 + hash(i, 4) * 1.1
                ctx.fill(Circle().path(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity(0.15 + 0.55 * tw)))
            }
        }
        .blendMode(.plusLighter)
    }

    private func hash(_ a: Int, _ b: Int) -> CGFloat {
        var h = UInt64(truncatingIfNeeded: a &* 73_856_093 ^ b &* 19_349_663)
        h ^= h >> 33; h &*= 0xff51_afd7_ed55_8ccd; h ^= h >> 33
        return CGFloat(h % 10_000) / 10_000
    }
}
