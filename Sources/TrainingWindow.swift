import AppKit
import Charts
import SwiftUI

// The Træning window: Plan (find time in the schedule), Træn (the workout, like the Strong app)
// and Fremgang (history and charts). Data and the planner are in Shared/Training.swift.

struct TrainingWindow: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var store = TrainingStore.shared
    @ObservedObject var prefs = Prefs.shared
    @State private var page: TrainingPage
    /// The setup shows first, and again from Program › Ret opsætning.
    @State private var setup: Bool
    /// Workouts to show instead of the real schedule (pictures and tests).
    private let preview: [PlannedItem]?

    init(page: TrainingPage? = nil, preview: [PlannedItem]? = nil, setup: Bool? = nil) {
        _page = State(initialValue: page ?? (TrainingStore.shared.active != nil ? .workout : .plan))
        _setup = State(initialValue: setup ?? (TrainingStore.shared.profile == nil))
        self.preview = preview
    }

    var body: some View {
        Group {
            if setup {
                TrainingSetup(profile: store.profile) { next in
                    withAnimation(.viggo) {
                        if let next { page = next }
                        setup = false
                    }
                }
                .frame(minWidth: 820, minHeight: 600)
                .transition(.opacity)
            } else {
                main.transition(.opacity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .viggoTrainingPage)) { n in
            if let p = n.object as? TrainingPage, !setup { withAnimation(.viggo) { page = p } }
        }
    }

    private var main: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 200)
            Rectangle().fill(Fomo.surface2).frame(width: 1)
            Group {
                switch page {
                case .plan: TrainingPlanPage(preview: preview) { letter in store.start(letter); withAnimation(.viggo) { page = .workout } }
                case .workout: WorkoutPage()
                case .program: TrainingProgramPage { withAnimation(.viggo) { setup = true } }
                case .progress: ProgressPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Fomo.bg)
        .frame(minWidth: 820, minHeight: 600)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Træning").font(.system(size: 22, weight: .bold, design: Fomo.design)).padding(.top, 36)
            Text("Fitnessrummet er altid åbent").font(.system(size: 11, design: Fomo.design)).foregroundStyle(Fomo.text2).padding(.bottom, 14)
            ForEach(TrainingPage.allCases, id: \.self) { p in
                Button { withAnimation(.viggo) { page = p } } label: {
                    HStack(spacing: 9) {
                        Image(systemName: p.icon).frame(width: 18)
                        Text(p.rawValue)
                        Spacer()
                        if p == .workout, store.active != nil {
                            Circle().fill(Fomo.green).frame(width: 7, height: 7).help("En træning er i gang")
                        }
                    }
                    .font(.system(size: 13, weight: page == p ? .semibold : .regular, design: Fomo.design))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(page == p ? Fomo.accent.opacity(0.18) : .clear))
                    .foregroundStyle(page == p ? Fomo.accent : .primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScale(scale: 0.96))
            }
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                stat("checkmark.circle.fill", "\(store.thisWeek()) af \(store.wish.count) denne uge", Fomo.green)
                stat("flame.fill", store.weeksInRow() == 1 ? "1 uge i træk" : "\(store.weeksInRow()) uger i træk", Fomo.warn)
                stat("figure.strengthtraining.traditional", "Næste: træning \(store.nextSession)", Fomo.accent)
            }
            .padding(.bottom, 18)
        }
        .padding(.horizontal, 14)
        .background(Fomo.surface.opacity(0.5))
    }

    private func stat(_ icon: String, _ text: String, _ c: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).foregroundStyle(c).frame(width: 16)
            Text(text).font(.system(size: 11.5, design: Fomo.design)).foregroundStyle(Fomo.text2)
        }
    }
}

// MARK: - Plan

private struct TrainingPlanPage: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var store = TrainingStore.shared
    let preview: [PlannedItem]?
    let start: (String) -> Void

    private var items: [PlannedItem] {
        let now = Date()
        return (preview ?? prefs.planned.filter { $0.from == TrainingPlanner.tag })
            .filter { $0.end > DateUtil.startOfDay(now) }.sorted { $0.start < $1.start }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Din træningsuge").font(.system(size: 20, weight: .bold, design: Fomo.design))
                Text("Viggo+ finder ledige tider på \(store.wish.minutes) min i dit skema, 20 min efter mad, og lægger \(store.wish.count) træninger ind med en hviledag imellem, når det kan lade sig gøre.")
                    .font(.system(size: 12, design: Fomo.design)).foregroundStyle(Fomo.text2).fixedSize(horizontal: false, vertical: true)
                Toggle(isOn: $prefs.trainingInSchedule.animation(.viggo)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vis i skema").font(.system(size: 13, weight: .semibold, design: Fomo.design))
                        Text(prefs.trainingInSchedule
                             ? "Træningerne står i panelet, menubaren og Uge-overblikket."
                             : "Træningerne er kun her. Panelet, menubaren og Uge-overblikket viser dem ikke.")
                            .font(.system(size: 11, design: Fomo.design)).foregroundStyle(Fomo.text2)
                    }
                }
                .toggleStyle(.switch).controlSize(.small)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .surface(Fomo.radiusSmall)
                Button { findTimes() } label: {
                    Label(items.isEmpty ? "Find tider de næste 7 dage" : "Find nye tider", systemImage: "wand.and.stars")
                        .font(.system(size: 13, weight: .semibold, design: Fomo.design)).padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Fomo.accent)).foregroundStyle(.white)
                }
                .buttonStyle(PressScale())
                if items.isEmpty {
                    Text("Ingen træning planlagt endnu.").font(.system(size: 13, design: Fomo.design)).foregroundStyle(Fomo.text2).padding(.top, 20)
                }
                ForEach(items) { item in card(item) }
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
        }
    }

    private func findTimes() {
        let now = Date()
        let new = TrainingPlanner.suggest(events: state.events, planned: prefs.planned, custom: prefs.customItems,
                                          now: now, first: store.nextSession, order: store.order, wish: store.wish)
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
        return HStack(alignment: .top, spacing: 14) {
            Text(letter).font(.system(size: 18, weight: .bold, design: Fomo.design)).frame(width: 40, height: 40)
                .background(Circle().fill(done ? Fomo.green : Fomo.green.opacity(0.18)))
                .foregroundStyle(done ? Fomo.onGreen : Fomo.green)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.title).font(.system(size: 14, weight: .semibold, design: Fomo.design))
                    if today { Text("I DAG").font(.system(size: 9, weight: .bold, design: Fomo.design)).padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(Fomo.accent)).foregroundStyle(.white) }
                    if done { Label("Klaret", systemImage: "checkmark").font(.system(size: 11, weight: .semibold, design: Fomo.design)).foregroundStyle(Fomo.green) }
                }
                Text("\(cap(longDay.string(from: item.start))) · \(DateUtil.hm(item.start))-\(DateUtil.hm(item.end))")
                    .font(.system(size: 12, design: Fomo.design)).monospacedDigit().foregroundStyle(Fomo.text2)
                Text(store.exercises(letter).map(\.name).joined(separator: ", "))
                    .font(.system(size: 11, design: Fomo.design)).foregroundStyle(.tertiary).lineLimit(2)
                if let clash {
                    Label("Overlapper nu med \(clash)", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium, design: Fomo.design)).foregroundStyle(Fomo.red)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                if today && !done && !past {
                    Button { start(letter) } label: {
                        Text(store.active != nil ? "Fortsæt" : "Start").font(.system(size: 12, weight: .semibold, design: Fomo.design))
                            .padding(.horizontal, 12).padding(.vertical, 5).background(Capsule().fill(Fomo.green)).foregroundStyle(Fomo.onGreen)
                    }
                    .buttonStyle(PressScale())
                }
                if !past && preview == nil {
                    HStack(spacing: 10) {
                        Menu {
                            let opts = TrainingPlanner.options(events: state.events, planned: prefs.planned, custom: prefs.customItems,
                                                               now: Date(), ignoring: item.id, wish: store.wish)
                            if opts.isEmpty { Text("Ingen andre ledige tider") }
                            ForEach(opts, id: \.self) { o in
                                Button("\(shortDay.string(from: o.start)) kl. \(DateUtil.hm(o.start))") { move(item, to: o) }
                            }
                        } label: { Text("Flyt").font(.system(size: 11.5, design: Fomo.design)) }
                        .menuStyle(.borderlessButton).fixedSize()
                        Button { withAnimation(.viggo) { prefs.planned.removeAll { $0.id == item.id } } } label: {
                            Image(systemName: "trash").font(.system(size: 11, design: Fomo.design))
                        }
                        .buttonStyle(.plain).foregroundStyle(Fomo.text2).help("Fjern fra skemaet")
                    }
                }
            }
        }
        .padding(14)
        .surface()
        .opacity(past && !done ? 0.5 : 1)
    }

    private func move(_ item: PlannedItem, to slot: TrainingPlanner.Slot) {
        guard let i = prefs.planned.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation(.viggo) {
            prefs.planned[i].start = slot.start
            prefs.planned[i].end = slot.end
        }
    }
}

// MARK: - Workout

private struct WorkoutPage: View {
    @ObservedObject var store = TrainingStore.shared
    @State private var summary: WorkoutLog?
    @State private var confirmCancel = false

    var body: some View {
        Group {
            if let a = store.active { active(a) } else { picker }
        }
        .sheet(item: $summary) { log in SummarySheet(log: log) { summary = nil } }
    }

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Vælg træning").font(.system(size: 20, weight: .bold, design: Fomo.design))
                Text("Kør dem i rækkefølgen \(store.order.joined(separator: ", ")). Næste gang er det træning \(store.nextSession). Klik på et billede for at se øvelsen.")
                    .font(.system(size: 12, design: Fomo.design)).foregroundStyle(Fomo.text2)
                ForEach(store.order, id: \.self) { s in
                    HStack(alignment: .top, spacing: 14) {
                        Text(s).font(.system(size: 18, weight: .bold, design: Fomo.design)).frame(width: 40, height: 40)
                            .background(Circle().fill(Fomo.green.opacity(s == store.nextSession ? 1 : 0.18)))
                            .foregroundStyle(s == store.nextSession ? Fomo.onGreen : Fomo.green)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Træning \(s)").font(.system(size: 14, weight: .semibold, design: Fomo.design))
                                Text(store.session(s)?.name ?? "").font(.system(size: 12, design: Fomo.design)).foregroundStyle(Fomo.text2)
                                if s == store.nextSession { Text("NÆSTE").font(.system(size: 9, weight: .bold, design: Fomo.design)).foregroundStyle(Fomo.green) }
                            }
                            ForEach(store.exercises(s)) { e in
                                HStack(spacing: 12) {
                                    ExercisePeek(ex: e, width: 66, height: 44)
                                    Text(e.name).font(.system(size: 12, design: Fomo.design))
                                    Spacer()
                                    Text(e.target).font(.system(size: 11, design: Fomo.design)).monospacedDigit().foregroundStyle(Fomo.text2)
                                }
                            }
                        }
                        Button { withAnimation(.viggo) { store.start(s) } } label: {
                            Text("Start").font(.system(size: 12, weight: .semibold, design: Fomo.design)).padding(.horizontal, 12).padding(.vertical, 5)
                                .background(Capsule().fill(Fomo.accent)).foregroundStyle(.white)
                        }
                        .buttonStyle(PressScale())
                    }
                    .padding(14)
                    .surface()
                }
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
        }
    }

    private func active(_ a: ActiveWorkout) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Træning \(a.session) · \(store.session(a.session)?.name ?? "")").font(.system(size: 20, weight: .bold, design: Fomo.design))
                    TimelineView(.periodic(from: .now, by: 1)) { t in
                        let s = max(0, Int(t.date.timeIntervalSince(a.started)))
                        Text(String(format: "%d:%02d", s / 60, s % 60)).font(.system(size: 12, design: Fomo.design)).monospacedDigit().foregroundStyle(Fomo.text2)
                    }
                }
                Spacer()
                Button("Annuller") { confirmCancel = true }.buttonStyle(.plain).font(.system(size: 12, design: Fomo.design)).foregroundStyle(Fomo.text2)
                    .confirmationDialog("Annuller træningen?", isPresented: $confirmCancel) {
                        Button("Annuller træningen", role: .destructive) { withAnimation(.viggo) { store.cancel() } }
                        Button("Fortsæt", role: .cancel) {}
                    } message: { Text("Sættene bliver ikke gemt.") }
                Button { summary = store.finish() } label: {
                    Text("Afslut").font(.system(size: 12, weight: .semibold, design: Fomo.design)).padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(Fomo.green)).foregroundStyle(Fomo.onGreen)
                }
                .buttonStyle(PressScale())
                .padding(.leading, 12)
            }
            .padding(.horizontal, 24).padding(.top, 30).padding(.bottom, 12)
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(a.exercises.indices, id: \.self) { i in ExerciseCard(index: i) }
                }
                .padding(.horizontal, 24).padding(.bottom, 90)
                .frame(maxWidth: 680)
            }
        }
        .overlay(alignment: .bottom) { RestBar() }
        .task(id: a.restEnds) {
            guard let end = a.restEnds, end > Date() else { return }
            try? await Task.sleep(for: .seconds(end.timeIntervalSinceNow))
            guard !Task.isCancelled, store.active?.restEnds == end else { return }
            NSSound(named: "Glass")?.play()
            withAnimation(.viggo) { store.active?.restEnds = nil }
        }
    }
}

private struct RestBar: View {
    @ObservedObject var store = TrainingStore.shared

    var body: some View {
        if let end = store.active?.restEnds {
            TimelineView(.periodic(from: .now, by: 0.5)) { t in
                let left = max(0, Int(end.timeIntervalSince(t.date).rounded(.up)))
                HStack(spacing: 14) {
                    Image(systemName: "timer").foregroundStyle(Fomo.accent)
                    Text("Pause").font(.system(size: 13, weight: .semibold, design: Fomo.design))
                    Text(String(format: "%d:%02d", left / 60, left % 60)).font(.system(size: 22, weight: .bold, design: Fomo.design)).monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                    Spacer()
                    Button("+15 sek") { store.active?.restEnds = end.addingTimeInterval(15) }
                    Button("Spring over") { withAnimation(.viggo) { store.active?.restEnds = nil } }
                }
                .buttonStyle(.plain).font(.system(size: 12, weight: .medium, design: Fomo.design))
                .padding(.horizontal, 18).padding(.vertical, 12)
                .surface(fill: Fomo.surface2)
                .padding(.horizontal, 24).padding(.bottom, 16)
                .frame(maxWidth: 680)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

private struct ExerciseCard: View {
    let index: Int
    @ObservedObject var store = TrainingStore.shared
    @State private var showHow: Bool

    /// The how-to opens by itself the first time you do an exercise.
    init(index: Int) {
        self.index = index
        let id = TrainingStore.shared.active?.exercises[safe: index]?.exercise ?? ""
        _showHow = State(initialValue: TrainingStore.shared.last(id) == nil)
    }

    var body: some View {
        if let a = store.active, let log = a.exercises[safe: index], let ex = store.spec(log.exercise, session: a.session) {
            VStack(alignment: .leading, spacing: 10) {
                header(ex)
                if showHow { how(ex).transition(.opacity) }
                sets(ex, log)
                Button { store.addSet(exercise: index) } label: {
                    Label("Sæt", systemImage: "plus").font(.system(size: 11.5, weight: .medium, design: Fomo.design)).foregroundStyle(Fomo.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .surface()
        }
    }

    private func header(_ ex: Exercise) -> some View {
        HStack(spacing: 12) {
            Button { withAnimation(.viggo) { showHow.toggle() } } label: { ExerciseThumb(ex: ex) }
                .buttonStyle(PressScale()).help("Sådan gør du")
            VStack(alignment: .leading, spacing: 2) {
                Text(ex.name).font(.system(size: 14, weight: .semibold, design: Fomo.design))
                Text("\(ex.muscles) · \(ex.target)").font(.system(size: 11, design: Fomo.design)).foregroundStyle(Fomo.text2)
            }
            Spacer()
            if let kg = store.suggestedKg(ex), let last = store.last(ex.id)?.sets.map(\.kg).max(), kg > last {
                Text("Prøv \(kgText(kg)) kg").font(.system(size: 10.5, weight: .bold, design: Fomo.design)).padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Fomo.green.opacity(0.18))).foregroundStyle(Fomo.green)
                    .help("Du klarede alle sæt i toppen af intervallet sidst")
            } else if store.last(ex.id) == nil && !ex.bodyweight {
                Text("Første gang: start let").font(.system(size: 10.5, weight: .medium, design: Fomo.design)).foregroundStyle(Fomo.warn)
            }
            Button { withAnimation(.viggo) { showHow.toggle() } } label: {
                Label("Sådan gør du", systemImage: showHow ? "chevron.up" : "questionmark.circle").font(.system(size: 11.5, design: Fomo.design))
            }
            .buttonStyle(.plain).foregroundStyle(Fomo.accent)
        }
    }

    private func how(_ ex: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 14) {
                ExerciseMotion(ex: ex).frame(width: 240, height: 160)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(ex.cues.enumerated()), id: \.offset) { i, c in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(i + 1)").font(.system(size: 11, weight: .bold, design: Fomo.design)).foregroundStyle(Fomo.accent).frame(width: 14)
                            Text(c).font(.system(size: 12, design: Fomo.design)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            HStack(spacing: 14) {
                if !ex.home.isEmpty { Text("Uden fitness: \(ex.home)").font(.system(size: 11, design: Fomo.design)).foregroundStyle(Fomo.text2) }
                Spacer()
                if let u = ex.videoURL {
                    Link(destination: u) { Label("Se video", systemImage: "play.rectangle.fill").font(.system(size: 11.5, weight: .medium, design: Fomo.design)) }
                }
            }
            .padding(.top, 3)
        }
        .padding(10)
        .surface(Fomo.radiusSmall, fill: Fomo.surface2)
    }

    private func sets(_ ex: Exercise, _ log: ExerciseLog) -> some View {
        let prev = store.last(ex.id)?.sets
        return Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                Text("SÆT"); Text("SIDST")
                Text(ex.bodyweight ? "" : "KG")
                Text(ex.unit == .seconds ? "SEK" : "REPS"); Text("")
            }
            .font(.system(size: 9.5, weight: .semibold, design: Fomo.design)).foregroundStyle(.tertiary)
            ForEach(log.sets.indices, id: \.self) { i in
                let s = log.sets[i]
                GridRow {
                    Text("\(i + 1)").font(.system(size: 12, weight: .semibold, design: Fomo.design)).frame(width: 26, alignment: .leading)
                    Text(prev.flatMap { $0.indices.contains(i) ? setText($0[i], ex) : nil } ?? "-")
                        .font(.system(size: 11.5, design: Fomo.design)).monospacedDigit().foregroundStyle(Fomo.text2).frame(width: 96, alignment: .leading)
                    if ex.bodyweight {
                        Text("Krop").font(.system(size: 11, design: Fomo.design)).foregroundStyle(.tertiary).frame(width: 64, alignment: .leading)
                    } else {
                        TextField("0", value: kg(i), format: .number).textFieldStyle(.roundedBorder).frame(width: 64)
                    }
                    TextField("0", value: reps(i), format: .number).textFieldStyle(.roundedBorder).frame(width: 56)
                    Button { withAnimation(.viggo) { store.toggle(exercise: index, set: i) } } label: {
                        Image(systemName: s.done ? "checkmark.circle.fill" : "circle").font(.system(size: 20, design: Fomo.design))
                            .foregroundStyle(s.done ? Fomo.green : Fomo.text2)
                            .symbolEffect(.bounce, value: s.done)
                    }
                    .buttonStyle(.plain).help(s.done ? "Fortryd" : "Sæt klaret")
                }
                .padding(.vertical, 2)
                .opacity(s.done ? 0.6 : 1)
            }
        }
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

private struct SummarySheet: View {
    let log: WorkoutLog
    let close: () -> Void
    @ObservedObject var store = TrainingStore.shared

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 44, design: Fomo.design)).foregroundStyle(Fomo.green)
            Text("Træning \(log.session) klaret").font(.system(size: 20, weight: .bold, design: Fomo.design))
            HStack(spacing: 28) {
                big("\(Int(log.finished.timeIntervalSince(log.started) / 60))", "min")
                big("\(log.doneSets)", "sæt")
                big(kgText(log.volume.rounded()), "kg løftet")
            }
            let recs = store.records(in: log).compactMap { TrainingProgram.exercise($0) }
            if !recs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(recs) { e in
                        Label("Ny rekord: \(e.name)", systemImage: "trophy.fill").font(.system(size: 12.5, weight: .medium, design: Fomo.design)).foregroundStyle(Fomo.warn)
                    }
                }
            }
            Button("Luk", action: close).keyboardShortcut(.defaultAction)
        }
        .padding(30)
        .frame(width: 380)
    }

    private func big(_ n: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(n).font(.system(size: 26, weight: .bold, design: Fomo.design)).monospacedDigit()
            Text(label).font(.system(size: 11, design: Fomo.design)).foregroundStyle(Fomo.text2)
        }
    }
}

// MARK: - Progress

private struct ProgressPage: View {
    @ObservedObject var store = TrainingStore.shared
    @State private var exercise = "squat"
    @State private var newWeight = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Fremgang").font(.system(size: 20, weight: .bold, design: Fomo.design))
                bodyWeight
                if store.logs.isEmpty {
                    Text("Når du har afsluttet din første træning, kommer din fremgang her.")
                        .font(.system(size: 13, design: Fomo.design)).foregroundStyle(Fomo.text2)
                } else {
                    HStack(spacing: 12) {
                        tile("\(store.logs.count)", "træninger i alt")
                        tile("\(store.weeksInRow())", "uger i træk")
                        tile(kgText((store.logs.reduce(0) { $0 + $1.volume } / 1000 * 10).rounded() / 10) + " ton", "løftet i alt")
                    }
                    chart
                    history
                }
            }
            .padding(24)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .onAppear {
            // Start on an exercise you actually do.
            let ids = Set(store.program.flatMap { $0.items.map(\.exercise) })
            if !ids.contains(exercise), let first = store.program.first?.items.first?.exercise { exercise = first }
        }
    }

    private var bodyWeight: some View {
        let w = store.weights
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kropsvægt").font(.system(size: 13, weight: .semibold, design: Fomo.design))
                    if let last = w.last {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(kgText(last.kg)) kg").font(.system(size: 26, weight: .bold, design: Fomo.design)).monospacedDigit()
                            if let first = w.first, w.count > 1 {
                                let d = ((last.kg - first.kg) * 10).rounded() / 10
                                Text("\(d > 0 ? "+" : d < 0 ? "−" : "")\(kgText(abs(d))) kg siden \(shortDay.string(from: first.date))")
                                    .font(.system(size: 12, weight: .medium, design: Fomo.design)).foregroundStyle(Fomo.text2)
                            }
                        }
                    } else {
                        Text("Vej dig en gang om ugen, samme tid på dagen.").font(.system(size: 12, design: Fomo.design)).foregroundStyle(Fomo.text2)
                    }
                }
                Spacer()
                HStack(spacing: 6) {
                    TextField("kg", text: $newWeight).textFieldStyle(.roundedBorder).frame(width: 64).onSubmit(addWeight)
                    Button("Gem vægt", action: addWeight).disabled(num(newWeight).map { (30...250).contains($0) } != true)
                }
            }
            if w.count > 1 {
                let lo = (w.map(\.kg).min() ?? 0) - 1, hi = (w.map(\.kg).max() ?? 0) + 1
                Chart(w) { p in
                    LineMark(x: .value("Dato", p.date), y: .value("kg", p.kg)).foregroundStyle(Fomo.warn)
                    PointMark(x: .value("Dato", p.date), y: .value("kg", p.kg)).foregroundStyle(Fomo.warn)
                }
                .chartYScale(domain: lo...hi)
                .chartYAxisLabel("kg")
                .frame(height: 140)
            }
            if !w.isEmpty {
                Text("Kropsvægten svinger 1-2 kg fra dag til dag. Kig på kurven over flere uger, og mål gerne taljen en gang om måneden.")
                    .font(.system(size: 11, design: Fomo.design)).foregroundStyle(Fomo.text2)
            }
        }
        .padding(14)
        .surface()
        .contextMenu {
            if let last = w.last { Button("Slet seneste vægt (\(kgText(last.kg)) kg)", role: .destructive) { store.deleteWeight(last) } }
        }
    }

    private func addWeight() {
        guard let kg = num(newWeight), (30...250).contains(kg) else { return }
        withAnimation(.viggo) { store.logWeight(kg) }
        newWeight = ""
    }

    private func tile(_ n: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(n).font(.system(size: 24, weight: .bold, design: Fomo.design)).monospacedDigit()
            Text(label).font(.system(size: 11, design: Fomo.design)).foregroundStyle(Fomo.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .surface()
    }

    private var chart: some View {
        let ex = TrainingProgram.exercise(exercise)
        let points = store.history(exercise)
        let unit = ex?.unit == .seconds ? "sek" : ex?.bodyweight == true ? "stk" : "kg"
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("", selection: $exercise) {
                    let done = Set(store.logs.flatMap { $0.exercises.map(\.exercise) } + store.program.flatMap { $0.items.map(\.exercise) })
                    ForEach(TrainingProgram.all.filter { done.contains($0.id) }) { e in Text(e.name).tag(e.id) }
                }
                .labelsHidden().fixedSize()
                Spacer()
                if let first = points.first?.1, let last = points.last?.1, last > first {
                    Text("+\(kgText(last - first)) \(unit)").font(.system(size: 12, weight: .semibold, design: Fomo.design)).foregroundStyle(Fomo.green)
                }
            }
            if points.isEmpty {
                Text("Ingen sæt endnu i denne øvelse.").font(.system(size: 12, design: Fomo.design)).foregroundStyle(Fomo.text2).frame(height: 180)
            } else {
                Chart(points, id: \.0) { p in
                    LineMark(x: .value("Dato", p.0), y: .value(unit, p.1)).foregroundStyle(Fomo.accent)
                    PointMark(x: .value("Dato", p.0), y: .value(unit, p.1)).foregroundStyle(Fomo.accent)
                }
                .chartYAxisLabel(unit)
                .frame(height: 200)
            }
        }
        .padding(14)
        .surface()
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Seneste træninger").font(.system(size: 13, weight: .semibold, design: Fomo.design))
            ForEach(store.logs.sorted { $0.started > $1.started }.prefix(12)) { l in
                HStack {
                    Text(l.session).font(.system(size: 12, weight: .bold, design: Fomo.design)).frame(width: 24, height: 24)
                        .background(Circle().fill(Fomo.green.opacity(0.18))).foregroundStyle(Fomo.green)
                    Text(cap(longDay.string(from: l.started))).font(.system(size: 12, design: Fomo.design))
                    Spacer()
                    Text("\(Int(l.finished.timeIntervalSince(l.started) / 60)) min · \(l.doneSets) sæt · \(kgText(l.volume.rounded())) kg")
                        .font(.system(size: 11, design: Fomo.design)).monospacedDigit().foregroundStyle(Fomo.text2)
                }
                .contextMenu { Button("Slet træningen", role: .destructive) { store.delete(l) } }
            }
        }
        .padding(14)
        .surface()
    }
}

/// A photo you can click to see the exercise moving, with the steps.
struct ExercisePeek: View {
    let ex: Exercise
    var width: CGFloat = 84
    var height: CGFloat = 56
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            ExerciseThumb(ex: ex, width: width, height: height)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "play.fill").font(.system(size: 7, weight: .bold, design: Fomo.design)).foregroundStyle(.white)
                        .frame(width: 17, height: 17).background(Circle().fill(.black.opacity(0.6))).padding(4)
                }
        }
        .buttonStyle(PressScale())
        .help("Se hvordan du laver \(ex.name.lowercased())")
        .popover(isPresented: $open, arrowEdge: .leading) { ExerciseDetail(ex: ex) }
    }
}

/// The exercise big: moving photo, the steps, what to do at home and a video link.
struct ExerciseDetail: View {
    let ex: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ExerciseMotion(ex: ex).frame(width: 360, height: 240)
            VStack(alignment: .leading, spacing: 2) {
                Text(ex.name).font(.system(size: 17, weight: .bold, design: Fomo.design))
                Text(ex.muscles).font(.system(size: 12, design: Fomo.design)).foregroundStyle(Fomo.text2)
            }
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(ex.cues.enumerated()), id: \.offset) { i, c in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(i + 1)").font(.system(size: 11, weight: .bold, design: Fomo.design)).foregroundStyle(Fomo.accent).frame(width: 14)
                        Text(c).font(.system(size: 12.5, design: Fomo.design)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack {
                if !ex.home.isEmpty {
                    Text("Uden fitness: \(ex.home)").font(.system(size: 11, design: Fomo.design)).foregroundStyle(Fomo.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if let u = ex.videoURL {
                    Link(destination: u) { Label("Se video", systemImage: "play.rectangle.fill").font(.system(size: 12, weight: .medium, design: Fomo.design)) }
                }
            }
        }
        .padding(16)
        .frame(width: 392)
    }
}
