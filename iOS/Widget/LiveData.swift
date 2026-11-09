import ActivityKit
import Foundation

/// The Live Activity during school: what runs now, what comes next and a few after that.
struct LessonAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var current: WidgetItem?
        var next: WidgetItem?
        var later: [WidgetItem]
    }
    var name: String
}
