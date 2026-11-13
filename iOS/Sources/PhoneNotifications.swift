import BackgroundTasks
import Foundation
import UserNotifications

/// The iPhone app is not running most of the time, so everything that happens at a known
/// time (lesson reminders, the morning and evening brief, birthdays) is handed to iOS ahead
/// of time. Changes, new homework and messages are found by a background refresh instead.
extension AppState {
    static let refreshTask = (Bundle.main.bundleIdentifier ?? "com.ottobigo.viggoplus.ios") + ".refresh"
    private static let prefix = "vp-"

    func scheduleAhead() {
        let c = UNUserNotificationCenter.current()
        let now = Date(), today = DateUtil.startOfDay(now)
        var list: [(Date, String, String, String)] = []   // fire date, id, title, body

        for n in 0..<7 {
            let day = DateUtil.add(.day, n, today)
            let key = DateUtil.ymd(day)
            if prefs.lessonAlarmMinutes > 0 {
                for e in items(on: day) where e.kind == .lesson || e.kind == .event {
                    let at = e.start.addingTimeInterval(TimeInterval(-prefs.lessonAlarmMinutes * 60))
                    list.append((at, "lesson-\(e.key)", "\(e.title) om \(prefs.lessonAlarmMinutes) min",
                                 "\(DateUtil.hm(e.start))–\(DateUtil.hm(e.end))\(e.room.isEmpty ? "" : " · \(e.room)")"))
                }
            }
            if prefs.briefs, !events.isEmpty {
                if let at = DateUtil.cal.date(bySettingHour: prefs.morningHour, minute: 0, second: 0, of: day) {
                    list.append((at, "morning-\(key)", "God morgen ☀️", brief(for: day, prefix: "I dag")))
                }
                if let at = DateUtil.cal.date(bySettingHour: prefs.eveningHour, minute: 0, second: 0, of: day) {
                    list.append((at, "evening-\(key)", "I morgen 🌙", brief(for: DateUtil.add(.day, 1, day), prefix: "I morgen")))
                }
            }
            if prefs.notifyBirthdays {
                let names = events.filter { $0.kind == .birthday && DateUtil.cal.isDate($0.start, inSameDayAs: day) }.map(\.birthdayName)
                if !names.isEmpty, let at = DateUtil.cal.date(bySettingHour: prefs.morningHour, minute: 1, second: 0, of: day) {
                    list.append((at, "birthday-\(key)", "🎂 Fødselsdag i dag", names.joined(separator: ", ")))
                }
            }
        }
        // For checking from Terminal: VIGGO_TEST_SOON=1 adds one that goes off in about a minute.
        if ProcessInfo.processInfo.environment["VIGGO_TEST_SOON"] != nil {
            list.append((now.addingTimeInterval(65), "test", "Viggo+ planlagt test", "Denne blev planlagt på forhånd"))
        }
        // iOS keeps at most 64 waiting notifications per app; the soonest ones matter most.
        let upcoming = list.filter { $0.0 > now }.sorted { $0.0 < $1.0 }.prefix(60)
        c.getPendingNotificationRequests { pending in
            let old = pending.map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
            c.removePendingNotificationRequests(withIdentifiers: old)
            for (at, id, title, body) in upcoming {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                let comps = DateUtil.cal.dateComponents([.year, .month, .day, .hour, .minute], from: at)
                c.add(UNNotificationRequest(identifier: Self.prefix + id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
            }
            // For checking from Terminal: VIGGO_DUMP_PENDING=1 prints what is waiting.
            if ProcessInfo.processInfo.environment["VIGGO_DUMP_PENDING"] != nil {
                for (at, id, title, body) in upcoming { print("[venter] \(at.formatted(date: .abbreviated, time: .shortened)) \(id) | \(title) | \(body)") }
            }
        }
    }

    /// Asks iOS to wake the app now and then to sync. iOS decides when; usually every hour or so.
    func scheduleRefresh() {
        let r = BGAppRefreshTaskRequest(identifier: Self.refreshTask)
        r.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(r)
    }

    /// Runs when iOS wakes the app in the background.
    func backgroundRefresh() async {
        print("[baggrund] synker")
        CookieJar.restore()
        await sync()
        await PhoneUpdate.shared.check()
        print("[baggrund] færdig, \(events.count) punkter, synket \(lastSync.map(DateUtil.hm) ?? "-")")
        scheduleRefresh()
    }
}
