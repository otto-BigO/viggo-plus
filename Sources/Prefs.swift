import Foundation
import Combine

final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    @Published var username: String { didSet { d.set(username, forKey: "username") } }
    @Published var hasPassword: Bool { didSet { d.set(hasPassword, forKey: "hasPassword") } }
    @Published var loginDays: Int { didSet { d.set(loginDays, forKey: "loginDays") } }
    @Published var mainLoginUntil: Date? { didSet { d.set(mainLoginUntil, forKey: "mainLoginUntil") } }
    @Published var useTouchID: Bool { didSet { d.set(useTouchID, forKey: "useTouchID") } }
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
            "useTouchID": true, "loginDays": 30, "imported": false, "importSchedule": true, "importHomework": true,
            "importEvents": true, "menubarRoutine": true, "showBirthdays": false, "includedRoutines": [String](),
            "lessonAlarmMinutes": 10, "homeworkAlarm": true, "notifyChanges": true,
            "notifyHomework": true, "notifyMessages": true, "briefs": true,
            "morningHour": 7, "eveningHour": 20,
        ])
        username = d.string(forKey: "username") ?? ""
        hasPassword = d.bool(forKey: "hasPassword")
        useTouchID = d.bool(forKey: "useTouchID")
        loginDays = d.integer(forKey: "loginDays")
        mainLoginUntil = d.object(forKey: "mainLoginUntil") as? Date
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
