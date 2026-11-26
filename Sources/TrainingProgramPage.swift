import SwiftUI

// Program: your workouts and their exercises. Swap, add, remove and move exercises, and change
// sets, reps and rest. The library shows every exercise with its photo.

/// What the library was opened for: adding to a workout, or swapping one exercise.
struct LibraryTarget: Identifiable {
    let id = UUID()
    let session: String
    var replacing: UUID? = nil
    var area: Area? = nil
}

struct TrainingProgramPage: View {
    @ObservedObject var store = TrainingStore.shared
    let editSetup: () -> Void
    @State private var library: LibraryTarget?
    @State private var editing: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dit program").font(.system(size: 20, weight: .bold, design: Fomo.design))
                        Text((store.profile?.summary ?? "Standardprogrammet. Lav din opsætning for at få et program til dig.") + "\nKlik på et billede for at se, hvordan øvelsen laves.")
                            .font(.system(size: 12, design: Fomo.design)).foregroundStyle(Fomo.text2)
                    }
                    Spacer()
                    Button(action: editSetup) {
                        Label(store.profile == nil ? "Lav opsætning" : "Ret opsætning", systemImage: "slider.horizontal.3")
                            .font(.system(size: 12, weight: .semibold, design: Fomo.design)).padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Fomo.surface2))
                    }
                    .buttonStyle(PressScale())
                }
                ForEach(store.program) { s in sessionCard(s) }
            }
            .padding(24)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .sheet(item: $library) { t in
            ExerciseLibrary(target: t, inSession: Set(store.session(t.session)?.items.map(\.exercise) ?? [])) { id in
                pick(id, for: t)
                library = nil
            } close: { library = nil }
        }
    }

    private func minutes(_ s: TrainingSession) -> Int {
        let secs = s.items.reduce(0) { $0 + $1.sets * (45 + $1.rest) }
        return Int((Double(secs) / 60 / 5).rounded()) * 5 + 10
    }

    private func sessionCard(_ s: TrainingSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(s.id).font(.system(size: 17, weight: .bold, design: Fomo.design)).frame(width: 38, height: 38)
                    .background(Circle().fill(Fomo.green.opacity(0.18))).foregroundStyle(Fomo.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Træning \(s.id)").font(.system(size: 14, weight: .semibold, design: Fomo.design))
                    Text("\(s.name) · \(s.items.count) øvelser · ca. \(minutes(s)) min").font(.system(size: 11.5, design: Fomo.design)).foregroundStyle(Fomo.text2)
                }
                Spacer()
            }
            VStack(spacing: 0) {
                ForEach(Array(s.items.enumerated()), id: \.element.id) { i, item in
                    if i > 0 { Divider().padding(.leading, 96) }
                    row(s, i, item)
                }
            }
            Button { library = LibraryTarget(session: s.id) } label: {
                Label("Tilføj øvelse", systemImage: "plus").font(.system(size: 12, weight: .medium, design: Fomo.design)).foregroundStyle(Fomo.accent)
            }
            .buttonStyle(.plain).padding(.leading, 4)
        }
        .padding(14)
        .surface()
    }

    @ViewBuilder private func row(_ s: TrainingSession, _ i: Int, _ item: PlanItem) -> some View {
        if let ex = TrainingProgram.exercise(item.exercise) {
            HStack(spacing: 12) {
                ExercisePeek(ex: ex, width: 84, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ex.name).font(.system(size: 13, weight: .medium, design: Fomo.design))
                    Text(ex.muscles).font(.system(size: 11, design: Fomo.design)).foregroundStyle(Fomo.text2)
                }
                Spacer()
                Button { editing = item.id } label: {
                    Text(targetText(ex, item)).font(.system(size: 12, design: Fomo.design)).monospacedDigit()
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(Fomo.surface2))
                }
                .buttonStyle(PressScale())
                .help("Ret sæt, gentagelser og pause")
                .popover(isPresented: Binding(get: { editing == item.id }, set: { if !$0 { editing = nil } })) {
                    ItemEditor(session: s.id, item: item.id, unit: ex.unit)
                }
                Menu {
                    Button("Byt øvelse…") { library = LibraryTarget(session: s.id, replacing: item.id, area: ex.area) }
                    Button("Flyt op") { move(s.id, i, -1) }.disabled(i == 0)
                    Button("Flyt ned") { move(s.id, i, 1) }.disabled(i == s.items.count - 1)
                    Divider()
                    Button("Fjern", role: .destructive) { remove(s.id, item.id) }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 15, design: Fomo.design)).foregroundStyle(Fomo.text2)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            .padding(.vertical, 6)
        }
    }

    private func index(_ session: String) -> Int? { store.program.firstIndex { $0.id == session } }

    private func pick(_ id: String, for t: LibraryTarget) {
        guard let si = index(t.session), let ex = TrainingProgram.exercise(id) else { return }
        var item = store.profile.map { TrainingBuilder.dose(ex, $0) }
            ?? PlanItem(exercise: ex.id, sets: ex.sets, repsLow: ex.repsLow, repsHigh: ex.repsHigh, rest: ex.rest)
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
        withAnimation(.viggo) { store.program[si].items.swapAt(i, i + d) }
    }

    private func remove(_ session: String, _ id: UUID) {
        guard let si = index(session) else { return }
        withAnimation(.viggo) { store.program[si].items.removeAll { $0.id == id } }
    }
}

/// Sets, reps and rest for one exercise in the program.
private struct ItemEditor: View {
    @ObservedObject var store = TrainingStore.shared
    let session: String
    let item: UUID
    let unit: RepUnit

    private func binding(_ key: WritableKeyPath<PlanItem, Int>) -> Binding<Int> {
        Binding(get: {
            store.session(session)?.items.first { $0.id == item }?[keyPath: key] ?? 0
        }, set: { v in
            guard let si = store.program.firstIndex(where: { $0.id == session }),
                  let ii = store.program[si].items.firstIndex(where: { $0.id == item }) else { return }
            store.program[si].items[ii][keyPath: key] = v
            // Keep the range the right way round.
            let it = store.program[si].items[ii]
            if it.repsHigh < it.repsLow { store.program[si].items[ii].repsHigh = it.repsLow }
        })
    }

    var body: some View {
        let u = unit == .seconds ? "sek" : "gange"
        VStack(alignment: .leading, spacing: 12) {
            Text("Sæt og gentagelser").font(.system(size: 13, weight: .semibold, design: Fomo.design))
            stepper("Sæt", binding(\.sets), 1...8, 1, "")
            stepper("Fra", binding(\.repsLow), 1...120, unit == .seconds ? 5 : 1, u)
            stepper("Til", binding(\.repsHigh), 1...120, unit == .seconds ? 5 : 1, u)
            stepper("Pause", binding(\.rest), 15...300, 15, "")
        }
        .padding(16)
        .frame(width: 250)
    }

    private func stepper(_ label: String, _ v: Binding<Int>, _ range: ClosedRange<Int>, _ step: Int, _ unit: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12.5, design: Fomo.design))
            Spacer()
            Text(label == "Pause" ? String(format: "%d:%02d", v.wrappedValue / 60, v.wrappedValue % 60) : "\(v.wrappedValue) \(unit)")
                .font(.system(size: 12.5, weight: .semibold, design: Fomo.design)).monospacedDigit()
            Stepper("", value: v, in: range, step: step).labelsHidden()
        }
    }
}

/// Every exercise with its photo, to add or swap one.
struct ExerciseLibrary: View {
    let target: LibraryTarget
    let inSession: Set<String>
    let pick: (String) -> Void
    let close: () -> Void
    @ObservedObject var store = TrainingStore.shared
    @State private var search = ""
    @State private var area: Area?

    init(target: LibraryTarget, inSession: Set<String>, pick: @escaping (String) -> Void, close: @escaping () -> Void) {
        self.target = target
        self.inSession = inSession
        self.pick = pick
        self.close = close
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
        VStack(spacing: 0) {
            HStack {
                Text(target.replacing == nil ? "Tilføj øvelse" : "Byt øvelse").font(.system(size: 18, weight: .bold, design: Fomo.design))
                Spacer()
                Button("Luk", action: close).keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20).padding(.top, 18)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Fomo.text2)
                TextField("Søg", text: $search).textFieldStyle(.plain)
            }
            .padding(.horizontal, 12).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 9).fill(Fomo.surface2))
            .padding(.horizontal, 20).padding(.top, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("Alle", area == nil) { area = nil }
                    ForEach(Area.allCases) { a in chip(a.title, area == a) { area = a } }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 12)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 14) {
                    ForEach(list) { e in card(e) }
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
        }
        .frame(width: 780, height: 580)
        .background(Fomo.bg)
    }

    private func chip(_ title: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button { withAnimation(.viggo) { action() } } label: {
            Text(title).font(.system(size: 12, weight: .medium, design: Fomo.design)).padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(on ? Fomo.accent : Fomo.surface))
                .foregroundStyle(on ? .white : .primary)
        }
        .buttonStyle(PressScale())
    }

    private func card(_ e: Exercise) -> some View {
        let taken = inSession.contains(e.id)
        return Button { pick(e.id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                ExerciseThumb(ex: e, width: 170, height: 112, frame: 0)
                    .overlay(alignment: .topLeading) {
                        if e.gear != .gym {
                            Text(e.gear == .home ? "Hjemme" : "Også hjemme").font(.system(size: 9.5, weight: .bold, design: Fomo.design))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(.black.opacity(0.55))).foregroundStyle(.white).padding(6)
                        }
                    }
                Text(e.name).font(.system(size: 12.5, weight: .semibold, design: Fomo.design)).lineLimit(1)
                Text(taken ? "Er allerede med" : e.muscles).font(.system(size: 11, design: Fomo.design))
                    .foregroundStyle(taken ? Fomo.warn : Fomo.text2).lineLimit(1)
            }
            .frame(width: 170, alignment: .leading)
            .opacity(taken ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale(scale: 0.97))
        .disabled(taken)
    }
}
