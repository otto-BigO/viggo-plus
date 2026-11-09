import AppIntents

/// Opens Viggo+ on a tab. Used by the Control Center button and Shortcuts.
/// Compiled into both the app and the widget, as iOS needs for intents that open the app.
struct OpenViggoIntent: AppIntent {
    static var title: LocalizedStringResource = "Åbn Viggo+"
    static var description = IntentDescription("Åbner Viggo+ på I dag.")
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult { .result() }
}
