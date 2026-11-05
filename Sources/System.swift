import Foundation
import Security
import LocalAuthentication
import UserNotifications
import EventKit
import AppKit

enum Keychain {
    private static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Config.bundleID,
         kSecAttrAccount as String: account]
    }
    @discardableResult
    static func save(_ password: String, account: String) -> Bool {
        SecItemDelete(base(account) as CFDictionary)
        var q = base(account)
        q[kSecValueData as String] = Data(password.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
    static func load(account: String) -> String? {
        var q = base(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func delete(account: String) { SecItemDelete(base(account) as CFDictionary) }
}

enum Biometrics {
    static func unlock(reason: String) async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return true }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    func setup() {
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        c.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
    func post(_ title: String, _ body: String, url: URL? = nil) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        if let url { c.userInfo = ["url": url.absoluteString] }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let s = response.notification.request.content.userInfo["url"] as? String, let u = URL(string: s) {
            NSWorkspace.shared.open(u)
        }
        completionHandler()
    }
}

struct CalItem {
    let key: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let location: String?
    let notes: String?
    let alarms: [EKAlarm]
}

final class CalendarSync {
    let store = EKEventStore()

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    func calendar(named name: String, color: NSColor) throws -> EKCalendar {
        if let c = store.calendars(for: .event).first(where: { $0.title == name }) { return c }
        let c = EKCalendar(for: .event, eventStore: store)
        c.title = name
        c.color = color
        let icloud = store.sources.first { $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("icloud") }
        guard let src = icloud ?? store.defaultCalendarForNewEvents?.source
                ?? store.sources.first(where: { $0.sourceType == .local }) else {
            throw ViggoError.unexpected("Ingen kalenderkonto fundet")
        }
        c.source = src
        try store.saveCalendar(c, commit: true)
        return c
    }

    func existing(named name: String) -> EKCalendar? {
        store.calendars(for: .event).first { $0.title == name }
    }

    func remove(named name: String) throws {
        for c in store.calendars(for: .event) where c.title == name && c.allowsContentModifications {
            try store.removeCalendar(c, commit: true)
        }
    }

    private func sig(_ a: [EKAlarm]?) -> String {
        (a ?? []).map { al in al.absoluteDate.map { "a\(Int($0.timeIntervalSince1970))" } ?? "r\(Int(al.relativeOffset))" }
            .sorted().joined(separator: ",")
    }

    @discardableResult
    func sync(_ items: [CalItem], into cal: EKCalendar, from: Date, to: Date) throws -> Int {
        var existing: [String: EKEvent] = [:]
        var changes = 0
        for ev in store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: [cal])) {
            guard let k = ev.url?.host else { continue }
            if existing[k] != nil { try store.remove(ev, span: .thisEvent, commit: false); changes += 1 } else { existing[k] = ev }
        }
        let wanted = Set(items.map(\.key))
        for item in items {
            let isNew = existing[item.key] == nil
            let ev = existing[item.key] ?? EKEvent(eventStore: store)
            if isNew {
                ev.calendar = cal
                ev.url = URL(string: "viggoplus://\(item.key)")
            }
            let differs = isNew || ev.title != item.title || ev.isAllDay != item.allDay
                || (!item.allDay && (ev.startDate != item.start || ev.endDate != item.end))
                || (ev.location ?? "") != (item.location ?? "") || (ev.notes ?? "") != (item.notes ?? "")
                || sig(ev.alarms) != sig(item.alarms)
            if differs {
                ev.title = item.title
                ev.isAllDay = item.allDay
                ev.startDate = item.start
                ev.endDate = item.end
                ev.location = item.location
                ev.notes = item.notes
                ev.alarms = item.alarms
                try store.save(ev, span: .thisEvent, commit: false)
                changes += 1
            }
        }
        for (k, ev) in existing where !wanted.contains(k) {
            try store.remove(ev, span: .thisEvent, commit: false)
            changes += 1
        }
        if changes > 0 { try store.commit() }
        return changes
    }
}

struct EventSnap: Codable, Equatable {
    let title: String
    let start: Date
    let end: Date
    let room: String
}

struct Snapshot: Codable {
    var events: [String: EventSnap] = [:]
    var homeworkIDs: Set<Int> = []
    var messageIDs: Set<Int> = []
    var lastMorningBrief = ""
    var lastEveningBrief = ""
    var initialized = false

    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ViggoPlus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }
    static func load() -> Snapshot {
        (try? JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))) ?? Snapshot()
    }
    func save() { try? JSONEncoder().encode(self).write(to: Snapshot.url, options: .atomic) }
}

/// Keeps Viggo sessions across app restarts (session cookies are dropped otherwise).
enum CookieJar {
    static var dir: URL { Snapshot.url.deletingLastPathComponent() }
    static var url: URL { dir.appendingPathComponent("session.plist") }
    static func friendURL(_ id: UUID) -> URL {
        let d = dir.appendingPathComponent("friends", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("\(id.uuidString).plist")
    }

    static func write(_ cookies: [HTTPCookie], to url: URL) {
        let props = cookies.filter { $0.domain.contains("viggo.dk") }.compactMap { c -> [String: Any]? in
            guard let p = c.properties else { return nil }
            return Dictionary(uniqueKeysWithValues: p.map { ($0.key.rawValue, $0.value) })
        }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: props, format: .binary, options: 0) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func read(_ url: URL) -> [HTTPCookie] {
        guard let data = try? Data(contentsOf: url),
              let arr = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            HTTPCookie(properties: Dictionary(uniqueKeysWithValues: d.map { (HTTPCookiePropertyKey($0.key), $0.value) }))
        }
    }

    static func save() { write(HTTPCookieStorage.shared.cookies ?? [], to: url) }
    static func restore() { read(url).forEach { HTTPCookieStorage.shared.setCookie($0) } }
    static func clear() { try? FileManager.default.removeItem(at: url) }
}

struct Friend: Codable, Identifiable, Equatable {
    let id: UUID
    var viggoID: Int
    var name: String
    var image: URL?
    var savedUsername: String?
    var loginVerified: Bool? = nil
    var savedUntil: Date? = nil
    var keychainAccount: String { "friend-\(id.uuidString)" }
    var firstName: String { name.components(separatedBy: " ").first ?? name }
}
