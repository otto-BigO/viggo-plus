import SwiftUI
import WidgetKit

struct BirthdayEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

struct BirthdayProvider: TimelineProvider {
    func placeholder(in context: Context) -> BirthdayEntry { BirthdayEntry(date: Date(), data: .birthdaySample) }
    func getSnapshot(in context: Context, completion: @escaping (BirthdayEntry) -> Void) {
        let d = WidgetStore.load()
        completion(BirthdayEntry(date: Date(), data: (d.birthdays ?? []).isEmpty && context.isPreview ? .birthdaySample : d))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<BirthdayEntry>) -> Void) {
        // One entry per day for a week, so "om 3 dage" counts down even if the app is not opened.
        let today = Calendar.current.startOfDay(for: Date())
        let d = WidgetStore.load()
        let entries = (0..<7).map { BirthdayEntry(date: $0 == 0 ? Date() : today.addingTimeInterval(Double($0) * 86_400 + 60), data: d) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

extension WidgetData {
    /// Made-up people, for the widget gallery and screenshots.
    static var birthdaySample: WidgetData {
        var d = WidgetData.sample
        let today = Calendar.current.startOfDay(for: Date())
        let names = [("Alma Jensen", 0, 17), ("Noah Larsen", 2, 16), ("Freja Holm", 5, 17), ("Oscar Berg", 9, 16), ("Ida Krogh", 14, 17), ("Karl Dahl", 21, 16)]
        d.birthdays = names.enumerated().map { i, n in
            WidgetBirthday(id: i, name: n.0, date: today.addingTimeInterval(Double(n.1) * 86_400), turns: n.2, from: i % 2 == 0 ? "Klasse 10.3" : "Musiklinjen")
        }
        return d
    }
}

struct BirthdayWidgetView: View {
    let family: WidgetFamily
    let entry: BirthdayEntry

    private var list: [WidgetBirthday] {
        let today = Calendar.current.startOfDay(for: entry.date)
        return (entry.data.birthdays ?? []).filter { $0.date >= today }
    }

    private func days(_ b: WidgetBirthday) -> Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: entry.date), to: b.date).day ?? 0
    }

    private static let dayF: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "da_DK"); f.dateFormat = "EEE d/M"; return f
    }()

    private func when(_ b: WidgetBirthday) -> String {
        switch days(b) {
        case 0: return "I dag 🎉"
        case 1: return "I morgen"
        case 2...6: return Self.dayF.string(from: b.date).capitalized
        case let n: return "Om \(n) dage"
        }
    }

    private static let palette: [Color] = [.pink, .purple, .orange, .teal, .indigo, .blue]

    private func bubble(_ b: WidgetBirthday, size: CGFloat) -> some View {
        Circle().fill(Self.palette[abs(b.id) % Self.palette.count].gradient)
            .overlay(Text(b.initials).font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(.white))
            .frame(width: size, height: size)
    }

    var body: some View {
        Group {
            if entry.data.loggedOut || list.isEmpty {
                VStack(spacing: 6) {
                    Text("🎂").font(.title)
                    Text(entry.data.loggedOut ? "Åbn Viggo+ og log ind" : "Åbn Viggo+, så den kan hente fødselsdage")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if family == .systemSmall {
                small(list[0])
            } else {
                rows
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func small(_ b: WidgetBirthday) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("🎂").font(.system(size: 15))
                Text("Fødselsdag").font(.system(size: 13, weight: .bold))
            }
            Spacer(minLength: 0)
            bubble(b, size: 38)
            Text(b.firstName).font(.system(size: 18, weight: .bold)).lineLimit(1)
            Text("Fylder \(b.turns) · \(when(b))").font(.system(size: 12, weight: .medium))
                .foregroundStyle(days(b) <= 1 ? .pink : .secondary).lineLimit(1)
            if list.count > 1 {
                Text("Så \(list[1].firstName), \(when(list[1]).lowercased())").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rows: some View {
        let limit = family == .systemLarge ? 8 : 3
        return VStack(alignment: .leading, spacing: family == .systemLarge ? 9 : 7) {
            HStack {
                Text("🎂").font(.system(size: 15))
                Text("Næste fødselsdage").font(.system(size: 15, weight: .bold))
                Spacer()
            }
            ForEach(list.prefix(limit)) { b in
                HStack(spacing: 9) {
                    bubble(b, size: 26)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(b.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text("Fylder \(b.turns) · \(b.from)").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(when(b)).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(days(b) <= 1 ? .pink : .secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct BirthdayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ViggoBirthdays", provider: BirthdayProvider()) { BirthdayFamilyView(entry: $0) }
            .configurationDisplayName("Fødselsdage")
            .description("De næste fødselsdage i din klasse og på din linje.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct BirthdayFamilyView: View {
    @Environment(\.widgetFamily) var family
    let entry: BirthdayEntry
    var body: some View { BirthdayWidgetView(family: family, entry: entry) }
}
