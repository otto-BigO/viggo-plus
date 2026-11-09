import SwiftUI
import WidgetKit

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), data: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let d = WidgetStore.load()
        completion(Entry(date: Date(), data: d.items.isEmpty ? .sample : d))
    }
    /// One entry now and one at every start and end, so the widget flips to the next lesson on time.
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let d = WidgetStore.load()
        let now = Date()
        // Every start and end, plus every 5 minutes for the next few hours so the lock screen ring moves.
        let soon = now.addingTimeInterval(4 * 3600)
        let ticks = stride(from: 300.0, to: soon.timeIntervalSince(now), by: 300).map { now.addingTimeInterval($0) }
        let edges = Set(d.items.flatMap { [$0.start, $0.end] }.filter { $0 > now && $0 < soon } + ticks).sorted()
        let entries = [Entry(date: now, data: d)] + edges.map { Entry(date: $0, data: d) }
        // Ask again in a few hours anyway; the app also reloads the widgets after every sync.
        completion(Timeline(entries: entries, policy: .after(soon)))
    }
}

// MARK: - Widgets

struct NowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ViggoNow", provider: Provider()) { FamilyView(entry: $0) }
            .configurationDisplayName("Nu og næste")
            .description("Hvad du har nu, hvor længe der er tilbage, og hvad der kommer bagefter.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

@main
struct ViggoWidgets: WidgetBundle {
    var body: some Widget { NowWidget() }
}

/// Reads the widget size from the environment and hands it to the view.
struct FamilyView: View {
    @Environment(\.widgetFamily) var family
    let entry: Entry
    var body: some View { WidgetView(family: family, entry: entry) }
}
