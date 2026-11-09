import ActivityKit
import Foundation

extension AppState {
    func widgetItem(_ e: ViggoEvent) -> WidgetItem {
        WidgetItem(title: e.shortTitle, start: e.start, end: e.end, room: e.room,
                   kind: e.kind.rawValue, color: (e.customColor ?? (e.kind == .lesson ? e.subjectColor : nil))?.hex)
    }

    /// For checking from Terminal: VIGGO_LIVE_AT="2026-11-10 10:30" pretends it is that time,
    /// so the Live Activity can be seen in a lesson outside school hours (see LiveDay.now).
    private var liveNow: Date { LiveDay.now() }
    static func testNow(_ real: Date) -> Date { LiveDay.now() }

    /// Starts the Live Activity when school begins, keeps it current and ends it after the last lesson.
    /// iOS only lets the app start one while it is open; after that it is updated from every sync.
    func updateLiveActivity() {
        let now = liveNow
        let running = Activity<LessonAttributes>.activities
        let items = timeline(now).map(widgetItem)
        let day = LiveDay.state(items, at: now)
        if ProcessInfo.processInfo.environment["VIGGO_LIVE_AT"] != nil {
            print("[live] now=\(now) pref=\(prefs.liveActivity) login=\(needsLogin) enabled=\(ActivityAuthorizationInfo().areActivitiesEnabled) items=\(items.count) school=\(day != nil) running=\(running.count)")
        }
        // Turned off in Settings: leave one started from Shortcuts alone, but never start one here.
        if !prefs.liveActivity, day != nil { return }
        guard !needsLogin, ActivityAuthorizationInfo().areActivitiesEnabled, let (state, stale) = day else {
            for a in running { Task { await a.end(nil, dismissalPolicy: .immediate) } }
            return
        }
        let content = ActivityContent(state: state, staleDate: stale)
        if let a = running.first {
            guard a.content.state != state else { return }
            Task { await a.update(content) }
            for extra in running.dropFirst() { Task { await extra.end(nil, dismissalPolicy: .immediate) } }
        } else {
            let first = profile.map { $0.name.components(separatedBy: " ").first ?? $0.name } ?? ""
            do {
                let a = try Activity.request(attributes: LessonAttributes(name: first), content: content)
                if ProcessInfo.processInfo.environment["VIGGO_LIVE_AT"] != nil {
                    print("[live] started \(a.id) state=\(a.activityState)")
                    Task { for await st in a.activityStateUpdates { print("[live] state -> \(st)") } }
                }
            }
            catch { print("[live] request failed: \(error)") }
        }
    }
}
