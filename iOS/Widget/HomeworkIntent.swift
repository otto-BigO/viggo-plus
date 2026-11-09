import AppIntents
import WidgetKit

/// The tick button in the homework widget. As a LiveActivityIntent it runs inside the app
/// (started in the background), which has your Viggo login; the widget itself has none.
struct ToggleHomeworkIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Markér lektie"
    static var isDiscoverable = false

    @Parameter(title: "Lektie") var id: Int
    @Parameter(title: "Færdig") var done: Bool

    init() {}
    init(id: Int, done: Bool) { self.id = id; self.done = done }

    func perform() async throws -> some IntentResult {
        #if !WIDGET
        await AppState.shared.setHomeworkFromWidget(id, done: done)
        #endif
        return .result()
    }
}
