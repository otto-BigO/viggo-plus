import SwiftUI
import WidgetKit

// The Live Activity's views. The countdowns are Text(timerInterval:), which the system ticks
// by itself, so the activity only needs an update when the lesson changes.

private let liveHM: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
private func lhm(_ d: Date) -> String { liveHM.string(from: d) }

func liveColor(_ i: WidgetItem) -> Color {
    if let h = i.color, let c = Color(widgetHex: h) { return c }
    switch i.kind {
    case "lesson": return .blue
    case "event": return .orange
    case "custom": return .green
    default: return .gray
    }
}

/// What to show as the main item. When the activity went stale (the lesson ended and no
/// update came yet), the next item is the best guess.
struct LiveMain {
    let item: WidgetItem?
    let isNow: Bool
    init(_ s: LessonAttributes.ContentState, stale: Bool) {
        if let c = s.current, !stale { item = c; isNow = true } else { item = s.next ?? s.current; isNow = false }
    }
}

struct LiveLockView: View {
    let state: LessonAttributes.ContentState
    let stale: Bool

    var body: some View {
        let m = LiveMain(state, stale: stale)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(m.item.map(liveColor) ?? .gray).frame(width: 4, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.isNow ? (m.item?.isPause == true ? "PAUSE" : "NU") : "NÆSTE")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    Text(m.item?.title ?? "Fri").font(.system(size: 18, weight: .bold)).lineLimit(1)
                    if let r = m.item?.room, !r.isEmpty {
                        Text(r).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                if let i = m.item {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(timerInterval: (m.isNow ? i.start : Date())...(m.isNow ? i.end : max(Date(), i.start)), countsDown: true)
                            .font(.system(size: 22, weight: .semibold).monospacedDigit())
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 90, alignment: .trailing)
                        Text(m.isNow ? "til \(lhm(i.end))" : "kl. \(lhm(i.start))").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            if m.isNow, let i = m.item {
                ProgressView(timerInterval: i.start...i.end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(liveColor(i))
            }
            if m.isNow, let n = state.next {
                HStack(spacing: 4) {
                    Text("Derefter").foregroundStyle(.secondary)
                    Text(n.title).fontWeight(.medium).lineLimit(1)
                    Spacer()
                    Text(lhm(n.start)).foregroundStyle(.secondary).monospacedDigit()
                }
                .font(.system(size: 12))
            }
        }
        .padding(14)
    }
}

struct LiveExpandedBottom: View {
    let state: LessonAttributes.ContentState
    let stale: Bool
    var body: some View {
        let m = LiveMain(state, stale: stale)
        VStack(spacing: 6) {
            if m.isNow, let i = m.item {
                ProgressView(timerInterval: i.start...i.end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(liveColor(i))
            }
            let rest = (m.isNow ? [state.next].compactMap { $0 } : []) + state.later
            ForEach(Array(rest.prefix(2)), id: \.self) { n in
                HStack {
                    Circle().fill(liveColor(n)).frame(width: 6, height: 6)
                    Text(n.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Spacer()
                    Text(lhm(n.start)).font(.system(size: 13).monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct LiveCountdown: View {
    let state: LessonAttributes.ContentState
    let stale: Bool
    var body: some View {
        let m = LiveMain(state, stale: stale)
        if let i = m.item {
            Text(timerInterval: (m.isNow ? i.start : Date())...(m.isNow ? i.end : max(Date(), i.start)), countsDown: true)
                .monospacedDigit()
        }
    }
}
