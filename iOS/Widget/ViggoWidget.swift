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
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct LessonLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LessonAttributes.self) { ctx in
            LiveLockView(state: ctx.state, stale: ctx.isStale)
                .activityBackgroundTint(nil)
        } dynamicIsland: { ctx in
            let m = LiveMain(ctx.state, stale: ctx.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(m.isNow ? (m.item?.isPause == true ? "PAUSE" : "NU") : "NÆSTE")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        Text(m.item?.title ?? "Fri").font(.system(size: 16, weight: .bold)).lineLimit(1)
                    }
                    .padding(.leading, 6).padding(.top, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveCountdown(state: ctx.state, stale: ctx.isStale)
                        .font(.system(size: 20, weight: .semibold))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80, alignment: .trailing)
                        .padding(.trailing, 6).padding(.top, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    LiveExpandedBottom(state: ctx.state, stale: ctx.isStale).padding(.horizontal, 4)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Circle().fill(m.item.map(liveColor) ?? .gray).frame(width: 7, height: 7)
                    Text(m.item?.title ?? "Fri").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        .frame(maxWidth: 70, alignment: .leading)
                }
            } compactTrailing: {
                LiveCountdown(state: ctx.state, stale: ctx.isStale)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: 46)
            } minimal: {
                Image(systemName: "graduationcap.fill").foregroundStyle(m.item.map(liveColor) ?? .gray)
            }
        }
    }
}

@main
struct ViggoWidgets: WidgetBundle {
    var body: some Widget {
        NowWidget()
        LessonLiveActivity()
        ViggoControl()
        HomeworkWidget()
    }
}

/// Reads the widget size from the environment and hands it to the view.
struct FamilyView: View {
    @Environment(\.widgetFamily) var family
    let entry: Entry
    var body: some View { WidgetView(family: family, entry: entry) }
}
