import SwiftUI
import WidgetKit

struct Entry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

extension WidgetData {
    static var sample: WidgetData {
        let c = Calendar.current, t = Date()
        func at(_ m: Int) -> Date { c.date(byAdding: .minute, value: m, to: t)! }
        return WidgetData(name: "Otto", items: [
            WidgetItem(title: "Matematik", start: at(-20), end: at(25), room: "Klasse 2", kind: "lesson", color: nil),
            WidgetItem(title: "Dansk", start: at(35), end: at(95), room: "Klasse 2", kind: "lesson", color: nil),
            WidgetItem(title: "Middag", start: at(100), end: at(150), room: "Spisesalen", kind: "routine", color: nil),
        ], homework: 2, updated: t, loggedOut: false)
    }
}

private let hmF: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
private func hm(_ d: Date) -> String { hmF.string(from: d) }

private func itemColor(_ i: WidgetItem) -> Color {
    if let h = i.color, let c = Color(widgetHex: h) { return c }
    switch i.kind {
    case "lesson": return .accentColor
    case "event": return .purple
    case "custom": return .green
    default: return .gray
    }
}

extension Color {
    init?(widgetHex: String) {
        var s = widgetHex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
}

/// "I morgen 08:15" when the next item is on another day, else "kl. 10:05".
private func when(_ i: WidgetItem, from t: Date) -> String {
    let c = Calendar.current
    if c.isDate(i.start, inSameDayAs: t) { return "kl. \(hm(i.start))" }
    if let tm = c.date(byAdding: .day, value: 1, to: t), c.isDate(i.start, inSameDayAs: tm) { return "i morgen \(hm(i.start))" }
    return i.start.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "da_DK"))) + " \(hm(i.start))"
}

// MARK: - Views

struct WidgetView: View {
    let family: WidgetFamily
    let entry: Entry

    var body: some View {
        let (cur, next, later) = entry.data.now(entry.date)
        Group {
            if entry.data.loggedOut || entry.data.items.isEmpty {
                empty
            } else {
                switch family {
                case .systemMedium: medium(cur, next, later)
                case .accessoryRectangular: rectangular(cur, next)
                case .accessoryInline: inline(cur, next)
                case .accessoryCircular: circular(cur, next)
                default: small(cur, next)
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "graduationcap.fill").foregroundStyle(.tint)
            Text(entry.data.loggedOut ? "Logget ud" : "Åbn Viggo+").font(.headline)
            Text(entry.data.loggedOut ? "Åbn appen og log ind" : "for at hente dit skema").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
    }

    @ViewBuilder private func nowBlock(_ cur: WidgetItem?, _ next: WidgetItem?, big: Bool) -> some View {
        if let c = cur {
            label(c.isPause ? "Pause" : "Nu")
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(itemColor(c)).frame(width: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.title).font(.system(size: big ? 19 : 17, weight: .bold)).lineLimit(2).minimumScaleFactor(0.8)
                    HStack(spacing: 3) {
                        Text(timerInterval: entry.date...c.end, countsDown: true).monospacedDigit()
                        Text("tilbage")
                    }
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        } else if let n = next {
            label("Fri")
            Text(n.title).font(.system(size: big ? 19 : 17, weight: .bold)).lineLimit(2).minimumScaleFactor(0.8)
            Text(when(n, from: entry.date)).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
        }
    }

    private func small(_ cur: WidgetItem?, _ next: WidgetItem?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            nowBlock(cur, next, big: false)
            Spacer(minLength: 2)
            if cur != nil, let n = next {
                label("Derefter")
                Text(n.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(when(n, from: entry.date)).font(.system(size: 11)).foregroundStyle(.secondary)
            } else if entry.data.homework > 0 {
                Label("\(entry.data.homework) lektier", systemImage: "book.closed").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func medium(_ cur: WidgetItem?, _ next: WidgetItem?, _ later: [WidgetItem]) -> some View {
        let list = ((cur == nil ? [] : [next].compactMap { $0 }) + later)
            .filter { Calendar.current.isDate($0.start, inSameDayAs: next?.start ?? entry.date) }.prefix(4)
        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                nowBlock(cur, next, big: true)
                Spacer(minLength: 0)
                if entry.data.homework > 0 {
                    Label("\(entry.data.homework) lektier", systemImage: "book.closed").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 5) {
                if !list.isEmpty { label(cur == nil ? "Bagefter" : "Resten af dagen") }
                ForEach(Array(list), id: \.self) { i in
                    HStack(spacing: 6) {
                        Text(hm(i.start)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 1).fill(itemColor(i)).frame(width: 2, height: 12)
                        Text(i.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder private func rectangular(_ cur: WidgetItem?, _ next: WidgetItem?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let c = cur {
                Text(c.title).font(.headline).lineLimit(1)
                HStack(spacing: 3) {
                    Text("slutter om")
                    Text(timerInterval: entry.date...c.end, countsDown: true).monospacedDigit()
                }
                .font(.caption)
                if let n = next { Text("\(n.title) \(when(n, from: entry.date))").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            } else if let n = next {
                Text("Fri").font(.caption).foregroundStyle(.secondary)
                Text(n.title).font(.headline).lineLimit(1)
                Text(when(n, from: entry.date)).font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func inline(_ cur: WidgetItem?, _ next: WidgetItem?) -> some View {
        if let c = cur { Text("\(c.title) → \(hm(c.end))") }
        else if let n = next { Text("\(n.title) \(when(n, from: entry.date))") }
    }

    @ViewBuilder private func circular(_ cur: WidgetItem?, _ next: WidgetItem?) -> some View {
        if let c = cur {
            // The provider adds an entry every few minutes, so the ring moves along.
            let left = c.end.timeIntervalSince(entry.date), total = max(1, c.end.timeIntervalSince(c.start))
            Gauge(value: max(0, min(1, left / total))) {
                EmptyView()
            } currentValueLabel: {
                Text("\(max(0, Int((left / 60).rounded(.up))))").font(.system(size: 16, weight: .semibold))
            }
            .gaugeStyle(.accessoryCircularCapacity)
        } else if let n = next {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "graduationcap.fill").font(.system(size: 10))
                    Text(hm(n.start)).font(.system(size: 12, weight: .semibold))
                }
            }
        }
    }
}

