import Foundation
import Combine

final class Prefs: ObservableObject {
    static let shared = Prefs()
    /// Docs rendering uses a throwaway store with the default settings, so your own settings are untouched.
    private let d: UserDefaults = {
        guard CommandLine.arguments.contains("--render-docs") else { return .standard }
        let suite = "com.ottobigo.ViggoPlus.docs"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }()

    @Published var username: String { didSet { d.set(username, forKey: "username") } }
    @Published var panelNow: Bool { didSet { d.set(panelNow, forKey: "panelNow") } }
    @Published var panelTimeline: Bool { didSet { d.set(panelTimeline, forKey: "panelTimeline") } }
    @Published var panelTomorrow: Bool { didSet { d.set(panelTomorrow, forKey: "panelTomorrow") } }
    @Published var panelDuty: Bool { didSet { d.set(panelDuty, forKey: "panelDuty") } }
    @Published var panelHomework: Bool { didSet { d.set(panelHomework, forKey: "panelHomework") } }
    @Published var panelMessages: Bool { didSet { d.set(panelMessages, forKey: "panelMessages") } }
    @Published var panelHidePast: Bool { didSet { d.set(panelHidePast, forKey: "panelHidePast") } }
    @Published var panelLarge: Bool { didSet { d.set(panelLarge, forKey: "panelLarge") } }
    @Published var panelMsgCount: Int { didSet { d.set(panelMsgCount, forKey: "panelMsgCount") } }
    @Published var menubarBadge: Bool { didSet { d.set(menubarBadge, forKey: "menubarBadge") } }
    @Published var panelHomeworkTick: Bool { didSet { d.set(panelHomeworkTick, forKey: "panelHomeworkTick") } }
    @Published var friendsFreeTogether: Bool { didSet { d.set(friendsFreeTogether, forKey: "friendsFreeTogether") } }
    @Published var focusEnabled: Bool { didSet { d.set(focusEnabled, forKey: "focusEnabled") } }
    @Published var focusOnShortcut: String { didSet { d.set(focusOnShortcut, forKey: "focusOnShortcut") } }
    @Published var focusOffShortcut: String { didSet { d.set(focusOffShortcut, forKey: "focusOffShortcut") } }
    @Published var panelBirthdays: Bool { didSet { d.set(panelBirthdays, forKey: "panelBirthdays") } }
    @Published var notifyBirthdays: Bool { didSet { d.set(notifyBirthdays, forKey: "notifyBirthdays") } }
    @Published var hotkeyEnabled: Bool { didSet { d.set(hotkeyEnabled, forKey: "hotkeyEnabled") } }
    @Published var panelFriendsNow: Bool { didSet { d.set(panelFriendsNow, forKey: "panelFriendsNow") } }
    @Published var notifyBulletin: Bool { didSet { d.set(notifyBulletin, forKey: "notifyBulletin") } }
    @Published var panelBulletin: Bool { didSet { d.set(panelBulletin, forKey: "panelBulletin") } }
    @Published var autoUpdate: Bool { didSet { d.set(autoUpdate, forKey: "autoUpdate") } }
    @Published var hotkeyChoice: Int { didSet { d.set(hotkeyChoice, forKey: "hotkeyChoice") } }
    @Published var lessonNames: [String: String] { didSet { d.set(lessonNames, forKey: "lessonNames") } }
    @Published var lessonColors: [String: String] { didSet { d.set(lessonColors, forKey: "lessonColors") } }
    @Published var panelBreaks: Bool { didSet { d.set(panelBreaks, forKey: "panelBreaks") } }
    @Published var panelMeals: Bool { didSet { d.set(panelMeals, forKey: "panelMeals") } }
    @Published var menubarBreaks: Bool { didSet { d.set(menubarBreaks, forKey: "menubarBreaks") } }
    @Published var panelLunch: Bool { didSet { d.set(panelLunch, forKey: "panelLunch") } }
    @Published var customItems: [CustomItem] { didSet { d.set(try? JSONEncoder().encode(customItems), forKey: "customItems") } }
    @Published var dismissedVersion: String { didSet { d.set(dismissedVersion, forKey: "dismissedVersion") } }
    @Published var imported: Bool { didSet { d.set(imported, forKey: "imported") } }
    @Published var importSchedule: Bool { didSet { d.set(importSchedule, forKey: "importSchedule") } }
    @Published var importHomework: Bool { didSet { d.set(importHomework, forKey: "importHomework") } }
    @Published var importEvents: Bool { didSet { d.set(importEvents, forKey: "importEvents") } }
    @Published var showBirthdays: Bool { didSet { d.set(showBirthdays, forKey: "showBirthdays") } }
    @Published var menubarRoutine: Bool { didSet { d.set(menubarRoutine, forKey: "menubarRoutine") } }
    /// nil until the user picks; then the exact titles to show in the menubar after school.
    @Published var menubarItems: [String]? { didSet { d.set(menubarItems, forKey: "menubarItems") } }
    @Published var includedRoutines: [String] { didSet { d.set(includedRoutines, forKey: "includedRoutines") } }
    @Published var lessonAlarmMinutes: Int { didSet { d.set(lessonAlarmMinutes, forKey: "lessonAlarmMinutes") } }
    @Published var homeworkAlarm: Bool { didSet { d.set(homeworkAlarm, forKey: "homeworkAlarm") } }
    @Published var notifyChanges: Bool { didSet { d.set(notifyChanges, forKey: "notifyChanges") } }
    @Published var notifyHomework: Bool { didSet { d.set(notifyHomework, forKey: "notifyHomework") } }
    @Published var notifyMessages: Bool { didSet { d.set(notifyMessages, forKey: "notifyMessages") } }
    @Published var briefs: Bool { didSet { d.set(briefs, forKey: "briefs") } }
    @Published var morningHour: Int { didSet { d.set(morningHour, forKey: "morningHour") } }
    @Published var eveningHour: Int { didSet { d.set(eveningHour, forKey: "eveningHour") } }

    private init() {
        d.register(defaults: [
            "panelBirthdays": true, "panelLunch": true, "panelBreaks": true, "panelMeals": true, "menubarBreaks": false, "notifyBirthdays": true, "hotkeyEnabled": true, "panelFriendsNow": true, "notifyBulletin": true, "panelBulletin": false, "autoUpdate": true, "hotkeyChoice": 0, "dismissedVersion": "", "menubarBadge": true, "panelHomeworkTick": true, "friendsFreeTogether": true, "focusEnabled": false, "focusOnShortcut": "Viggo Fokus til", "focusOffShortcut": "Viggo Fokus fra", "panelNow": true, "panelTimeline": true, "panelTomorrow": true, "panelDuty": false, "panelHomework": true, "panelMessages": false, "panelHidePast": true, "panelLarge": false, "panelMsgCount": 3, "imported": false, "importSchedule": true, "importHomework": true,
            "importEvents": true, "menubarRoutine": true, "showBirthdays": false, "includedRoutines": [String](),
            "lessonAlarmMinutes": 10, "homeworkAlarm": true, "notifyChanges": true,
            "notifyHomework": true, "notifyMessages": true, "briefs": true,
            "morningHour": 7, "eveningHour": 20,
        ])
        username = d.string(forKey: "username") ?? ""
        panelNow = d.bool(forKey: "panelNow")
        panelTimeline = d.bool(forKey: "panelTimeline")
        panelTomorrow = d.bool(forKey: "panelTomorrow")
        panelDuty = d.bool(forKey: "panelDuty")
        panelHomework = d.bool(forKey: "panelHomework")
        panelMessages = d.bool(forKey: "panelMessages")
        panelHidePast = d.bool(forKey: "panelHidePast")
        panelLarge = d.bool(forKey: "panelLarge")
        panelMsgCount = d.integer(forKey: "panelMsgCount")
        menubarBadge = d.bool(forKey: "menubarBadge")
        panelHomeworkTick = d.bool(forKey: "panelHomeworkTick")
        friendsFreeTogether = d.bool(forKey: "friendsFreeTogether")
        focusEnabled = d.bool(forKey: "focusEnabled")
        focusOnShortcut = d.string(forKey: "focusOnShortcut") ?? "Viggo Fokus til"
        focusOffShortcut = d.string(forKey: "focusOffShortcut") ?? "Viggo Fokus fra"
        panelBirthdays = d.bool(forKey: "panelBirthdays")
        notifyBirthdays = d.bool(forKey: "notifyBirthdays")
        hotkeyEnabled = d.bool(forKey: "hotkeyEnabled")
        panelFriendsNow = d.bool(forKey: "panelFriendsNow")
        notifyBulletin = d.bool(forKey: "notifyBulletin")
        panelBulletin = d.bool(forKey: "panelBulletin")
        autoUpdate = d.bool(forKey: "autoUpdate")
        hotkeyChoice = d.integer(forKey: "hotkeyChoice")
        lessonNames = d.dictionary(forKey: "lessonNames") as? [String: String] ?? [:]
        lessonColors = d.dictionary(forKey: "lessonColors") as? [String: String] ?? [:]
        panelLunch = d.bool(forKey: "panelLunch")
        panelBreaks = d.bool(forKey: "panelBreaks")
        panelMeals = d.bool(forKey: "panelMeals")
        menubarBreaks = d.bool(forKey: "menubarBreaks")
        customItems = d.data(forKey: "customItems").flatMap { try? JSONDecoder().decode([CustomItem].self, from: $0) } ?? []
        dismissedVersion = d.string(forKey: "dismissedVersion") ?? ""
        imported = d.bool(forKey: "imported")
        importSchedule = d.bool(forKey: "importSchedule")
        importHomework = d.bool(forKey: "importHomework")
        importEvents = d.bool(forKey: "importEvents")
        showBirthdays = d.bool(forKey: "showBirthdays")
        menubarRoutine = d.bool(forKey: "menubarRoutine")
        menubarItems = d.stringArray(forKey: "menubarItems")
        includedRoutines = d.stringArray(forKey: "includedRoutines") ?? []
        lessonAlarmMinutes = d.integer(forKey: "lessonAlarmMinutes")
        homeworkAlarm = d.bool(forKey: "homeworkAlarm")
        notifyChanges = d.bool(forKey: "notifyChanges")
        notifyHomework = d.bool(forKey: "notifyHomework")
        notifyMessages = d.bool(forKey: "notifyMessages")
        briefs = d.bool(forKey: "briefs")
        morningHour = d.integer(forKey: "morningHour")
        eveningHour = d.integer(forKey: "eveningHour")
    }
}
