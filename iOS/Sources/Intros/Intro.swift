import SwiftUI

/// Shown at launch until the first sync is done. Mostly the icon, now and then one of the rare ones.
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

    /// The ones that turn up now and then instead of the icon.
    static let rare: [Intro] = [.aurora, .schedule, .terminal, .asciiIcon]

    /// The one to show at this launch: the icon, and about 1 in 10 times one of the rare ones.
    static func pick() -> Intro {
        if let s = ProcessInfo.processInfo.environment["VIGGO_INTRO"], let i = Intro(rawValue: s) { return i }
        return Int.random(in: 0..<10) == 0 ? rare.randomElement()! : .icon
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
