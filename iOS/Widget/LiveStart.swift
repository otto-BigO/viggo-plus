import ActivityKit
import AppIntents
import Foundation

/// What the Live Activity shows at a given moment. Shared by the app (after every sync) and
/// StartLiveIntent (Shortcuts, Control Center), which only has the widget data to go on.
enum LiveDay {
    /// The state at `now`, or nil outside school: from half an hour before the first lesson
    /// or event until the last one ends.
    static func state(_ all: [WidgetItem], at now: Date) -> (state: LessonAttributes.ContentState, stale: Date?)? {
        let items = all.filter { Calendar.current.isDate($0.start, inSameDayAs: now) }
        let school = items.filter { $0.kind == "lesson" || $0.kind == "event" }
        guard let first = school.first, let last = school.map(\.end).max(),
              now >= first.start.addingTimeInterval(-30 * 60), now < last else { return nil }
        let current = items.first { $0.start <= now && $0.end > now }
        let upcoming = items.filter { $0.start > now && !$0.isPause && $0.start < last }
        let state = LessonAttributes.ContentState(current: current, next: upcoming.first, later: Array(upcoming.dropFirst().prefix(3)))
        // Stale at the next change, so the lock screen shows what comes next if no update arrives in time.
        return (state, [current?.end, upcoming.first?.start].compactMap { $0 }.min())
    }

    /// The clock, which tests can move: VIGGO_LIVE_AT="2026-11-10 10:30" in the environment, or the
    /// same text in live-at.txt in the app group (an intent run by Shortcuts gets no environment).
    static func now() -> Date {
        guard let fake = override else { return Date() }
        return fake.addingTimeInterval(Date().timeIntervalSince(started))
    }
    private static let started = Date()
    /// Read once, since the I dag screen asks for the time on every redraw.
    private static let override: Date? = {
        let s = ProcessInfo.processInfo.environment["VIGGO_LIVE_AT"]
            ?? WidgetStore.url.flatMap { try? String(contentsOf: $0.deletingLastPathComponent().appendingPathComponent("live-at.txt"), encoding: .utf8) }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        return s.flatMap { f.date(from: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }()
}

/// Starts (or refreshes) the school day Live Activity without opening the app. iOS only lets an
/// app start one in the background from an intent like this, so it is what makes a Shortcuts
/// automation ("7.45 on weekdays", "when I arrive at school") or the Control Center button work.
struct StartLiveIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Vis skoledagen"
    static var description = IntentDescription("Viser timen der er i gang og nedtællingen på låseskærmen, uden at åbne Viggo+.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let data = WidgetStore.load()
        if let m = data.missing { return .result(dialog: IntentDialog(stringLiteral: m)) }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return .result(dialog: "Live Activities er slået fra for Viggo+ i Indstillinger.")
        }
        let now = LiveDay.now()
        let running = Activity<LessonAttributes>.activities
        guard let (state, stale) = LiveDay.state(data.items, at: now) else {
            for a in running { await a.end(nil, dismissalPolicy: .immediate) }
            return .result(dialog: IntentDialog(stringLiteral: "Ingen skole lige nu. " + data.sayNow(now)))
        }
        let content = ActivityContent(state: state, staleDate: stale)
        if let a = running.first {
            await a.update(content)
        } else {
            do { _ = try Activity.request(attributes: LessonAttributes(name: data.name ?? ""), content: content) }
            catch {
                // Run twice at once (a double tap), the other run may have just started it: update that one.
                if let a = Activity<LessonAttributes>.activities.first { await a.update(content) }
                else { return .result(dialog: "iOS ville ikke starte den lige nu. Prøv igen, eller åbn Viggo+.") }
            }
        }
        let what = state.current.map { $0.isPause ? "Pause" : $0.title } ?? state.next.map { "Næste: \($0.title)" } ?? "Skoledagen"
        return .result(dialog: IntentDialog(stringLiteral: "\(what) står nu på låseskærmen."))
    }
}
