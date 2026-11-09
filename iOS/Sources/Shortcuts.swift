import AppIntents

/// Siri and Shortcuts: ask what you have now, when you are done, about homework and tomorrow.
/// They answer from the same data as the widgets, so they work without opening the app.
struct WhatNowIntent: AppIntent {
    static var title: LocalizedStringResource = "Hvad har jeg nu?"
    static var description = IntentDescription("Fortæller hvilken time du har nu, og hvad der kommer bagefter.")
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let s = WidgetStore.load().sayNow(Date())
        return .result(value: s, dialog: IntentDialog(stringLiteral: s))
    }
}

struct WhenFreeIntent: AppIntent {
    static var title: LocalizedStringResource = "Hvornår har jeg fri?"
    static var description = IntentDescription("Fortæller hvornår din sidste time i dag slutter.")
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let s = WidgetStore.load().sayFree(Date())
        return .result(value: s, dialog: IntentDialog(stringLiteral: s))
    }
}

struct HomeworkIntent: AppIntent {
    static var title: LocalizedStringResource = "Hvilke lektier har jeg?"
    static var description = IntentDescription("Læser dine åbne lektier op.")
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let s = WidgetStore.load().sayHomework()
        return .result(value: s, dialog: IntentDialog(stringLiteral: s))
    }
}

struct TomorrowIntent: AppIntent {
    static var title: LocalizedStringResource = "Hvad har jeg i morgen?"
    static var description = IntentDescription("Fortæller hvad du starter med i morgen.")
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let d = WidgetStore.load()
        let s = d.missing ?? d.sayTomorrow(Date()) ?? "Du har ingenting i skemaet i morgen."
        return .result(value: s, dialog: IntentDialog(stringLiteral: s))
    }
}

struct ViggoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: WhatNowIntent(), phrases: [
            "Hvad har jeg nu i \(.applicationName)",
            "Hvad har jeg nu \(.applicationName)",
            "\(.applicationName) nu",
        ], shortTitle: "Hvad har jeg nu?", systemImageName: "graduationcap.fill")
        AppShortcut(intent: WhenFreeIntent(), phrases: [
            "Hvornår har jeg fri i \(.applicationName)",
            "Hvornår har jeg fri \(.applicationName)",
        ], shortTitle: "Hvornår har jeg fri?", systemImageName: "figure.walk")
        AppShortcut(intent: HomeworkIntent(), phrases: [
            "Hvilke lektier har jeg i \(.applicationName)",
            "Lektier i \(.applicationName)",
        ], shortTitle: "Lektier", systemImageName: "book.fill")
        AppShortcut(intent: StartLiveIntent(), phrases: [
            "Vis skoledagen i \(.applicationName)",
            "Start skoledagen i \(.applicationName)",
            "\(.applicationName) skoledag",
        ], shortTitle: "Vis skoledagen", systemImageName: "clock.badge.fill")
        AppShortcut(intent: TomorrowIntent(), phrases: [
            "Hvad har jeg i morgen i \(.applicationName)",
        ], shortTitle: "I morgen", systemImageName: "sunrise.fill")
    }
}
