import AppIntents
import SwiftUI
import WidgetKit

struct HomeworkEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

struct HomeworkProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeworkEntry { HomeworkEntry(date: Date(), data: .homeworkSample) }
    func getSnapshot(in context: Context, completion: @escaping (HomeworkEntry) -> Void) {
        let d = WidgetStore.load()
        completion(HomeworkEntry(date: Date(), data: (d.homeworkItems ?? []).isEmpty && context.isPreview ? .homeworkSample : d))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeworkEntry>) -> Void) {
        // The app reloads this after every sync and every tick, so one entry is enough.
        let next = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400 + 60)
        completion(Timeline(entries: [HomeworkEntry(date: Date(), data: WidgetStore.load())], policy: .after(next)))
    }
}

extension WidgetData {
    static var homeworkSample: WidgetData {
        var d = WidgetData.sample
        let t = Date()
        d.homeworkItems = [
            WidgetHomework(id: 1, title: "Aflever stil om Blicher", subject: "Dansk", due: t.addingTimeInterval(86_400), done: false),
            WidgetHomework(id: 2, title: "Opgave 4.1 til 4.8", subject: "Matematik", due: t.addingTimeInterval(2 * 86_400), done: true),
            WidgetHomework(id: 3, title: "Læs kapitel 3", subject: "Engelsk", due: t.addingTimeInterval(3 * 86_400), done: false),
        ]
        return d
    }
}

struct HomeworkWidgetView: View {
    let family: WidgetFamily
    let entry: HomeworkEntry

    private var items: [WidgetHomework] {
        let all = entry.data.homeworkItems ?? []
        let limit = family == .systemLarge ? 8 : family == .systemMedium ? 3 : 3
        // Open homework first, then what you just ticked off (so you can undo it).
        return Array((all.filter { !$0.done } + all.filter(\.done)).prefix(limit))
    }

    private static let dayF: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "da_DK"); f.dateFormat = "EEE d/M"; return f
    }()
    private func due(_ d: Date) -> String {
        let c = Calendar.current
        if c.isDateInToday(d) { return "I dag" }
        if c.isDateInTomorrow(d) { return "I morgen" }
        return Self.dayF.string(from: d).capitalized
    }

    var body: some View {
        let open = (entry.data.homeworkItems ?? []).filter { !$0.done }.count
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            HStack {
                Image(systemName: "book.fill").foregroundStyle(.orange)
                Text("Lektier").font(.system(size: 15, weight: .bold))
                Spacer()
                if open > 0 {
                    Text("\(open)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(.orange))
                }
            }
            if entry.data.loggedOut {
                Spacer(); Text("Åbn Viggo+ og log ind").font(.footnote).foregroundStyle(.secondary); Spacer()
            } else if items.isEmpty {
                Spacer()
                HStack { Spacer(); VStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill").font(.title2).foregroundStyle(.green)
                    Text("Ingen lektier").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                }; Spacer() }
                Spacer()
            } else {
                ForEach(items) { h in row(h) }
                Spacer(minLength: 0)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func row(_ h: WidgetHomework) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Button(intent: ToggleHomeworkIntent(id: h.id, done: !h.done)) {
                Image(systemName: h.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: family == .systemSmall ? 18 : 20))
                    .foregroundStyle(h.done ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 0) {
                Text(h.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    .strikethrough(h.done).foregroundStyle(h.done ? .secondary : .primary)
                if family != .systemSmall {
                    Text(h.subject).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if family != .systemSmall {
                Text(due(h.due)).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Calendar.current.isDateInToday(h.due) || Calendar.current.isDateInTomorrow(h.due) ? .orange : .secondary)
            }
        }
    }
}

struct HomeworkWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ViggoHomework", provider: HomeworkProvider()) { HomeworkFamilyView(entry: $0) }
            .configurationDisplayName("Lektier")
            .description("Dine lektier. Tryk på cirklen for at markere en som færdig.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// Reads the widget size from the environment and hands it to the view.
struct HomeworkFamilyView: View {
    @Environment(\.widgetFamily) var family
    let entry: HomeworkEntry
    var body: some View { HomeworkWidgetView(family: family, entry: entry) }
}
