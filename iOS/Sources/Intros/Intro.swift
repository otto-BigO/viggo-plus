import SwiftUI

/// Shown at launch until the first sync is done. Which animation it is comes from
/// Indstillinger > Opstart: one of the intros switched on there, picked at random each launch.
struct LaunchScreen: View {
    let intro: Intro

    var body: some View { intro.view }

    /// Test hooks: `VIGGO_SPLASH_T=2.5` freezes the animation at that second and keeps it on
    /// screen, `VIGGO_SPLASH_HOUR=22` picks the time of day, `VIGGO_INTRO=owl` picks the intro.
    static let frozen = ProcessInfo.processInfo.environment["VIGGO_SPLASH_T"].flatMap(Double.init)
    /// `VIGGO_SPLASH_HOLD=1` keeps it on screen while it animates normally.
    static let hold = frozen != nil || ProcessInfo.processInfo.environment["VIGGO_SPLASH_HOLD"] != nil
    static let hour: Double = ProcessInfo.processInfo.environment["VIGGO_SPLASH_HOUR"].flatMap(Double.init) ?? {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60
    }()
    static var night: Bool { hour < 7 || hour >= 19 }

    static let steps = ["Henter skema", "Henter lektier", "Henter beskeder", "Næsten klar"]
}

enum Intro: String, CaseIterable, Identifiable {
    case radio, terminal, schedule, aurora, stardust, owl, asciiIcon, icon

    var id: String { rawValue }

    var name: String {
        switch self {
        case .radio: "Radio"
        case .terminal: "Terminal"
        case .schedule: "Skema"
        case .aurora: "Nordlys"
        case .stardust: "Stjernestøv"
        case .owl: "Ugle"
        case .asciiIcon: "ASCII-ikon"
        case .icon: "Ikon"
        }
    }

    var detail: String {
        switch self {
        case .radio: "ASCII-landskab i lo-fi-stil, skyer om dagen og en ring om natten"
        case .terminal: "Viggo+ starter op som en gammel computer"
        case .schedule: "Ugens timer falder på plads i skemaet"
        case .aurora: "Bløde farver i dit app-ikons farver"
        case .stardust: "Tusind prikker flyver sammen til Viggo+"
        case .owl: "Pixel-landskab med uglen på hegnspælen"
        case .asciiIcon: "Ikonet bygger sig selv op af tegn"
        case .icon: "Ikonet tegner sig selv med en glorie omkring"
        }
    }

    var symbol: String {
        switch self {
        case .radio: "radio.fill"
        case .terminal: "terminal.fill"
        case .schedule: "calendar"
        case .aurora: "sparkles"
        case .stardust: "circle.hexagongrid.fill"
        case .owl: "bird.fill"
        case .asciiIcon: "textformat.characters"
        case .icon: "app.fill"
        }
    }

    var color: Color {
        switch self {
        case .radio: .brown
        case .terminal: .green
        case .schedule: .red
        case .aurora: .purple
        case .stardust: .indigo
        case .owl: .orange
        case .asciiIcon: .teal
        case .icon: .blue
        }
    }

    /// The version it came with, for the old ones.
    var from: String? {
        switch self {
        case .owl: "1.0"
        case .asciiIcon: "0.7"
        case .icon: "0.6"
        default: nil
        }
    }

    @MainActor @ViewBuilder var view: some View {
        switch self {
        case .radio: RadioIntro()
        case .terminal: TerminalIntro()
        case .schedule: ScheduleIntro()
        case .aurora: AuroraIntro()
        case .stardust: StardustIntro()
        case .owl: OwlIntro()
        case .asciiIcon: AsciiIconIntro()
        case .icon: IconIntro()
        }
    }

    static let key = "intros"

    /// The intros switched on in Indstillinger. Radio until something else is picked.
    static var enabled: Set<Intro> {
        get {
            let ids = UserDefaults.standard.stringArray(forKey: key) ?? [Intro.radio.rawValue]
            let set = Set(ids.compactMap(Intro.init(rawValue:)))
            return set.isEmpty ? [.radio] : set
        }
        set { UserDefaults.standard.set(allCases.filter(newValue.contains).map(\.rawValue), forKey: key) }
    }

    /// The one to show at this launch.
    static func pick() -> Intro {
        if let s = ProcessInfo.processInfo.environment["VIGGO_INTRO"], let i = Intro(rawValue: s) { return i }
        return enabled.randomElement() ?? .radio
    }
}

/// The loading steps rolling past, like a departure board. Used by the newer intros.
struct StepTicker: View {
    var font: Font = .subheadline.weight(.medium)
    var color: Color = .secondary
    @State private var step = 0

    var body: some View {
        ZStack {
            Text(LaunchScreen.steps[step])
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .move(edge: .top).combined(with: .opacity)))
        }
        .font(font)
        .foregroundStyle(color)
        .frame(height: 20)
        .clipped()
        .task {
            while !Task.isCancelled, LaunchScreen.frozen == nil {
                try? await Task.sleep(for: .milliseconds(1100))
                guard step < LaunchScreen.steps.count - 1 else { break }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step += 1 }
            }
        }
    }
}

/// Seconds since the intro appeared, or the frozen test time. Drives the Canvas based intros.
struct IntroClock<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    var fps: Double = 30
    var still: Double = 3
    @ViewBuilder let content: (Double) -> Content

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / fps, paused: reduceMotion || LaunchScreen.frozen != nil)) { tl in
            content(LaunchScreen.frozen ?? (reduceMotion ? still : tl.date.timeIntervalSince(start)))
        }
    }
}

// MARK: - Indstillinger > Opstart

struct IntroPicker: View {
    @State private var on = Intro.enabled
    @State private var preview: Intro?
    @State private var nope = false

    private var newOnes: [Intro] { Intro.allCases.filter { $0.from == nil } }
    private var oldOnes: [Intro] { Intro.allCases.filter { $0.from != nil } }

    var body: some View {
        List {
            Section {
                ForEach(newOnes) { row($0) }
            } footer: {
                Text(on.count > 1
                     ? "Du får en tilfældig af de \(on.count) valgte, hver gang Viggo+ starter."
                     : "Vælg flere, så får du en tilfældig af dem hver gang Viggo+ starter.")
            }
            Section("De gamle") {
                ForEach(oldOnes) { row($0) }
            }
            Section {
                Button {
                    Haptic.tap()
                    preview = on.randomElement()
                } label: { Label("Afspil en tilfældig", systemImage: "shuffle") }
                Button {
                    Haptic.select()
                    withAnimation(.viggo) { on = Set(Intro.allCases) }
                    Intro.enabled = on
                } label: { Label("Slå alle til", systemImage: "checkmark.circle") }
                    .disabled(on.count == Intro.allCases.count)
            }
        }
        .fullScreenCover(item: $preview) { IntroPreview(intro: $0) }
        .sensoryFeedback(.error, trigger: nope)
    }

    private func row(_ i: Intro) -> some View {
        let isOn = on.contains(i)
        return HStack(spacing: 12) {
            Button { toggle(i) } label: {
                HStack(spacing: 12) {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isOn ? Color.accentColor : Color.secondary.opacity(0.5))
                        .contentTransition(.symbolEffect(.replace))
                    Image(systemName: i.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(i.color.gradient))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(i.name).foregroundStyle(.primary)
                            if let v = i.from {
                                Text("fra \(v)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Capsule().fill(Color(.tertiarySystemFill)))
                            }
                        }
                        Text(i.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                Haptic.tap()
                preview = i
            } label: {
                Image(systemName: "play.circle.fill").font(.title2).symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Afspil \(i.name)")
        }
        .padding(.vertical, 2)
    }

    private func toggle(_ i: Intro) {
        if on.contains(i) {
            guard on.count > 1 else { nope.toggle(); return }     // one has to stay on
            on.remove(i)
        } else {
            on.insert(i)
        }
        Haptic.select()
        Intro.enabled = on
    }
}

/// An intro on its own, full screen, from Indstillinger. Tap to close, or to play it again.
struct IntroPreview: View {
    let intro: Intro
    @Environment(\.dismiss) private var dismiss
    @State private var run = 0
    @State private var hint = false

    var body: some View {
        intro.view
            .id(run)
            .overlay(alignment: .bottom) {
                HStack(spacing: 10) {
                    Button { Haptic.tap(); run += 1 } label: { Label("Igen", systemImage: "arrow.counterclockwise") }
                    Button { dismiss() } label: { Label("Luk", systemImage: "xmark") }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(.gray)
                .environment(\.colorScheme, .dark)
                .padding(.bottom, 24)
                .opacity(hint ? 1 : 0)
            }
            .statusBarHidden()
            .task {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(.easeOut(duration: 0.4)) { hint = true }
            }
    }
}
