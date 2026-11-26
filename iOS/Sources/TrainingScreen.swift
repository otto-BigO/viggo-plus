import Charts
import SwiftUI
import UserNotifications
#if os(iOS)
import UIKit
#endif

// Træning on the iPhone: the same four pages as the Mac window (Plan, Træn, Program, Fremgang)
// laid out for one hand at the gym. The data, the planner and the setup are shared with the Mac
// (Shared/Training.swift, Shared/TrainingSetup.swift, Shared/TrainingKit.swift).

struct TrainingScreen: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var store = TrainingStore.shared
    @State private var page: TrainingPage
    @State private var setup: Bool
    /// VIGGO_TRAINING_SETUP=<n> opens the setup on that page (pictures and tests).
    private let setupStep = ProcessInfo.processInfo.environment["VIGGO_TRAINING_SETUP"].flatMap(Int.init).flatMap(SetupStep.init) ?? .welcome

    init() {
        let env = ProcessInfo.processInfo.environment
        let start = env["VIGGO_TRAINING_PAGE"].flatMap { p in TrainingPage.allCases.first { $0.rawValue.lowercased() == p.lowercased() } }
        _page = State(initialValue: start ?? (TrainingStore.shared.active != nil ? .workout : .plan))
        _setup = State(initialValue: env["VIGGO_TRAINING_SETUP"] != nil || (start == nil && TrainingStore.shared.profile == nil))
    }

    var body: some View {
        NavigationStack {
            Group {
                if setup {
                    TrainingSetup(step: setupStep, profile: store.profile, built: setupStep == .build) { next in
                        withAnimation(.viggo) {
                            if let next { page = next }
                            setup = false
                        }
                    }
                    .transition(.opacity)
                } else {
                    main.transition(.opacity)
                }
            }
            .background(Fomo.bg)
            .navigationTitle("Træning")
            .trHideNavBar(setup)
        }
        .onReceive(NotificationCenter.default.publisher(for: .viggoTabAgain)) { n in
            if (n.object as? Int) == PhoneTabs.training, !setup, store.active != nil { withAnimation(.viggo) { page = .workout } }
        }
        .onChange(of: store.active != nil) { _, on in trKeepAwake(on) }
        .onAppear { trKeepAwake(store.active != nil) }
    }

    private var main: some View {
        VStack(spacing: 0) {
            Picker("Side", selection: $page.animation(.viggo)) {
                ForEach(TrainingPage.allCases, id: \.self) { p in Text(p.rawValue).tag(p) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 16).padding(.bottom, 8)
            if let a = store.active, page != .workout {
                RunningBanner(active: a) { withAnimation(.viggo) { page = .workout } }
                    .padding(.horizontal, 16).padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Group {
                switch page {
                case .plan: PhonePlanPage { letter in store.start(letter); withAnimation(.viggo) { page = .workout } }
                case .workout: PhoneWorkoutPage()
                case .program: PhoneProgramPage { withAnimation(.viggo) { setup = true } }
                case .progress: PhoneProgressPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The phone's tab numbers, so other screens can point at Træning.
enum PhoneTabs {
    static let training = 4
}

/// "Træning A i gang · 12:04" on the other pages while a workout runs.
private struct RunningBanner: View {
    @ObservedObject var store = TrainingStore.shared
    let active: ActiveWorkout
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Circle().fill(Fomo.green).frame(width: 8, height: 8)
                Text("Træning \(active.session) i gang").font(.subheadline.weight(.semibold))
                TimelineView(.periodic(from: .now, by: 1)) { t in
                    Text(clock(t.date.timeIntervalSince(active.started))).font(.subheadline).monospacedDigit().foregroundStyle(Fomo.text2)
                }
                Spacer()
                Text("Fortsæt").font(.subheadline.weight(.semibold)).foregroundStyle(Fomo.green)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Fomo.green)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .surface(14, fill: Fomo.green.opacity(0.14))
            .foregroundStyle(.primary)
        }
        .buttonStyle(PressScale(scale: 0.98))
    }
}

private func clock(_ t: TimeInterval) -> String {
    let s = max(0, Int(t))
    return String(format: "%d:%02d", s / 60, s % 60)
}

/// The big headline at the top of each page, in the I dag style.
private func pageTitle(_ title: String, _ sub: String? = nil) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.title2.weight(.bold))
        if let sub { Text(sub).font(.subheadline).foregroundStyle(Fomo.text2).fixedSize(horizontal: false, vertical: true) }
    }
}

private func letterBadge(_ letter: String, filled: Bool, size: CGFloat = 40) -> some View {
    Text(letter).font(.system(size: size * 0.45, weight: .bold)).frame(width: size, height: size)
        .background(Circle().fill(filled ? Fomo.green : Fomo.green.opacity(0.18)))
        .foregroundStyle(filled ? Fomo.onGreen : Fomo.green)
}

// MARK: - Plan

private struct PhonePlanPage: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var store = TrainingStore.shared
    let start: (String) -> Void

    private var items: [PlannedItem] {
        let now = Date()
        return prefs.planned.filter { $0.from == TrainingPlanner.tag }
            .filter { $0.end > DateUtil.startOfDay(now) }.sorted { $0.start < $1.start }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                stats
                pageTitle("Din træningsuge",
                          "Viggo+ finder ledige tider på \(store.wish.minutes) min i dit skema, 20 min efter mad, og lægger \(store.wish.count) træninger ind med en hviledag imellem.")
                Toggle(isOn: $prefs.trainingInSchedule.animation(.viggo)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vis i skema").font(.body.weight(.semibold))
                        Text(prefs.trainingInSchedule
                             ? "Træningerne står i I dag, Uge og på widgets."
                             : "Træningerne er kun her. I dag, Uge og widgets viser dem ikke.")
                            .font(.footnote).foregroundStyle(Fomo.text2)
                    }
                }
                .tint(Fomo.green)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .surface()
                Button { findTimes() } label: {
                    Label(items.isEmpty ? "Find tider de næste 7 dage" : "Find nye tider", systemImage: "wand.and.stars")
                        .font(.body.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Fomo.accent)).foregroundStyle(.white)
                }
                .buttonStyle(PressScale(scale: 0.98))
                if items.isEmpty {
                    Text("Ingen træning planlagt endnu.").font(.subheadline).foregroundStyle(Fomo.text2).padding(.top, 12)
                        .frame(maxWidth: .infinity)
                }
                ForEach(items) { item in card(item) }
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 28)
        }
    }

    private var stats: some View {
        HStack(spacing: 8) {
            stat("checkmark.circle.fill", "\(store.thisWeek()) af \(store.wish.count)", "denne uge", Fomo.green)
            stat("flame.fill", "\(store.weeksInRow())", store.weeksInRow() == 1 ? "uge i træk" : "uger i træk", Fomo.warn)
            stat("figure.strengthtraining.traditional", store.nextSession, "næste træning", Fomo.accent)
        }
    }

    private func stat(_ icon: String, _ big: String, _ small: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(c).frame(height: 18)
            Text(big).font(.title3.weight(.bold)).monospacedDigit()
            Text(small).font(.caption).foregroundStyle(Fomo.text2).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .surface()
    }

    private func findTimes() {
        let now = Date()
        let new = TrainingPlanner.suggest(events: state.events, planned: prefs.planned, custom: prefs.customItems,
                                          now: now, first: store.nextSession, order: store.order, wish: store.wish)
        Haptic.success()
        withAnimation(.viggo) {
            prefs.planned = prefs.planned.filter { !($0.from == TrainingPlanner.tag && $0.end > now) } + new
        }
    }

    private func card(_ item: PlannedItem) -> some View {
        let letter = TrainingPlanner.letter(item)
        let today = DateUtil.cal.isDateInToday(item.start)
        let past = item.end < Date()
        let clash = past ? nil : TrainingPlanner.conflict(item, events: state.events, custom: prefs.customItems)
        let done = store.logs.contains { DateUtil.cal.isDate($0.started, inSameDayAs: item.start) && $0.session == letter }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                letterBadge(letter, filled: done)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.title).font(.headline)
                        if today { Text("I DAG").font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Fomo.accent)).foregroundStyle(.white) }
                    }
                    Text("\(cap(longDay.string(from: item.start))) · \(DateUtil.hm(item.start))-\(DateUtil.hm(item.end))")
                        .font(.subheadline).monospacedDigit().foregroundStyle(Fomo.text2)
                    Text(store.exercises(letter).map(\.name).joined(separator: ", "))
                        .font(.footnote).foregroundStyle(.tertiary).lineLimit(2)
                    if done { Label("Klaret", systemImage: "checkmark").font(.footnote.weight(.semibold)).foregroundStyle(Fomo.green) }
                    if let clash {
                        Label("Overlapper nu med \(clash)", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.medium)).foregroundStyle(Fomo.red)
                    }
                }
                Spacer(minLength: 0)
                if !past { menu(item) }
            }
            if today && !done && !past {
                Button { Haptic.firm(); start(letter) } label: {
                    Text(store.active != nil ? "Fortsæt træningen" : "Start træning \(letter)").font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Fomo.green)).foregroundStyle(Fomo.onGreen)
                }
                .buttonStyle(PressScale(scale: 0.98))
            }
        }
        .padding(16)
        .surface()
        .opacity(past && !done ? 0.5 : 1)
    }

    private func menu(_ item: PlannedItem) -> some View {
        Menu {
            Menu("Flyt til") {
                let opts = TrainingPlanner.options(events: state.events, planned: prefs.planned, custom: prefs.customItems,
                                                   now: Date(), ignoring: item.id, wish: store.wish)
                if opts.isEmpty { Text("Ingen andre ledige tider") }
                ForEach(opts, id: \.self) { o in
                    Button("\(cap(shortDay.string(from: o.start))) kl. \(DateUtil.hm(o.start))") { move(item, to: o) }
                }
            }
            Button(role: .destructive) { withAnimation(.viggo) { prefs.planned.removeAll { $0.id == item.id } } } label: {
                Label("Fjern fra skemaet", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis").font(.body.weight(.semibold)).foregroundStyle(Fomo.text2)
                .frame(width: 36, height: 36).contentShape(Rectangle())
        }
    }

    private func move(_ item: PlannedItem, to slot: TrainingPlanner.Slot) {
        guard let i = prefs.planned.firstIndex(where: { $0.id == item.id }) else { return }
        Haptic.select()
        withAnimation(.viggo) {
            prefs.planned[i].start = slot.start
            prefs.planned[i].end = slot.end
        }
    }
}

// MARK: - Workout

private struct PhoneWorkoutPage: View {
    @ObservedObject var store = TrainingStore.shared
    @State private var summary: WorkoutLog?
    @State private var confirmCancel = false
    @State private var detail: Exercise?
    @FocusState private var field: SetField?

    var body: some View {
        Group {
            if let a = store.active { active(a) } else { picker }
        }
        .sheet(item: $summary) { log in PhoneSummary(log: log) { summary = nil } }
        .sheet(item: $detail) { ex in ExerciseSheet(ex: ex) }
        // Tapping a kg or reps box marks the number, so typing 20 replaces the 0 instead of making 200.
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { n in
            guard let tf = n.object as? UITextField else { return }
            DispatchQueue.main.async { tf.selectAll(nil) }
        }
    }

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                pageTitle("Vælg træning", "Kør dem i rækkefølgen \(store.order.joined(separator: ", ")). Næste gang er det træning \(store.nextSession). Tryk på et billede for at se øvelsen.")
                ForEach(store.order, id: \.self) { s in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            letterBadge(s, filled: s == store.nextSession)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("Træning \(s)").font(.headline)
                                    if s == store.nextSession { Text("NÆSTE").font(.caption2.weight(.bold)).foregroundStyle(Fomo.green) }
                                }
                                Text(store.session(s)?.name ?? "").font(.subheadline).foregroundStyle(Fomo.text2)
                            }
                            Spacer()
                        }
                        ForEach(store.exercises(s)) { e in
                            HStack(spacing: 12) {
                                Button { detail = e } label: { PlayThumb(ex: e, width: 64, height: 44) }.buttonStyle(PressScale())
                                Text(e.name).font(.subheadline)
                                Spacer()
                                Text(e.target).font(.footnote).monospacedDigit().foregroundStyle(Fomo.text2)
                            }
                        }
                        Button { Haptic.firm(); withAnimation(.viggo) { store.start(s) } } label: {
                            Text("Start træning \(s)").font(.body.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 44)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(s == store.nextSession ? Fomo.accent : Fomo.surface2))
                                .foregroundStyle(s == store.nextSession ? .white : .primary)
                        }
                        .buttonStyle(PressScale(scale: 0.98))
                    }
                    .padding(16)
                    .surface()
                }
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 28)
        }
    }

    private func active(_ a: ActiveWorkout) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Træning \(a.session)").font(.title2.weight(.bold))
                        HStack(spacing: 6) {
                            Text(store.session(a.session)?.name ?? "")
                            TimelineView(.periodic(from: .now, by: 1)) { t in
                                Text("· " + clock(t.date.timeIntervalSince(a.started))).monospacedDigit()
                            }
                        }
                        .font(.subheadline).foregroundStyle(Fomo.text2)
                    }
                    Spacer()
                    Button("Annuller") { confirmCancel = true }.font(.subheadline).foregroundStyle(Fomo.text2)
                }
                ForEach(a.exercises.indices, id: \.self) { i in
                    PhoneExerciseCard(index: i, field: $field) { detail = $0 }
                }
                Button { finish() } label: {
                    Label("Afslut træningen", systemImage: "flag.checkered").font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Fomo.green)).foregroundStyle(Fomo.onGreen)
                }
                .buttonStyle(PressScale(scale: 0.98))
                .padding(.top, 4)
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, a.restEnds == nil ? 28 : 110)
        }
        .scrollDismissesKeyboard(.interactively)
        .overlay(alignment: .bottom) { PhoneRestBar() }
        .confirmationDialog("Annuller træningen?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Annuller træningen", role: .destructive) { RestAlarm.cancel(); withAnimation(.viggo) { store.cancel() } }
            Button("Fortsæt", role: .cancel) {}
        } message: { Text("Sættene bliver ikke gemt.") }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Færdig") { field = nil }.fontWeight(.semibold)
            }
        }
        .task(id: a.restEnds) {
            guard let end = a.restEnds, end > Date() else { RestAlarm.cancel(); return }
            RestAlarm.schedule(at: end, next: nextName(a))
            try? await Task.sleep(for: .seconds(end.timeIntervalSinceNow))
            guard !Task.isCancelled, store.active?.restEnds == end else { return }
            RestAlarm.cancel()
            Haptic.success()
            withAnimation(.viggo) { store.active?.restEnds = nil }
        }
    }

    /// The exercise with the next set that is not done, for the rest notification.
    private func nextName(_ a: ActiveWorkout) -> String? {
        a.exercises.first { $0.sets.contains { !$0.done } }.flatMap { TrainingProgram.exercise($0.exercise)?.name }
    }

    private func finish() {
        field = nil
        RestAlarm.cancel()
        Haptic.success()
        summary = store.finish()
    }
}

/// Which box has the keyboard: exercise, set, and kg or reps.
struct SetField: Hashable {
    let exercise: Int
    let set: Int
    let kg: Bool
}

/// The rest timer as a notification, so the phone buzzes when the pause is over even when it is
/// in your pocket with the screen off.
enum RestAlarm {
    static let id = "viggo.training.rest"
    static func schedule(at end: Date, next: String?) {
        let c = UNMutableNotificationContent()
        c.title = "Pausen er slut"
        c.body = next.map { "Næste sæt: \($0)" } ?? "Klar til næste sæt"
        c.sound = .default
        let t = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: t))
    }
    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}

private struct PhoneRestBar: View {
    @ObservedObject var store = TrainingStore.shared

    var body: some View {
        if let end = store.active?.restEnds {
            TimelineView(.periodic(from: .now, by: 0.5)) { t in
                let left = max(0, Int(end.timeIntervalSince(t.date).rounded(.up)))
                HStack(spacing: 12) {
                    Image(systemName: "timer").font(.title3).foregroundStyle(Fomo.accent)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Pause").font(.caption.weight(.semibold)).foregroundStyle(Fomo.text2)
                        Text(String(format: "%d:%02d", left / 60, left % 60)).font(.title.weight(.bold)).monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                    }
                    Spacer()
                    Button("+15 sek") { Haptic.tap(); store.active?.restEnds = end.addingTimeInterval(15) }
                        .font(.subheadline.weight(.semibold)).padding(.horizontal, 12).frame(height: 38)
                        .background(Capsule().fill(Fomo.surface))
                    Button("Spring over") { Haptic.tap(); RestAlarm.cancel(); withAnimation(.viggo) { store.active?.restEnds = nil } }
                        .font(.subheadline.weight(.semibold)).padding(.horizontal, 12).frame(height: 38)
                        .background(Capsule().fill(Fomo.accent)).foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Fomo.surface2)
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4))
                .padding(.horizontal, 12).padding(.bottom, 10)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

private struct PhoneExerciseCard: View {
    let index: Int
    var field: FocusState<SetField?>.Binding
    let showDetail: (Exercise) -> Void
    @ObservedObject var store = TrainingStore.shared
    @State private var showHow: Bool

    /// The how-to opens by itself the first time you do an exercise.
    init(index: Int, field: FocusState<SetField?>.Binding, showDetail: @escaping (Exercise) -> Void) {
        self.index = index
        self.field = field
        self.showDetail = showDetail
        let id = TrainingStore.shared.active?.exercises[safe: index]?.exercise ?? ""
        _showHow = State(initialValue: TrainingStore.shared.last(id) == nil)
    }

    var body: some View {
        if let a = store.active, let log = a.exercises[safe: index], let ex = store.spec(log.exercise, session: a.session) {
            VStack(alignment: .leading, spacing: 12) {
                header(ex)
                if showHow { how(ex).transition(.opacity) }
                sets(ex, log)
                Button { Haptic.tap(); withAnimation(.viggo) { store.addSet(exercise: index) } } label: {
                    Label("Tilføj sæt", systemImage: "plus").font(.subheadline.weight(.medium)).foregroundStyle(Fomo.accent)
                        .frame(maxWidth: .infinity).frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Fomo.accent.opacity(0.1)))
                }
                .buttonStyle(PressScale(scale: 0.98))
            }
            .padding(14)
            .surface()
        }
    }

    private func header(_ ex: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button { showDetail(ex) } label: { PlayThumb(ex: ex, width: 64, height: 46) }.buttonStyle(PressScale())
                VStack(alignment: .leading, spacing: 2) {
                    Text(ex.name).font(.headline)
                    Text("\(ex.muscles) · \(ex.target)").font(.footnote).foregroundStyle(Fomo.text2)
                }
                Spacer(minLength: 0)
                Button { withAnimation(.viggo) { showHow.toggle() } } label: {
                    Image(systemName: showHow ? "chevron.up.circle.fill" : "questionmark.circle")
                        .font(.title3).foregroundStyle(Fomo.accent).frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sådan gør du")
            }
            if let kg = store.suggestedKg(ex), let last = store.last(ex.id)?.sets.map(\.kg).max(), kg > last {
                Label("Prøv \(kgText(kg)) kg i dag. Du klarede alle sæt sidst.", systemImage: "arrow.up.circle.fill")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Fomo.green)
            } else if store.last(ex.id) == nil && !ex.bodyweight {
                Label("Første gang: start let og lær bevægelsen.", systemImage: "leaf.fill")
                    .font(.footnote.weight(.medium)).foregroundStyle(Fomo.warn)
            }
        }
    }

    private func how(_ ex: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ExerciseMotion(ex: ex).frame(maxWidth: .infinity).aspectRatio(3 / 2, contentMode: .fit)
            Cues(ex: ex)
            HStack {
                if !ex.home.isEmpty { Text("Uden fitness: \(ex.home)").font(.footnote).foregroundStyle(Fomo.text2) }
                Spacer()
                if let u = ex.videoURL {
                    Link(destination: u) { Label("Video", systemImage: "play.rectangle.fill").font(.footnote.weight(.medium)) }
                }
            }
        }
        .padding(12)
        .surface(Fomo.radiusSmall, fill: Fomo.surface2)
    }

    private func sets(_ ex: Exercise, _ log: ExerciseLog) -> some View {
        let prev = store.last(ex.id)?.sets
        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text("SÆT").frame(width: 30, alignment: .leading)
                Text("SIDST").frame(maxWidth: .infinity, alignment: .leading)
                Text(ex.bodyweight ? "" : "KG").frame(width: 66)
                Text(ex.unit == .seconds ? "SEK" : "REPS").frame(width: 58)
                Text("").frame(width: 40)
            }
            .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            ForEach(log.sets.indices, id: \.self) { i in
                let s = log.sets[i]
                HStack(spacing: 8) {
                    Text("\(i + 1)").font(.subheadline.weight(.semibold)).frame(width: 30, alignment: .leading)
                    Text(prev.flatMap { $0.indices.contains(i) ? setText($0[i], ex) : nil } ?? "-")
                        .font(.footnote).monospacedDigit().foregroundStyle(Fomo.text2).lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if ex.bodyweight {
                        Text("Krop").font(.footnote).foregroundStyle(.tertiary).frame(width: 66)
                    } else {
                        box(TextField("0", value: kg(i), format: .number).trKeyboard(decimal: true)
                            .focused(field, equals: SetField(exercise: index, set: i, kg: true)), width: 66)
                    }
                    box(TextField("0", value: reps(i), format: .number).trKeyboard(decimal: false)
                        .focused(field, equals: SetField(exercise: index, set: i, kg: false)), width: 58)
                    Button {
                        field.wrappedValue = nil
                        if s.done { Haptic.tap() } else { Haptic.success() }
                        withAnimation(.viggo) { store.toggle(exercise: index, set: i) }
                    } label: {
                        Image(systemName: "checkmark").font(.body.weight(.bold))
                            .frame(width: 40, height: 36)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(s.done ? Fomo.green : Fomo.surface2))
                            .foregroundStyle(s.done ? Fomo.onGreen : Fomo.text2)
                            .symbolEffect(.bounce, value: s.done)
                    }
                    .buttonStyle(PressScale(scale: 0.9))
                    .accessibilityLabel(s.done ? "Fortryd sæt \(i + 1)" : "Sæt \(i + 1) klaret")
                }
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 8).fill(s.done ? Fomo.green.opacity(0.1) : .clear).padding(.horizontal, -6))
            }
        }
    }

    private func box<V: View>(_ v: V, width: CGFloat) -> some View {
        v.font(.body.weight(.semibold)).monospacedDigit().multilineTextAlignment(.center)
            .frame(width: width, height: 36)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Fomo.surface2))
    }

    private func kg(_ i: Int) -> Binding<Double> {
        Binding(get: { store.active?.exercises[safe: index]?.sets[safe: i]?.kg ?? 0 },
                set: { store.active?.exercises[index].sets[i].kg = max(0, $0) })
    }

    private func reps(_ i: Int) -> Binding<Int> {
        Binding(get: { store.active?.exercises[safe: index]?.sets[safe: i]?.reps ?? 0 },
                set: { store.active?.exercises[index].sets[i].reps = max(0, $0) })
    }
}

/// The numbered steps of an exercise.
private struct Cues: View {
    let ex: Exercise
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(ex.cues.enumerated()), id: \.offset) { i, c in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(i + 1)").font(.footnote.weight(.bold)).foregroundStyle(Fomo.accent).frame(width: 16)
                    Text(c).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A photo with a small play mark: tap it to see the exercise moving.
private struct PlayThumb: View {
    let ex: Exercise
    var width: CGFloat
    var height: CGFloat
    var body: some View {
        ExerciseThumb(ex: ex, width: width, height: height)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "play.fill").font(.system(size: 7, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 17, height: 17).background(Circle().fill(.black.opacity(0.6))).padding(4)
            }
            .accessibilityLabel("Se hvordan du laver \(ex.name.lowercased())")
    }
}

/// The exercise big, as a sheet: moving photo, the steps, what to do at home and a video link.
private struct ExerciseSheet: View {
    let ex: Exercise
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ExerciseMotion(ex: ex).frame(maxWidth: .infinity).aspectRatio(3 / 2, contentMode: .fit)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ex.name).font(.title2.weight(.bold))
                        Text(ex.muscles).font(.subheadline).foregroundStyle(Fomo.text2)
                    }
                    Cues(ex: ex)
                    if !ex.home.isEmpty {
                        Label("Uden fitness: \(ex.home)", systemImage: "house.fill").font(.subheadline).foregroundStyle(Fomo.text2)
                    }
                    if let u = ex.videoURL {
                        Link(destination: u) {
                            Label("Se video", systemImage: "play.rectangle.fill").font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity).frame(height: 46)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Fomo.surface2))
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .background(Fomo.bg)
            .trInlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Luk") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}

private struct PhoneSummary: View {
    let log: WorkoutLog
    let close: () -> Void
    @ObservedObject var store = TrainingStore.shared

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundStyle(Fomo.green)
                .symbolEffect(.bounce, options: .nonRepeating)
                .padding(.top, 28)
            Text("Træning \(log.session) klaret").font(.title2.weight(.bold))
            HStack(spacing: 30) {
                big("\(Int(log.finished.timeIntervalSince(log.started) / 60))", "min")
                big("\(log.doneSets)", "sæt")
                big(kgText(log.volume.rounded()), "kg løftet")
            }
            let recs = store.records(in: log).compactMap { TrainingProgram.exercise($0) }
            if !recs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(recs) { e in
                        Label("Ny rekord: \(e.name)", systemImage: "trophy.fill").font(.subheadline.weight(.medium)).foregroundStyle(Fomo.warn)
                    }
                }
            }
            Spacer(minLength: 0)
            Button(action: close) {
                Text("Luk").font(.body.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Fomo.accent)).foregroundStyle(.white)
            }
            .buttonStyle(PressScale(scale: 0.98))
        }
        .padding(.horizontal, 20).padding(.bottom, 16)
        // As tall as what it shows: the seal, the numbers, any records and Luk.
        .presentationDetents([.height(340 + CGFloat(store.records(in: log).count) * 26)])
        .interactiveDismissDisabled()
    }

    private func big(_ n: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(n).font(.title.weight(.bold)).monospacedDigit()
            Text(label).font(.footnote).foregroundStyle(Fomo.text2)
        }
    }
}

// MARK: - Program

/// What the exercise sheet was opened for: adding to a workout, or swapping one exercise.
private struct PhoneLibraryTarget: Identifiable {
    let id = UUID()
    let session: String
    var replacing: UUID? = nil
    var area: Area? = nil
}

/// One exercise in the program whose sets and reps are being changed.
private struct EditTarget: Identifiable {
    let id: UUID
    let session: String
    let ex: Exercise
}

private struct PhoneProgramPage: View {
    @ObservedObject var store = TrainingStore.shared
    let editSetup: () -> Void
    @State private var library: PhoneLibraryTarget?
    @State private var editing: EditTarget?
    @State private var detail: Exercise?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                pageTitle("Dit program", (store.profile.map { $0.summary + "." } ?? "Standardprogrammet. Lav din opsætning for at få et program til dig.")
                          + " Tryk på et billede for at se øvelsen.")
                Button(action: editSetup) {
                    Label(store.profile == nil ? "Lav opsætning" : "Ret opsætning", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold)).padding(.horizontal, 14).frame(height: 36)
                        .background(Capsule().fill(Fomo.surface2)).foregroundStyle(.primary)
                }
                .buttonStyle(PressScale())
                ForEach(store.program) { s in sessionCard(s) }
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 28)
        }
        .sheet(item: $library) { t in
            PhoneExerciseLibrary(target: t, inSession: Set(store.session(t.session)?.items.map(\.exercise) ?? [])) { id in
                pick(id, for: t)
                library = nil
            }
        }
        .sheet(item: $editing) { t in PhoneItemEditor(session: t.session, item: t.id, ex: t.ex) }
        .sheet(item: $detail) { ex in ExerciseSheet(ex: ex) }
    }

    private func minutes(_ s: TrainingSession) -> Int {
        let secs = s.items.reduce(0) { $0 + $1.sets * (45 + $1.rest) }
        return Int((Double(secs) / 60 / 5).rounded()) * 5 + 10
    }

    private func sessionCard(_ s: TrainingSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                letterBadge(s.id, filled: false, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Træning \(s.id)").font(.headline)
                    Text("\(s.name) · \(s.items.count) øvelser · ca. \(minutes(s)) min").font(.footnote).foregroundStyle(Fomo.text2)
                }
                Spacer()
            }
            VStack(spacing: 0) {
                ForEach(Array(s.items.enumerated()), id: \.element.id) { i, item in
                    if i > 0 { Divider().padding(.leading, 84) }
                    row(s, i, item)
                }
            }
            Button { library = PhoneLibraryTarget(session: s.id) } label: {
                Label("Tilføj øvelse", systemImage: "plus").font(.subheadline.weight(.medium)).foregroundStyle(Fomo.accent)
                    .frame(maxWidth: .infinity).frame(height: 38)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Fomo.accent.opacity(0.1)))
            }
            .buttonStyle(PressScale(scale: 0.98))
        }
        .padding(14)
        .surface()
    }

    @ViewBuilder private func row(_ s: TrainingSession, _ i: Int, _ item: PlanItem) -> some View {
        if let ex = TrainingProgram.exercise(item.exercise) {
            HStack(spacing: 12) {
                Button { detail = ex } label: { PlayThumb(ex: ex, width: 72, height: 50) }.buttonStyle(PressScale())
                VStack(alignment: .leading, spacing: 4) {
                    Text(ex.name).font(.subheadline.weight(.medium)).lineLimit(2)
                    Button { editing = EditTarget(id: item.id, session: s.id, ex: ex) } label: {
                        Text(targetText(ex, item)).font(.footnote.weight(.medium)).monospacedDigit()
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Capsule().fill(Fomo.surface2)).foregroundStyle(.primary)
                    }
                    .buttonStyle(PressScale())
                }
                Spacer(minLength: 0)
                Menu {
                    Button { editing = EditTarget(id: item.id, session: s.id, ex: ex) } label: { Label("Ret sæt og pause", systemImage: "slider.horizontal.3") }
                    Button { library = PhoneLibraryTarget(session: s.id, replacing: item.id, area: ex.area) } label: {
                        Label("Byt øvelse", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button { move(s.id, i, -1) } label: { Label("Flyt op", systemImage: "arrow.up") }.disabled(i == 0)
                    Button { move(s.id, i, 1) } label: { Label("Flyt ned", systemImage: "arrow.down") }.disabled(i == s.items.count - 1)
                    Divider()
                    Button(role: .destructive) { remove(s.id, item.id) } label: { Label("Fjern", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").font(.body.weight(.semibold)).foregroundStyle(Fomo.text2)
                        .frame(width: 36, height: 36).contentShape(Rectangle())
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func index(_ session: String) -> Int? { store.program.firstIndex { $0.id == session } }

    private func pick(_ id: String, for t: PhoneLibraryTarget) {
        guard let si = index(t.session), let ex = TrainingProgram.exercise(id) else { return }
        var item = store.profile.map { TrainingBuilder.dose(ex, $0) }
            ?? PlanItem(exercise: ex.id, sets: ex.sets, repsLow: ex.repsLow, repsHigh: ex.repsHigh, rest: ex.rest)
        Haptic.success()
        withAnimation(.viggo) {
            if let r = t.replacing, let ii = store.program[si].items.firstIndex(where: { $0.id == r }) {
                item.id = r
                store.program[si].items[ii] = item
            } else {
                store.program[si].items.append(item)
            }
        }
    }

    private func move(_ session: String, _ i: Int, _ d: Int) {
        guard let si = index(session) else { return }
        Haptic.select()
        withAnimation(.viggo) { store.program[si].items.swapAt(i, i + d) }
    }

    private func remove(_ session: String, _ id: UUID) {
        guard let si = index(session) else { return }
        withAnimation(.viggo) { store.program[si].items.removeAll { $0.id == id } }
    }
}

/// Sets, reps and rest for one exercise in the program.
private struct PhoneItemEditor: View {
    @ObservedObject var store = TrainingStore.shared
    let session: String
    let item: UUID
    let ex: Exercise
    @Environment(\.dismiss) private var dismiss

    private func binding(_ key: WritableKeyPath<PlanItem, Int>) -> Binding<Int> {
        Binding(get: {
            store.session(session)?.items.first { $0.id == item }?[keyPath: key] ?? 0
        }, set: { v in
            guard let si = store.program.firstIndex(where: { $0.id == session }),
                  let ii = store.program[si].items.firstIndex(where: { $0.id == item }) else { return }
            Haptic.select()
            store.program[si].items[ii][keyPath: key] = v
            // Keep the range the right way round.
            let it = store.program[si].items[ii]
            if it.repsHigh < it.repsLow { store.program[si].items[ii].repsHigh = it.repsLow }
        })
    }

    var body: some View {
        let u = ex.unit == .seconds ? "sek" : "gange"
        NavigationStack {
            Form {
                Section {
                    stepper("Sæt", binding(\.sets), 1...8, 1) { "\($0)" }
                    stepper("Fra", binding(\.repsLow), 1...120, ex.unit == .seconds ? 5 : 1) { "\($0) \(u)" }
                    stepper("Til", binding(\.repsHigh), 1...120, ex.unit == .seconds ? 5 : 1) { "\($0) \(u)" }
                    stepper("Pause", binding(\.rest), 15...300, 15) { String(format: "%d:%02d", $0 / 60, $0 % 60) }
                } footer: {
                    Text("Viggo+ foreslår mere vægt, når du klarer alle sæt i toppen af intervallet.")
                }
            }
            .fomoList()
            .navigationTitle(ex.name)
            .trInlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Færdig") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }

    private func stepper(_ label: String, _ v: Binding<Int>, _ range: ClosedRange<Int>, _ step: Int, _ text: @escaping (Int) -> String) -> some View {
        Stepper(value: v, in: range, step: step) {
            HStack {
                Text(label)
                Spacer()
                Text(text(v.wrappedValue)).fontWeight(.semibold).monospacedDigit()
            }
        }
    }
}

/// Every exercise with its photo, to add or swap one.
private struct PhoneExerciseLibrary: View {
    let target: PhoneLibraryTarget
    let inSession: Set<String>
    let pick: (String) -> Void
    @ObservedObject var store = TrainingStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var area: Area?

    init(target: PhoneLibraryTarget, inSession: Set<String>, pick: @escaping (String) -> Void) {
        self.target = target
        self.inSession = inSession
        self.pick = pick
        _area = State(initialValue: target.area)
    }

    private var list: [Exercise] {
        let q = search.lowercased()
        let place = store.profile?.place ?? .gym
        return TrainingProgram.all
            .filter { area == nil || $0.area == area }
            .filter { q.isEmpty || $0.name.lowercased().contains(q) || $0.muscles.lowercased().contains(q) }
            .sorted { TrainingBuilder.fits($0, place) && !TrainingBuilder.fits($1, place) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip("Alle", area == nil) { area = nil }
                        ForEach(Area.allCases) { a in chip(a.title, area == a) { area = a } }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 8)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
                    ForEach(list) { e in card(e) }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .background(Fomo.bg)
            .searchable(text: $search, prompt: "Søg i øvelser")
            .navigationTitle(target.replacing == nil ? "Tilføj øvelse" : "Byt øvelse")
            .trInlineTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Luk") { dismiss() } } }
        }
    }

    private func chip(_ title: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button { Haptic.select(); withAnimation(.viggo) { action() } } label: {
            Text(title).font(.subheadline.weight(.medium)).padding(.horizontal, 14).frame(height: 34)
                .background(Capsule().fill(on ? Fomo.accent : Fomo.surface))
                .foregroundStyle(on ? .white : .primary)
        }
        .buttonStyle(PressScale())
    }

    private func card(_ e: Exercise) -> some View {
        let taken = inSession.contains(e.id)
        return Button { pick(e.id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Color.clear.aspectRatio(3 / 2, contentMode: .fit)
                    .overlay { GeometryReader { g in ExerciseThumb(ex: e, width: g.size.width, height: g.size.height, frame: 0) } }
                    .overlay(alignment: .topLeading) {
                        if e.gear != .gym {
                            Text(e.gear == .home ? "Hjemme" : "Også hjemme").font(.caption2.weight(.bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(.black.opacity(0.55))).foregroundStyle(.white).padding(6)
                        }
                    }
                Text(e.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(taken ? "Er allerede med" : e.muscles).font(.caption)
                    .foregroundStyle(taken ? Fomo.warn : Fomo.text2).lineLimit(1)
            }
            .foregroundStyle(.primary)
            .opacity(taken ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale(scale: 0.97))
        .disabled(taken)
    }
}

// MARK: - Progress

private struct PhoneProgressPage: View {
    @ObservedObject var store = TrainingStore.shared
    @State private var exercise = "squat"
    @State private var newWeight = ""
    @FocusState private var weightField: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                pageTitle("Fremgang")
                bodyWeight
                if store.logs.isEmpty {
                    Text("Når du har afsluttet din første træning, kommer din fremgang her.")
                        .font(.subheadline).foregroundStyle(Fomo.text2)
                } else {
                    HStack(spacing: 8) {
                        tile("\(store.logs.count)", "træninger")
                        tile("\(store.weeksInRow())", "uger i træk")
                        tile(kgText((store.logs.reduce(0) { $0 + $1.volume } / 1000 * 10).rounded() / 10) + " ton", "løftet i alt")
                    }
                    chart
                    history
                }
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            // Start on an exercise you actually do.
            let ids = Set(store.program.flatMap { $0.items.map(\.exercise) })
            if !ids.contains(exercise), let first = store.program.first?.items.first?.exercise { exercise = first }
        }
    }

    private var bodyWeight: some View {
        let w = store.weights
        return VStack(alignment: .leading, spacing: 12) {
            Text("Kropsvægt").font(.headline)
            if let last = w.last {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(kgText(last.kg)) kg").font(.largeTitle.weight(.bold)).monospacedDigit()
                    if let first = w.first, w.count > 1 {
                        let d = ((last.kg - first.kg) * 10).rounded() / 10
                        Text("\(d > 0 ? "+" : d < 0 ? "−" : "")\(kgText(abs(d))) kg siden \(shortDay.string(from: first.date))")
                            .font(.subheadline.weight(.medium)).foregroundStyle(Fomo.text2)
                    }
                }
            } else {
                Text("Vej dig en gang om ugen, samme tid på dagen.").font(.subheadline).foregroundStyle(Fomo.text2)
            }
            if w.count > 1 {
                let lo = (w.map(\.kg).min() ?? 0) - 1, hi = (w.map(\.kg).max() ?? 0) + 1
                Chart(w) { p in
                    LineMark(x: .value("Dato", p.date), y: .value("kg", p.kg)).foregroundStyle(Fomo.warn)
                    PointMark(x: .value("Dato", p.date), y: .value("kg", p.kg)).foregroundStyle(Fomo.warn)
                }
                .chartYScale(domain: lo...hi)
                .frame(height: 150)
            }
            HStack(spacing: 8) {
                TextField("Vægt i kg", text: $newWeight)
                    .trKeyboard(decimal: true).focused($weightField)
                    .font(.body.weight(.semibold)).monospacedDigit()
                    .padding(.horizontal, 12).frame(height: 42)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Fomo.surface2))
                Button(action: addWeight) {
                    Text("Gem").font(.body.weight(.semibold)).padding(.horizontal, 18).frame(height: 42)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Fomo.accent)).foregroundStyle(.white)
                }
                .buttonStyle(PressScale())
                .disabled(!validWeight).opacity(validWeight ? 1 : 0.45)
            }
            if !w.isEmpty {
                Text("Vægten svinger 1-2 kg fra dag til dag. Kig på kurven over flere uger. Hold fingeren på kortet for at slette den seneste.")
                    .font(.footnote).foregroundStyle(Fomo.text2)
            }
        }
        .padding(16)
        .surface()
        .contextMenu {
            if let last = w.last {
                Button(role: .destructive) { store.deleteWeight(last) } label: { Label("Slet seneste vægt (\(kgText(last.kg)) kg)", systemImage: "trash") }
            }
        }
    }

    private var validWeight: Bool { num(newWeight).map { (30...250).contains($0) } == true }

    private func addWeight() {
        guard let kg = num(newWeight), (30...250).contains(kg) else { return }
        Haptic.success()
        withAnimation(.viggo) { store.logWeight(kg) }
        newWeight = ""
        weightField = false
    }

    private func tile(_ n: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(n).font(.title2.weight(.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(Fomo.text2).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .surface()
    }

    private var chart: some View {
        let ex = TrainingProgram.exercise(exercise)
        let points = store.history(exercise)
        let unit = ex?.unit == .seconds ? "sek" : ex?.bodyweight == true ? "stk" : "kg"
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Øvelse", selection: $exercise) {
                    let done = Set(store.logs.flatMap { $0.exercises.map(\.exercise) } + store.program.flatMap { $0.items.map(\.exercise) })
                    ForEach(TrainingProgram.all.filter { done.contains($0.id) }) { e in Text(e.name).tag(e.id) }
                }
                .pickerStyle(.menu).labelsHidden().tint(.primary)
                Spacer()
                if let first = points.first?.1, let last = points.last?.1, last > first {
                    Text("+\(kgText(last - first)) \(unit)").font(.subheadline.weight(.semibold)).foregroundStyle(Fomo.green)
                }
            }
            if points.isEmpty {
                Text("Ingen sæt endnu i denne øvelse.").font(.subheadline).foregroundStyle(Fomo.text2)
                    .frame(maxWidth: .infinity).frame(height: 160)
            } else {
                Chart(points, id: \.0) { p in
                    LineMark(x: .value("Dato", p.0), y: .value(unit, p.1)).foregroundStyle(Fomo.accent)
                    PointMark(x: .value("Dato", p.0), y: .value(unit, p.1)).foregroundStyle(Fomo.accent)
                }
                .chartYAxisLabel(unit)
                .frame(height: 190)
            }
        }
        .padding(16)
        .surface()
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Seneste træninger").font(.headline)
            ForEach(store.logs.sorted { $0.started > $1.started }.prefix(12)) { l in
                HStack(spacing: 10) {
                    letterBadge(l.session, filled: false, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(cap(longDay.string(from: l.started))).font(.subheadline)
                        Text("\(Int(l.finished.timeIntervalSince(l.started) / 60)) min · \(l.doneSets) sæt · \(kgText(l.volume.rounded())) kg")
                            .font(.footnote).monospacedDigit().foregroundStyle(Fomo.text2)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .contextMenu {
                    Button(role: .destructive) { store.delete(l) } label: { Label("Slet træningen", systemImage: "trash") }
                }
            }
        }
        .padding(16)
        .surface()
    }
}

/// The screen stays on during a workout, so the sets are there when you look at the phone.
@MainActor func trKeepAwake(_ on: Bool) {
    #if os(iOS)
    UIApplication.shared.isIdleTimerDisabled = on
    #endif
}
