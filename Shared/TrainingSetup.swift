import SwiftUI

// The setup for Træning, like the setup on a new iPhone: one question per page, big choices,
// a progress bar, and at the end the program it built and a button that puts it in the schedule.

enum SetupStep: Int, CaseIterable {
    case welcome, body, goal, level, place, schedule, focus, when, build
}

struct TrainingSetup: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var store = TrainingStore.shared
    @ObservedObject var prefs = Prefs.shared
    @State private var p: TrainingProfile
    @State private var step: SetupStep
    @State private var forward = true
    @State private var weight: String
    @State private var height: String
    @State private var age: String
    @State private var built: Bool
    @State private var program: [TrainingSession] = []
    private let editing: Bool
    /// Called when done: the page to show next, or nil when cancelled.
    let done: (TrainingPage?) -> Void

    init(step: SetupStep = .welcome, profile: TrainingProfile? = nil, built: Bool = false, done: @escaping (TrainingPage?) -> Void) {
        let p = profile ?? TrainingProfile()
        _p = State(initialValue: p)
        _step = State(initialValue: step)
        _weight = State(initialValue: p.weight > 0 ? numText(p.weight) : "")
        _height = State(initialValue: p.height > 0 ? numText(p.height) : "")
        _age = State(initialValue: p.age > 0 ? "\(p.age)" : "")
        _built = State(initialValue: built)
        _program = State(initialValue: built ? TrainingBuilder.build(p) : [])
        editing = profile != nil
        self.done = done
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                page(step)
                    .id(step)
                    .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            bottomBar
        }
        .background(Fomo.bg)
    }

    // MARK: Bars

    private var topBar: some View {
        HStack(spacing: 16) {
            Button { go(-1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 14 * Tk.k, weight: .semibold, design: Fomo.design)).frame(width: 28, height: 28)
                    .background(Circle().fill(Fomo.surface2))
            }
            .buttonStyle(PressScale()).opacity(step == .welcome || (step == .build && built) ? 0 : 1)
            .disabled(step == .welcome)
            .help("Tilbage")
            if (SetupStep.body.rawValue...SetupStep.when.rawValue).contains(step.rawValue) {
                let total = Double(SetupStep.when.rawValue)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Fomo.surface2)
                        Capsule().fill(Fomo.accent).frame(width: g.size.width * Double(step.rawValue) / total)
                    }
                }
                .frame(height: 5).frame(maxWidth: 260)
                .frame(maxWidth: .infinity)
            } else {
                Spacer()
            }
            Button(editing ? "Annuller" : "Senere") { done(nil) }
                .buttonStyle(.plain).font(.system(size: 12.5 * Tk.k, design: Fomo.design)).foregroundStyle(Fomo.text2)
                .opacity(step == .build && built ? 0 : 1)
        }
        .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 6)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            switch step {
            case .welcome:
                primary("Kom i gang") { go(1) }
            case .build:
                if built {
                    primary("Læg i skemaet", icon: "calendar.badge.plus") { finish(plan: true) }
                    Button("Gem uden at lægge i skemaet") { finish(plan: false) }
                        .buttonStyle(.plain).font(.system(size: 12.5 * Tk.k, design: Fomo.design)).foregroundStyle(Fomo.accent)
                } else {
                    primary("Fortsæt") {}.opacity(0)
                }
            case .focus:
                primary(p.focus.isEmpty ? "Spring over" : "Fortsæt") { go(1) }
            default:
                primary("Fortsæt") { go(1) }.disabled(!valid).opacity(valid ? 1 : 0.45)
            }
        }
        .padding(.horizontal, 20).padding(.bottom, Tk.phone ? 12 : 30).padding(.top, 8)
        .frame(height: Tk.phone ? 104 : 110, alignment: .top)
    }

    private func primary(_ title: String, icon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.system(size: 14 * Tk.k, weight: .semibold, design: Fomo.design))
            .frame(maxWidth: 320).frame(height: 44 * Tk.k)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Fomo.accent))
            .foregroundStyle(.white)
        }
        .buttonStyle(PressScale(scale: 0.97))
        .keyboardShortcut(.defaultAction)
    }

    private var valid: Bool {
        switch step {
        case .body:
            guard let w = num(weight), (30...250).contains(w) else { return false }
            if !height.isEmpty, num(height).map({ (100...230).contains($0) }) != true { return false }
            if !age.isEmpty, Int(age).map({ (10...99).contains($0) }) != true { return false }
            return true
        case .when: return p.skip.count < 7
        default: return true
        }
    }

    private func go(_ d: Int) {
        if step == .body {
            p.weight = num(weight) ?? 0
            p.height = num(height) ?? 0
            p.age = Int(age) ?? 0
        }
        guard let next = SetupStep(rawValue: step.rawValue + d) else { return }
        forward = d > 0
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) { step = next }
        if next == .build { build() }
    }

    private func build() {
        built = false
        program = TrainingBuilder.build(p)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.1))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { built = true }
        }
    }

    private func finish(plan: Bool) {
        store.apply(profile: p, program: program)
        if plan {
            let now = Date()
            let new = TrainingPlanner.suggest(events: state.events, planned: prefs.planned, custom: prefs.customItems,
                                              now: now, first: store.nextSession, order: store.order, wish: p.wish)
            prefs.planned = prefs.planned.filter { !($0.from == TrainingPlanner.tag && $0.end > now) } + new
        }
        done(plan ? .plan : .program)
    }

    // MARK: Pages

    @ViewBuilder private func page(_ s: SetupStep) -> some View {
        ScrollView {
            VStack(spacing: 22) {
                switch s {
                case .welcome: welcome
                case .body: about
                case .goal:
                    header("target", Fomo.red, "Hvad er dit mål?", "Det bestemmer sæt, gentagelser og pauser.")
                    choices(Goal.allCases, \.goal)
                case .level:
                    header("figure.strengthtraining.traditional", Fomo.accent, "Hvor meget har du trænet?",
                           "Som ny starter du med færre sæt og lærer øvelserne med let vægt.")
                    choices(Level.allCases, \.level)
                case .place:
                    header("mappin.and.ellipse", Fomo.green, "Hvor træner du?", "Viggo+ vælger øvelser, du kan lave der.")
                    choices(Place.allCases, \.place)
                case .schedule: schedule
                case .focus: focus
                case .when: when
                case .build: result
                }
            }
            .frame(maxWidth: 500)
            .padding(.horizontal, Tk.phone ? 20 : 30).padding(.top, 26).padding(.bottom, 20)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }

    private func header(_ icon: String, _ color: Color, _ title: String, _ sub: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 28 * Tk.k, weight: .semibold, design: Fomo.design)).foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom)))
                .shadow(color: color.opacity(0.35), radius: 12, y: 5)
            Text(title).font(.system(size: 26 * Tk.k, weight: .bold, design: Fomo.design)).multilineTextAlignment(.center)
            Text(sub).font(.system(size: 13 * Tk.k, design: Fomo.design)).foregroundStyle(Fomo.text2).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }

    private var welcome: some View {
        VStack(spacing: 26) {
            header("dumbbell.fill", Fomo.accent, "Træning lavet til dig",
                   "Svar på et par spørgsmål, så laver Viggo+ et program og finder tider i dit skema. Det tager et minut.")
            VStack(alignment: .leading, spacing: 20) {
                feature("list.bullet.rectangle", "Et program der passer til dig", "Øvelser, sæt og gentagelser efter dit mål, og efter om du træner i fitness eller hjemme.")
                feature("calendar.badge.clock", "Tider der passer i dit skema", "Viggo+ kender din dag og lægger træningen, hvor der er plads.")
                feature("chart.line.uptrend.xyaxis", "Fremgang du kan se", "Vægten på stangen, din kropsvægt og uger i træk.")
            }
            .padding(.horizontal, 10)
            privacy
        }
    }

    private func feature(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon).font(.system(size: 24 * Tk.k, design: Fomo.design)).foregroundStyle(Fomo.accent).frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14 * Tk.k, weight: .semibold, design: Fomo.design))
                Text(text).font(.system(size: 12.5 * Tk.k, design: Fomo.design)).foregroundStyle(Fomo.text2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var privacy: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill").font(.system(size: 11 * Tk.k, design: Fomo.design)).foregroundStyle(Fomo.text2)
            Text("Det du skriver, bliver på denne \(Tk.device). Viggo+ sender det ikke nogen steder hen.")
                .font(.system(size: 11.5 * Tk.k, design: Fomo.design)).foregroundStyle(Fomo.text2)
        }
    }

    private var about: some View {
        VStack(spacing: 22) {
            header("scalemass.fill", Fomo.warn, "Om dig", "Din vægt bruges til at vise din fremgang over tid.")
            VStack(spacing: 0) {
                field("Vægt", $weight, "kg", "Fx 81")
                Divider().padding(.leading, 16)
                field("Højde", $height, "cm", "Valgfri")
                Divider().padding(.leading, 16)
                field("Alder", $age, "år", "Valgfri")
            }
            .surface()
            privacy
        }
    }

    private func field(_ label: String, _ text: Binding<String>, _ unit: String, _ hint: String) -> some View {
        HStack {
            Text(label).font(.system(size: 14 * Tk.k, design: Fomo.design))
            Spacer()
            TextField(hint, text: text)
                .trKeyboard(decimal: unit != "år")
                .textFieldStyle(.plain).multilineTextAlignment(.trailing)
                .font(.system(size: 17 * Tk.k, weight: .semibold, design: Fomo.design)).monospacedDigit().frame(width: 110)
            Text(unit).font(.system(size: 13 * Tk.k, design: Fomo.design)).foregroundStyle(Fomo.text2).frame(width: 26, alignment: .leading)
        }
        .padding(.horizontal, 16).frame(height: 50)
    }

    private func choices<T: Identifiable & Equatable>(_ all: [T], _ key: WritableKeyPath<TrainingProfile, T>) -> some View where T: SetupOption {
        VStack(spacing: 10) {
            ForEach(all) { o in
                Choice(icon: o.icon, title: o.title, subtitle: o.subtitle, selected: p[keyPath: key] == o) {
                    withAnimation(.viggo) { p[keyPath: key] = o }
                }
            }
        }
    }

    private var schedule: some View {
        VStack(spacing: 22) {
            header("calendar", Fomo.accent, "Hvor tit og hvor længe?", "Tre gange om ugen er et godt sted at starte.")
            section("GANGE OM UGEN") {
                HStack(spacing: 10) {
                    tile("2", "Hele kroppen", p.days == 2) { p.days = 2 }
                    tile("3", "Hele kroppen", p.days == 3) { p.days = 3 }
                    tile("4", "Over- og underkrop", p.days == 4) { p.days = 4 }
                }
            }
            section("TID HVER GANG") {
                HStack(spacing: 10) {
                    ForEach([30, 45, 60], id: \.self) { m in
                        tile("\(m)", "min · \(TrainingBuilder.count(minutes: m)) øvelser", p.minutes == m) { p.minutes = m }
                    }
                }
            }
            let total = p.days * p.minutes
            Label("Cirka \(total / 60 > 0 ? "\(total / 60) t " : "")\(total % 60 > 0 ? "\(total % 60) min " : "")om ugen", systemImage: "clock")
                .font(.system(size: 12.5 * Tk.k, weight: .medium, design: Fomo.design)).foregroundStyle(Fomo.text2)
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 10.5 * Tk.k, weight: .semibold, design: Fomo.design)).foregroundStyle(Fomo.text2).padding(.leading, 4)
            c()
        }
    }

    private func tile(_ big: String, _ small: String, _ selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button { withAnimation(.viggo) { action() } } label: {
            VStack(spacing: 4) {
                Text(big).font(.system(size: 28 * Tk.k, weight: .bold, design: Fomo.design)).monospacedDigit()
                Text(small).font(.system(size: 11 * Tk.k, design: Fomo.design)).multilineTextAlignment(.center)
                    .foregroundStyle(selected ? .white.opacity(0.9) : Fomo.text2)
            }
            .frame(maxWidth: .infinity).frame(height: 86)
            .foregroundStyle(selected ? .white : .primary)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected ? Fomo.accent : Fomo.surface))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale(scale: 0.96))
    }

    private var focus: some View {
        VStack(spacing: 22) {
            header("scope", Fomo.red, "Vil du fokusere på noget?", "Vælg op til to. Så får de lidt ekstra hver gang. Du kan også springe over.")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(Area.allCases) { a in
                    let on = p.focus.contains(a)
                    Button {
                        withAnimation(.viggo) {
                            if on { p.focus.removeAll { $0 == a } }
                            else if p.focus.count < 2 { p.focus.append(a) }
                            else { p.focus = [p.focus[1], a] }
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: a.icon).font(.system(size: 22 * Tk.k, design: Fomo.design))
                            Text(a.title).font(.system(size: 12.5 * Tk.k, weight: .medium, design: Fomo.design))
                        }
                        .frame(maxWidth: .infinity).frame(height: 86)
                        .foregroundStyle(on ? .white : .primary)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? Fomo.accent : Fomo.surface))
                        .overlay(alignment: .topTrailing) {
                            if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(.white).padding(8) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScale(scale: 0.96))
                }
            }
        }
    }

    private var when: some View {
        VStack(spacing: 22) {
            header("clock.fill", Fomo.green, "Hvornår passer det dig?", "Viggo+ leder efter en ledig time på det tidspunkt i dit skema.")
            choices(TimeOfDay.allCases, \.when)
            section("DAGE DU KAN TRÆNE") {
                HStack(spacing: Tk.phone ? 6 : 8) {
                    ForEach(Array(["M", "T", "O", "T", "F", "L", "S"].enumerated()), id: \.offset) { i, d in
                        let wd = i + 1, on = !p.skip.contains(wd)
                        Button {
                            withAnimation(.viggo) { if on { p.skip.append(wd) } else { p.skip.removeAll { $0 == wd } } }
                        } label: {
                            Text(d).font(.system(size: 14 * Tk.k, weight: .semibold, design: Fomo.design)).frame(width: Tk.phone ? 40 : 44, height: Tk.phone ? 40 : 44)
                                .background(Circle().fill(on ? Fomo.accent : Fomo.surface))
                                .foregroundStyle(on ? .white : Fomo.text2)
                        }
                        .buttonStyle(PressScale(scale: 0.92))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            Text(p.place == .gym ? "Viggo+ lægger kun træning på dage, hvor du er på skolen." : "Hjemmetræning kan også ligge i weekender, hvor du er hjemme.")
                .font(.system(size: 11.5 * Tk.k, design: Fomo.design)).foregroundStyle(Fomo.text2)
        }
    }

    @ViewBuilder private var result: some View {
        if !built {
            VStack(spacing: 26) {
                ProgressView().controlSize(.large).padding(.top, 60)
                Text("Laver dit program").font(.system(size: 22 * Tk.k, weight: .bold, design: Fomo.design))
                BuildChecklist()
            }
        } else {
            VStack(spacing: 18) {
                header("checkmark.seal.fill", Fomo.green, "Dit program er klar", p.summary)
                ForEach(program) { s in SessionPreview(session: s) }
                if editing {
                    Label("Dit gamle program bliver skiftet ud. Din historik bliver.", systemImage: "info.circle")
                        .font(.system(size: 11.5 * Tk.k, design: Fomo.design)).foregroundStyle(Fomo.text2)
                }
                Text("Du kan bytte øvelser og ændre sæt bagefter under Program.")
                    .font(.system(size: 11.5 * Tk.k, design: Fomo.design)).foregroundStyle(Fomo.text2)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }
}

/// The three lines that tick off one by one while the program is built.
private struct BuildChecklist: View {
    @State private var done = 0
    private let lines = ["Vælger øvelser", "Sætter sæt, gentagelser og pauser", "Gør klar til at finde tider i dit skema"]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(lines.indices, id: \.self) { i in
                HStack(spacing: 10) {
                    Image(systemName: i < done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(i < done ? Fomo.green : Color.secondary.opacity(0.4))
                        .contentTransition(.symbolEffect(.replace))
                    Text(lines[i]).font(.system(size: 13 * Tk.k, design: Fomo.design)).foregroundStyle(i < done ? .primary : Fomo.text2)
                }
            }
        }
        .task {
            for i in 1...lines.count {
                try? await Task.sleep(for: .seconds(0.6))
                withAnimation(.viggo) { done = i }
            }
        }
    }
}

/// One workout of a program: letter, name and small photos of the exercises.
struct SessionPreview: View {
    let session: TrainingSession
    var body: some View {
        HStack(spacing: 14) {
            Text(session.id).font(.system(size: 17 * Tk.k, weight: .bold, design: Fomo.design)).frame(width: 38, height: 38)
                .background(Circle().fill(Fomo.green.opacity(0.18))).foregroundStyle(Fomo.green)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Træning \(session.id)").font(.system(size: 13.5 * Tk.k, weight: .semibold, design: Fomo.design))
                    Text("\(session.name) · \(session.items.count) øvelser").font(.system(size: 12 * Tk.k, design: Fomo.design))
                        .foregroundStyle(Fomo.text2).lineLimit(1)
                }
                HStack(spacing: 5) {
                    ForEach(session.items) { i in
                        if let ex = TrainingProgram.exercise(i.exercise) {
                            ExerciseThumb(ex: ex, width: Tk.phone ? 38 : 44, height: Tk.phone ? 28 : 32).help(ex.name)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .surface()
    }
}

/// Anything the setup lets you pick from a list of cards.
protocol SetupOption {
    var title: String { get }
    var subtitle: String { get }
    var icon: String { get }
}
extension Goal: SetupOption {}
extension Level: SetupOption {}
extension Place: SetupOption {}
extension TimeOfDay: SetupOption {}

private struct Choice: View {
    let icon: String
    let title: String
    let subtitle: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 17 * Tk.k, design: Fomo.design)).frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Fomo.accent : Fomo.accent.opacity(0.12)))
                    .foregroundStyle(selected ? .white : Fomo.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14 * Tk.k, weight: .semibold, design: Fomo.design))
                    Text(subtitle).font(.system(size: 12 * Tk.k, design: Fomo.design)).foregroundStyle(Fomo.text2)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 20 * Tk.k, design: Fomo.design))
                    .foregroundStyle(selected ? Fomo.accent : Color.secondary.opacity(0.35))
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Fomo.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? Fomo.accent : .clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale(scale: 0.98))
    }
}
