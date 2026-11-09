import AppKit
import SwiftUI

/// `ViggoPlus --render-docs <dir>` draws the panel and the settings pages with made-up demo data
/// into PNGs for the README. No real account, names or schedule are used.
@MainActor
enum DocRenderer {
    static var outDir: String? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--render-docs"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    static func run(_ state: AppState, dir: String) async {
        loadDemo(state)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        snap(MenuView().environmentObject(state), name: "panel", dir: dir, panel: true)

        state.selectedFriend = state.friends.first?.id
        snap(MenuView().environmentObject(state), name: "panel-friend", dir: dir, panel: true)
        state.selectedFriend = nil

        snap(WeekView().environmentObject(state), name: "week", dir: dir, size: NSSize(width: 1040, height: 720))
        if let fysik = state.events.first(where: { $0.id == 4 }) {
            snap(LessonDetailView(e: fysik), name: "lesson", dir: dir)
        }

        Updater.shared.available = Updater.Release(
            version: "1.2.0", highlights: ["Uge-overblik med alle dine timer", "Fødselsdage i panelet", "Genvejstast til panelet"],
            page: URL(string: "https://github.com/otto-BigO/viggo-plus/releases")!, zip: URL(string: "https://example.com")!)
        snap(UpdateView(updater: Updater.shared), name: "update", dir: dir)
        Updater.shared.available = nil

        // The iPhone page with made-up state: halfway through the guide, then installed.
        PhoneInstaller.shared.loadDemo(done: false)
        snap(SettingsView(initial: .iphone).environmentObject(state), name: "settings-iphone-guide", dir: dir,
             size: NSSize(width: 680, height: 500))
        if ProcessInfo.processInfo.environment["VIGGO_PHONE_TALL"] != nil {
            // Only for checking the whole guide; not part of the README pictures.
            snap(PhoneTab().frame(width: 470, height: 1250).background(Color(nsColor: .windowBackgroundColor)),
                 name: "iphone-guide-tall", dir: dir, size: NSSize(width: 470, height: 1250))
        }
        PhoneInstaller.shared.loadDemo(done: true)
        for page in SettingsPage.allCases {
            snap(SettingsView(initial: page).environmentObject(state), name: "settings-\(page.slug)", dir: dir,
                 size: NSSize(width: 680, height: 500))
        }
        if ProcessInfo.processInfo.environment["VIGGO_CARD_SNAPS"] != nil {
            // Only for checking the sign-in card; not part of the README pictures.
            for (name, st) in [("card-skoleit", LoginStage.skoleit), ("card-ok", .success), ("card-fail", .failure("Forkert brugernavn eller adgangskode"))] {
                state.loginStageName = nil
                state.loginStage = st
                snap(SettingsView(initial: .konto).environmentObject(state), name: name, dir: dir, size: NSSize(width: 680, height: 500))
            }
            state.loginStage = nil
        }
        exit(0)
    }

    /// Days from today to Monday + i of this week.
    private static func mon(_ i: Int) -> Int {
        let todayIdx = DateUtil.cal.dateComponents([.day], from: DateUtil.mondayOf(Date()), to: DateUtil.startOfDay(Date())).day ?? 0
        return i - todayIdx
    }

    private static func at(_ h: Int, _ m: Int, day: Int = 0) -> Date {
        let base = DateUtil.add(.day, day, DateUtil.startOfDay(Date()))
        return DateUtil.cal.date(bySettingHour: h, minute: m, second: 0, of: base)!
    }

    private static func ev(_ id: Int, _ name: String, _ h: Int, _ m: Int, _ eh: Int, _ em: Int,
                           room: String = "", kind: EventKind = .lesson, day: Int = 0) -> ViggoEvent {
        ViggoEvent(id: id, rawName: name, start: at(h, m, day: day), end: at(eh, em, day: day), room: room,
                   notes: "", kind: kind, teachers: [], groups: [])
    }

    private static func loadDemo(_ s: AppState) {
        s.profile = Profile(id: 1, name: "Alex Jensen", image: nil)
        Prefs.shared.customItems = [
            CustomItem(title: "Træning", start: 16 * 60 + 30, end: 17 * 60 + 30, days: [2, 3, 4]),
        ]
        s.events = [
            ev(1, "104 Dansk", 8, 35, 9, 35, room: "Klasse 2"),
            ev(2, "104 Engelsk", 9, 55, 10, 55, room: "Klasse 2"),
            ev(3, "104 Matematik", 11, 5, 12, 5, room: "Klasse 3"),
            ViggoEvent(id: 4, rawName: "104 Fysik", start: at(13, 15), end: at(14, 15), room: "Lab",
                       notes: "Vi laver forsøg med strøm og spænding. Husk lommeregner og hæftet fra sidst.\n\nSe videoen inden timen:\n• Ohms lov på 5 minutter\n• Opgave 4.1 til 4.3",
                       kind: .lesson, teachers: ["Maja Holm"], groups: ["Fysik (Fys104)"],
                       links: [URL(string: "https://www.youtube.com/watch?v=demo")!, URL(string: "https://drive.google.com/file/d/demo/view")!]),
            ev(5, "104 Gymnastik", 14, 30, 16, 0, room: "Store hal"),
            ev(10, "Aftensmad", 18, 0, 18, 30, room: "Spisesalen", kind: .routine),
            ev(80, "Middag", 12, 10, 13, 0, room: "Spisesalen", kind: .routine, day: mon(0)),
            ev(81, "Middag", 12, 10, 13, 0, room: "Spisesalen", kind: .routine, day: mon(1)),
            ev(82, "Middag", 12, 10, 13, 0, room: "Spisesalen", kind: .routine, day: mon(2)),
            ev(83, "Middag", 12, 10, 13, 0, room: "Spisesalen", kind: .routine, day: mon(3)),
            ev(84, "Middag", 12, 10, 13, 0, room: "Spisesalen", kind: .routine, day: mon(4)),
            ev(85, "Tjek af værelser", 13, 0, 13, 10, kind: .routine, day: mon(0)),
            ev(86, "Tjek af værelser", 13, 0, 13, 10, kind: .routine, day: mon(1)),
            ev(87, "Tjek af værelser", 13, 0, 13, 10, kind: .routine, day: mon(2)),
            ev(88, "Tjek af værelser", 13, 0, 13, 10, kind: .routine, day: mon(3)),
            ev(89, "Tjek af værelser", 13, 0, 13, 10, kind: .routine, day: mon(4)),
            ev(11, "Stilletime og oprydning på værelset", 18, 30, 19, 30, kind: .routine),
            ev(12, "Fællessamling og aflevering af telefon", 19, 30, 19, 50, kind: .routine),
            ev(13, "Alle på eget område", 21, 45, 22, 0, kind: .routine),
            ev(14, "Godnat kl. 22.15", 22, 15, 22, 30, kind: .routine),
            ViggoEvent(id: 40, rawName: "Sofie Lund (06/11)", start: at(0, 0), end: at(23, 59), room: "", notes: "",
                       kind: .birthday, teachers: [], groups: []),
            ev(50, "Dansk", 8, 35, 9, 35, room: "Klasse 2", day: mon(1)), ev(51, "Matematik", 9, 55, 10, 55, room: "Klasse 3", day: mon(1)),
            ev(52, "Engelsk", 11, 5, 12, 5, room: "Klasse 2", day: mon(1)), 
            ev(54, "Fysik", 8, 35, 9, 35, room: "Lab", day: mon(2)), ev(55, "Tysk", 9, 55, 10, 55, room: "Klasse 2", day: mon(2)),
            ev(56, "Musik", 11, 5, 12, 5, room: "Musikhuset", day: mon(2)),
            ev(70, "Foredrag om ludomani og spil for alle elever", 16, 15, 17, 30, room: "Foredragssalen", kind: .event),
            ev(71, "Temaeftermiddag og Galla", 13, 15, 22, 30, room: "Store hal", kind: .event, day: mon(1)),
            ev(72, "Musiklinje", 13, 15, 14, 45, room: "Musikhuset", day: mon(2)),
            ev(73, "Kor", 14, 0, 15, 0, room: "Musikhuset", day: mon(2)),
            ev(61, "Biologi", 8, 35, 9, 35, room: "Lab", day: mon(3)), ev(62, "Dansk", 9, 55, 10, 55, room: "Klasse 2", day: mon(3)),
            ev(63, "Medborgerskab", 11, 5, 12, 5, room: "Klasse 2", day: mon(3)),
            ev(60, "Kor", 13, 15, 14, 15, room: "Musikhuset", day: mon(0)),
            ev(20, "Fællessang", 8, 0, 8, 30, room: "Foredragssalen", kind: .lesson, day: 1),
            ev(21, "Tysk", 8, 35, 9, 35, room: "Klasse 2", day: 1),
            ev(22, "Historie", 9, 55, 10, 55, room: "Klasse 4", day: 1),
        ]
        s.meals = [DateUtil.startOfDay(at(12, 0)): MealDay(lunch: "Svampefrikadeller m/ris, svampesauce og broccoli", dinner: "Kold buffet")]
        s.homework = [
            Homework(id: 1, title: "Læs kapitel 4", group: "Dansk", day: at(0, 0, day: 1), start: nil, end: nil,
                     notes: "", author: "", done: false),
            Homework(id: 2, title: "Opgave 3.1 til 3.6", group: "Matematik", day: at(0, 0, day: 2), start: nil, end: nil,
                     notes: "", author: "", done: true),
        ]
        s.messages = [
            ViggoMessage(id: 1, sender: "Kontoret", when: "2 timer siden", subject: "Køkkenhold uge 46", preview: ""),
            ViggoMessage(id: 2, sender: "Lærer", when: "I går 08:42", subject: "Mandagsplan", preview: ""),
        ]
        s.unreadCount = 1
        s.questionnaireCount = 0
        let ida = Friend(id: UUID(), viggoID: 2, name: "Ida Hansen", image: nil)
        let noah = Friend(id: UUID(), viggoID: 3, name: "Noah Berg", image: nil)
        s.friends = [ida, noah]
        s.friendEvents[ida.id] = [
            ev(30, "Billedkunst", 8, 35, 10, 55, room: "Atelier"),
            ev(31, "Engelsk", 11, 5, 12, 5, room: "Klasse 1"),
            ev(32, "Biologi", 13, 15, 14, 15, room: "Lab"),
            ev(33, "Musik", 15, 0, 16, 0, room: "Musikhuset"),
            ev(34, "Dansk", 8, 35, 9, 35, room: "Klasse 1", day: 1),
        ]
        s.friendHomework[ida.id] = []
        s.lastSync = at(13, 38)
        s.tick = at(13, 40)
    }

    private static func snap<V: View>(_ view: V, name: String, dir: String, size: NSSize? = nil, panel: Bool = false) {
        let content: AnyView = panel
            ? AnyView(view.environment(\.controlActiveState, .key).background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)))
            : AnyView(view.environment(\.controlActiveState, .key))
        let host = NSHostingView(rootView: content)
        let sz = size ?? host.fittingSize
        host.frame = NSRect(origin: .zero, size: sz)
        host.appearance = NSAppearance(named: .darkAqua)
        let win = KeyWindow(contentRect: NSRect(x: -30000, y: -30000, width: sz.width, height: sz.height),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.appearance = NSAppearance(named: .darkAqua)
        win.backgroundColor = panel ? .clear : .windowBackgroundColor
        win.isOpaque = !panel
        win.contentView = host
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        for _ in 0..<15 { RunLoop.main.run(until: Date().addingTimeInterval(0.05)); host.layoutSubtreeIfNeeded() }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(sz.width * 2), pixelsHigh: Int(sz.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = sz
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        win.orderOut(nil)
    }
}

/// Lets an off-screen window count as the active one, so switches and selections draw in color.
final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}
