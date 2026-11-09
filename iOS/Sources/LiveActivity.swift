import ActivityKit
import Foundation

extension AppState {
    func widgetItem(_ e: ViggoEvent) -> WidgetItem {
        WidgetItem(title: e.shortTitle, start: e.start, end: e.end, room: e.room,
                   kind: e.kind.rawValue, color: e.customColor?.hex)
    }

    /// For checking from Terminal: VIGGO_LIVE_AT="2026-11-10 10:30" pretends it is that time,
    /// so the Live Activity can be seen in a lesson outside school hours.
    private var liveNow: Date {
        guard let s = ProcessInfo.processInfo.environment["VIGGO_LIVE_AT"] else { return Date() }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s) ?? Date()
    }

    /// Starts the Live Activity when school begins, keeps it current and ends it after the last lesson.
    /// iOS only lets the app start one while it is open; after that it is updated from every sync.
    func updateLiveActivity() {
        let now = liveNow
        let running = Activity<LessonAttributes>.activities
        let items = timeline(now).map(widgetItem)
        let school = items.filter { $0.kind == "lesson" || $0.kind == "event" }
        guard prefs.liveActivity, !needsLogin, ActivityAuthorizationInfo().areActivitiesEnabled,
              let first = school.first, let last = school.map(\.end).max(),
              now >= first.start.addingTimeInterval(-30 * 60), now < last else {
            for a in running { Task { await a.end(nil, dismissalPolicy: .immediate) } }
            return
        }
        let current = items.first { $0.start <= now && $0.end > now }
        let upcoming = items.filter { $0.start > now && !$0.isPause && $0.start < last }
        let state = LessonAttributes.ContentState(current: current, next: upcoming.first, later: Array(upcoming.dropFirst().prefix(3)))
        // Stale at the next change, so the lock screen shows what comes next if no update arrives in time.
        let stale = [current?.end, upcoming.first?.start].compactMap { $0 }.min()
        let content = ActivityContent(state: state, staleDate: stale)
        if let a = running.first {
            guard a.content.state != state else { return }
            Task { await a.update(content) }
            for extra in running.dropFirst() { Task { await extra.end(nil, dismissalPolicy: .immediate) } }
        } else {
            let first = profile.map { $0.name.components(separatedBy: " ").first ?? $0.name } ?? ""
            _ = try? Activity.request(attributes: LessonAttributes(name: first), content: content)
        }
    }
}
