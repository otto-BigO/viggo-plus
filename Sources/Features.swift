import AppKit
import SwiftUI
import Carbon

// MARK: - Global hotkey

final class HotKey {
    static let shared = HotKey()
    static let choices: [(label: String, mods: UInt32)] = [
        ("⌥ V", UInt32(optionKey)), ("⌃ ⌥ V", UInt32(controlKey | optionKey)), ("⌥ ⇧ V", UInt32(optionKey | shiftKey)),
    ]
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: (() -> Void)?

    func register(choice: Int) {
        unregister()
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKey.shared.action?() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let mods = HotKey.choices[max(0, min(choice, HotKey.choices.count - 1))].mods
        RegisterEventHotKey(UInt32(kVK_ANSI_V), mods, EventHotKeyID(signature: OSType(0x5650_4C53), id: 1),
                            GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
    }

    /// Opens or closes the panel.
    @MainActor static func togglePanel() { PanelController.shared.toggle() }
}

// MARK: - Week overview

struct WeekView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var p = Prefs.shared
    @State private var offset = 0
    @State private var person: UUID?

    private var monday: Date { DateUtil.add(.weekOfYear, offset, DateUtil.mondayOf(Date())) }
    private var events: [ViggoEvent] { person.flatMap { state.friendEvents[$0] } ?? state.events }
    private var homework: [Homework] { person.flatMap { state.friendHomework[$0] } ?? state.homework }
    private var range: ClosedRange<Int> { person == nil ? -Config.weeksBack...Config.weeksAhead : 0...1 }

    private func dayItems(_ d: Date) -> [ViggoEvent] { state.weekItems(d, person: person) }

    var body: some View {
        let days = (0..<7).map { DateUtil.add(.day, $0, monday) }
        let shown = days   // always the whole week, weekend included
        let week = DateUtil.cal.component(.weekOfYear, from: monday)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Uge \(week)").font(.system(size: 20, weight: .bold))
                Text("\(DateUtil.day(monday)) – \(DateUtil.day(DateUtil.add(.day, 6, monday)))")
                    .foregroundStyle(.secondary)
                Spacer()
                if !state.friends.isEmpty {
                    Picker("", selection: $person) {
                        Text("Mig").tag(UUID?.none)
                        ForEach(state.friends) { f in Text(f.firstName).tag(UUID?.some(f.id)) }
                    }
                    .labelsHidden().fixedSize()
                    .onChange(of: person) { offset = max(range.lowerBound, min(offset, range.upperBound)) }
                }
                Button { offset -= 1 } label: { Image(systemName: "chevron.left") }.disabled(offset <= range.lowerBound)
                Button("I dag") { offset = 0 }.disabled(offset == 0)
                Button { offset += 1 } label: { Image(systemName: "chevron.right") }.disabled(offset >= range.upperBound)
            }
            .padding(.horizontal, 20).padding(.top, 34).padding(.bottom, 14)

            WeekGrid(days: shown, items: dayItems,
                     homework: { d in homework.filter { DateUtil.cal.isDate($0.due, inSameDayAs: d) } })
                .padding(.horizontal, 12).padding(.bottom, 12)
        }
        .frame(minWidth: 860, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
    }
}

