import Foundation
import SwiftUI
import WidgetKit

extension AppState {
    /// Hands the coming week to the widgets: today and the next six days, the same items as "I dag".
    func pushWidget() {
        let today = DateUtil.startOfDay(Date())
        let items = (0..<7).flatMap { n in timeline(DateUtil.add(.day, n, today)) }.map(widgetItem)
        let openList = homework.filter { !$0.done && $0.due >= today }
        let open = openList.count
        let first = profile.map { $0.name.components(separatedBy: " ").first ?? $0.name }
        WidgetStore.save(WidgetData(name: first, items: items, homework: open, updated: Date(), loggedOut: needsLogin,
                                    homeworkList: openList.map(\.title),
                                    homeworkItems: homework.filter { $0.due >= today }.prefix(10).map {
                                        WidgetHomework(id: $0.id, title: $0.title, subject: $0.group, due: $0.due, done: $0.done)
                                    }, birthdays: widgetBirthdays()))
        WidgetCenter.shared.reloadAllTimelines()
        WidgetShots.run()
        updateLiveActivity()
    }
}

extension AppState {
    /// The next birthdays among your classmates and the students on your line, from the address book.
    func widgetBirthdays() -> [WidgetBirthday] {
        guard let me = profile?.id else { return [] }
        let dir = Directory.shared
        let mine = dir.member(me)
        let line = dir.line(of: me)
        return dir.circle(of: me).compactMap { m -> (Member, (date: Date, days: Int, turns: Int))? in
            m.nextBirthday.map { (m, $0) }
        }
        .sorted { $0.1.days < $1.1.days }
        .prefix(12)
        .map { m, n in
            let from = mine.map { !$0.grade.isEmpty && $0.grade == m.grade } == true ? "Klasse \(m.className)" : (line ?? "Linje")
            return WidgetBirthday(id: m.id, name: m.name, date: n.date, turns: n.turns, from: from)
        }
    }
}

extension AppState {
    /// A tick from the homework widget: shows it at once, saves it on Viggo, and undoes it if that fails.
    func setHomeworkFromWidget(_ id: Int, done: Bool) async {
        CookieJar.restore()
        func mark(_ v: Bool) {
            if let i = homework.firstIndex(where: { $0.id == id }) { homework[i].done = v }
            var d = WidgetStore.load()
            if let i = d.homeworkItems?.firstIndex(where: { $0.id == id }) { d.homeworkItems?[i].done = v }
            d.homework = d.homeworkItems?.filter { !$0.done }.count ?? d.homework
            WidgetStore.save(d)
            WidgetCenter.shared.reloadAllTimelines()
        }
        mark(done)
        do { try await client.setHomework(id, done: done) }
        catch { mark(!done) }
    }
}

/// For checking the widgets without the home screen: VIGGO_WIDGET_SHOTS=<dir> renders every
/// widget size at a few moments (now, in a lesson and in a pause tomorrow) to PNG files.
enum WidgetShots {
    @MainActor static func run() {
        if ProcessInfo.processInfo.environment["VIGGO_SAY"] != nil {
            let d = WidgetStore.load(), t = AppState.testNow(Date())
            print("[say] nu: \(d.sayNow(t))\n[say] fri: \(d.sayFree(t))\n[say] lektier: \(d.sayHomework())\n[say] i morgen: \(d.sayTomorrow(t) ?? "-")")
        }
        guard let dir = ProcessInfo.processInfo.environment["VIGGO_WIDGET_SHOTS"] else { return }
        let d = WidgetStore.load()
        let tomorrow = DateUtil.add(.day, 1, DateUtil.startOfDay(Date()))
        let firstLesson = d.items.first { $0.start >= tomorrow && $0.kind == "lesson" }
        let pause = d.items.first { $0.start >= tomorrow && $0.isPause }
        var moments: [(String, Date)] = [("nu", Date())]
        if let l = firstLesson { moments.append(("time", l.start.addingTimeInterval(20 * 60))) }
        if let p = pause { moments.append(("pause", p.start.addingTimeInterval(5 * 60))) }
        let sizes: [(WidgetFamily, CGSize, String)] = [
            (.systemSmall, CGSize(width: 170, height: 170), "small"),
            (.systemMedium, CGSize(width: 364, height: 170), "medium"),
            (.systemLarge, CGSize(width: 364, height: 382), "large"),
            (.accessoryRectangular, CGSize(width: 172, height: 76), "rect"),
            (.accessoryInline, CGSize(width: 250, height: 24), "inline"),
            (.accessoryCircular, CGSize(width: 76, height: 76), "circle"),
        ]
        for (name, t) in moments {
            for (fam, size, fname) in sizes {
                let v = WidgetView(family: fam, entry: Entry(date: t, data: d))
                    .padding(fam.rawValue < 3 ? 16 : 4)
                    .frame(width: size.width, height: size.height)
                    .background(Color(white: 0.94))
                let r = ImageRenderer(content: v)
                r.scale = 3
                if let img = r.uiImage, let png = img.pngData() {
                    try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)-\(fname).png"))
                }
            }
        }
        for (name, data) in [("lektier", d), ("lektier-eksempel", WidgetData.homeworkSample)] {
            for (fam, size, fname) in sizes.prefix(3) {
                let v = HomeworkWidgetView(family: fam, entry: HomeworkEntry(date: Date(), data: data))
                    .padding(16).frame(width: size.width, height: size.height).background(Color(white: 0.94))
                let r = ImageRenderer(content: v)
                r.scale = 3
                if let png = r.uiImage?.pngData() { try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)-\(fname).png")) }
            }
        }
        for (name, data) in [("fodselsdage", d), ("fodselsdage-eksempel", WidgetData.birthdaySample)] {
            for (fam, size, fname) in sizes.prefix(3) {
                let v = BirthdayWidgetView(family: fam, entry: BirthdayEntry(date: Date(), data: data))
                    .padding(16).frame(width: size.width, height: size.height).background(Color(white: 0.94))
                let r = ImageRenderer(content: v)
                r.scale = 3
                if let png = r.uiImage?.pngData() { try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)-\(fname).png")) }
            }
        }
        print("[widget-shots] \(moments.map(\.0)) -> \(dir)")
    }
}
