import SwiftUI

/// A login the app runs by itself, shown as a small badge instead of the sign-in card.
struct QuietLogin: Identifiable, Equatable {
    /// The id used for your own login; friends use their own id.
    static let me = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    let id: UUID
    let name: String
    let image: URL?
    var stage: LoginStage = .viggo

    var failed: Bool { if case .failure = stage { return true } else { return false } }
    var done: Bool { stage == .success }
    /// 0...1 for the ring around the picture.
    var progress: Double { done || failed ? 1 : max(0.12, Double(stage.step) / 4.4) }
    var who: String { id == Self.me ? "dig" : name }

    var title: String {
        if done { return id == Self.me ? "Du er logget ind" : "\(name) er logget ind" }
        if failed { return id == Self.me ? "Log ind igen" : "\(name) skal logge ind" }
        return "Logger \(who) ind"
    }
    var detail: String {
        switch stage {
        case .success: return "Klar"
        case .saving, .viggo: return "Viggo"
        case .unilogin: return "UNI-Login"
        case .skoleit: return "SkoleIT"
        case .verifying: return "Bekræfter"
        case .failure: return "Tryk for at logge ind"
        }
    }
}

/// The picture with a ring that fills as the login moves from Viggo to UNI-Login to SkoleIT. Spins a
/// little light around while it waits, turns green with a tick when it's done and orange if not.
struct QuietLoginAvatar: View {
    let q: QuietLogin
    var size: CGFloat = 30
    @State private var spin = false

    private var tint: Color { q.failed ? .orange : q.done ? .green : .accentColor }

    var body: some View {
        ZStack {
            Avatar(url: q.image, size: size, name: q.name)
            Circle().stroke(tint.opacity(0.18), lineWidth: 2.5)
                .frame(width: size + 7, height: size + 7)
            Circle().trim(from: 0, to: q.progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: size + 7, height: size + 7)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: q.progress)
            if !q.done && !q.failed {
                // A short bright arc running round the ring, so it is clearly working.
                Circle().trim(from: 0, to: 0.12)
                    .stroke(tint.opacity(0.9), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: size + 7, height: size + 7)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spin)
                    .onAppear { spin = true }
            }
            if q.done || q.failed {
                Image(systemName: q.done ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, tint)
                    .background(Circle().fill(.background).padding(1))
                    .offset(x: size * 0.42, y: size * 0.42)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .frame(width: size + 10, height: size + 10)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: q.done)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: q.failed)
    }
}

/// The corner badge: one pill per login, stacked. Lives on top of the iPhone app and in the Mac
/// panel and settings window. A failed one is a button that opens the normal login.
struct QuietLoginBadges: View {
    @EnvironmentObject var state: AppState
    var compact = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(state.quietLogins) { q in
                pill(q)
                    .contentShape(Capsule())
                    .onTapGesture { if q.failed { state.openQuietLogin(q) } }
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.8)),
                                            removal: .opacity.combined(with: .scale(scale: 0.9))))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: state.quietLogins)
    }

    private func pill(_ q: QuietLogin) -> some View {
        HStack(spacing: 8) {
            QuietLoginAvatar(q: q, size: compact ? 20 : 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(q.title).font(.system(size: compact ? 11 : 13, weight: .semibold))
                    .contentTransition(.opacity)
                Text(q.detail).font(.system(size: compact ? 9.5 : 11)).foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            .lineLimit(1)
        }
        .padding(.leading, 4).padding(.trailing, 12).padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(q.failed ? Color.orange.opacity(0.5) : .primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
        .animation(.easeInOut(duration: 0.25), value: q.stage)
    }
}
