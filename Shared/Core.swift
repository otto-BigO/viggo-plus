import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Bulletin board (opslagstavle)

struct Bulletin: Identifiable, Hashable {
    let board: String
    let author: String
    let when: String
    let title: String
    let text: String
    /// The full text with its line breaks, for reading the post.
    var body = ""
    var authorImage: URL? = nil
    /// Pictures attached to the post or put in its text.
    var images: [URL] = []
    /// Links in the text, shown as buttons.
    var links: [URL] = []
    /// The post's colour on Viggo.
    var color: Color? = nil
    /// Viggo gives posts no id, so author + title + start of the text identifies one.
    var id: String { "\(board)|\(author)|\(title)|\(text.prefix(120))" }
}

extension Parser {
    static func bulletins(_ html: String) -> [Bulletin] {
        let board = html.firstMatch("<h4>.*?</i>(.*?)<small>")?[1].strippedHTML ?? "Opslagstavle"
        return html.components(separatedBy: "class=\"hinted\">").dropFirst().compactMap { bulletin(String($0), board: board) }
    }

    private static func bulletin(_ c: String, board: String) -> Bulletin? {
        guard let title = c.firstMatch("<p class=\"h\"><strong>(.*?)</strong>")?[1].strippedHTML else { return nil }
        let author = c.firstMatch("^(.*?)<small>")?[1].strippedHTML ?? ""
        let when = c.firstMatch("<small>(.*?)</small>")?[1].strippedHTML ?? ""
        let content: String = c.firstMatch("<div class=\"content\">(.*?)</div></div>")?[1] ?? ""
        var b = Bulletin(board: board, author: author, when: when, title: title, text: content.strippedHTML)
        b.body = content.messageText
        if let src = c.firstMatch("<span class=\"hint\">\\s*<img src=\"(.*?)\"")?[1] {
            b.authorImage = URL(string: src.htmlDecoded, relativeTo: Config.baseURL)?.absoluteURL
        }
        var images: [URL] = []
        for m in c.matches("<img[^>]+src=\"([^\"]+)\"") {
            let src = m[1].htmlDecoded
            guard src.contains("DownloadFile") || (src.contains("cdn.viggo.dk") && !src.contains("/users/")) else { continue }
            if let u = URL(string: src.replacingOccurrences(of: "&preview=true", with: ""), relativeTo: Config.baseURL) { images.append(u.absoluteURL) }
        }
        b.images = images
        b.links = content.matches("href=\"(https?://[^\"]+)\"").compactMap { URL(string: $0[1].htmlDecoded) }
        if let hex = c.firstMatch("background-color: (#[0-9a-fA-F]{6})")?[1] { b.color = Color(hex: hex) }
        return b
    }
}

extension ViggoClient {
    /// The student and parent boards shown on Viggo's front page.
    func fetchBulletins() async throws -> [Bulletin] {
        var all: [Bulletin] = []
        for type in [28, 29] {
            let html = String(decoding: try await getPublic("/Basic/BulletinBoard/HomeWidget?show=9&userType=\(type)&ajax=1"), as: UTF8.self)
            all += Parser.bulletins(html)
        }
        return all
    }
}

// MARK: - Madplan (meal plan from the bulletin board)

/// Today's food, read from the kitchen's "Madplan uge 45" post on the student board:
/// one line per weekday, "Mandag - Svampefrikadeller m/ris ... og kl. 18 kold buffet".
/// The part before "og kl. 18" is lunch (Middag), the rest is dinner (Aftensmad).
struct MealDay: Codable, Hashable {
    let lunch: String
    let dinner: String?
}

enum MealPlan {
    static let iso: Calendar = { var c = Calendar(identifier: .iso8601); c.timeZone = .current; return c }()
    private static let days = ["mandag": 2, "tirsdag": 3, "onsdag": 4, "torsdag": 5, "fredag": 6, "lørdag": 7, "søndag": 1]
    private static let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "maj": 5, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "okt": 10, "nov": 11, "dec": 12]

    /// "1. nov 2026 06:05" (or "3 timer siden" for today's posts) → a date.
    static func postDate(_ when: String, now: Date = Date()) -> Date? {
        if let m = when.firstMatch("(\\d{1,2})\\. (\\w{3})\\w* (\\d{4})"), let d = Int(m[1]), let mo = months[m[2].lowercased()], let y = Int(m[3]) {
            return DateUtil.cal.date(from: DateComponents(year: y, month: mo, day: d, hour: 12))
        }
        return when.contains("siden") || when.lowercased().contains("i dag") ? now : nil
    }

    /// Start of day → food, for every meal plan post found.
    static func parse(_ posts: [Bulletin], now: Date = Date()) -> [Date: MealDay] {
        var out: [Date: MealDay] = [:]
        for b in posts where b.title.lowercased().firstMatch("^\\s*(mad|menu)plan") != nil {
            guard let posted = postDate(b.when, now: now) else { continue }
            // The week: "uge 45" in the title, else the week after a Sunday post, else the post's own week.
            var week = iso.component(.weekOfYear, from: posted)
            var year = iso.component(.yearForWeekOfYear, from: posted)
            if let m = b.title.lowercased().firstMatch("uge\\s*(\\d{1,2})"), let w = Int(m[1]) {
                if w < week - 26 { year += 1 }
                week = w
            } else if iso.component(.weekday, from: posted) == 1, let next = iso.date(byAdding: .day, value: 1, to: posted) {
                week = iso.component(.weekOfYear, from: next); year = iso.component(.yearForWeekOfYear, from: next)
            }
            for line in b.text.components(separatedBy: .newlines) {
                guard let m = line.trimmingCharacters(in: .whitespaces)
                        .firstMatch("^(?i)(mandag|tirsdag|onsdag|torsdag|fredag|lørdag|søndag)\\s*[-–:]\\s*(.+)$"),
                      let wd = days[m[1].lowercased()],
                      let date = iso.date(from: DateComponents(weekday: wd, weekOfYear: week, yearForWeekOfYear: year)) else { continue }
                let food = m[2].trimmingCharacters(in: .whitespaces)
                var lunch = food, dinner: String? = nil
                if let r = food.range(of: "\\s+og\\s+kl\\.?\\s*1[6-9]([.:]\\d{2})?\\s*", options: [.regularExpression, .caseInsensitive])
                    ?? food.range(of: "\\s+og\\s+(?=kold buffet\\s*$)", options: [.regularExpression, .caseInsensitive]) {
                    lunch = String(food[..<r.lowerBound])
                    let rest = String(food[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                    dinner = rest.isEmpty ? nil : rest.prefix(1).uppercased() + rest.dropFirst()
                }
                out[DateUtil.startOfDay(date)] = MealDay(lunch: lunch, dinner: dinner)
            }
        }
        return out
    }
}

extension ViggoClient {
    /// Meal plan posts from the student board, also older ones Viggo has taken down from the front page.
    func fetchMealPosts() async throws -> [Bulletin] {
        var all: [Bulletin] = []
        for path in ["/Basic/BulletinBoard/HomeWidget?show=60&userType=28&ajax=1", "/Basic/BulletinBoard/GetOldBulletins/?useTypsId=28"] {
            if let d = try? await getPublic(path) { all += Parser.bulletins(String(decoding: d, as: UTF8.self)) }
        }
        return all.filter { $0.title.lowercased().firstMatch("^\\s*(mad|menu)plan") != nil }
    }
}

extension ViggoEvent {
    /// The same event with `notes` set (used to put today's food on Middag and Aftensmad).
    func withNotes(_ n: String) -> ViggoEvent {
        var e = ViggoEvent(id: id, rawName: rawName, start: start, end: end, room: room, notes: n, kind: kind, teachers: teachers, groups: groups)
        e.links = links
        return e
    }
}

// MARK: - Birthdays

extension ViggoEvent {
    /// "Anders Lemming Borgensgaard (06/11)" → "Anders Lemming Borgensgaard"
    var birthdayName: String {
        rawName.replacingOccurrences(of: "\\s*\\(\\d{1,2}/\\d{1,2}\\)\\s*$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Own names and colours for lessons

extension Color {
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let v = Int(h, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
    var hex: String {
        #if os(macOS)
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        let (r, g, b) = (c.redComponent, c.greenComponent, c.blueComponent)
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

extension ViggoEvent {
    var customColor: Color? { Prefs.shared.lessonColors[baseTitle].flatMap { Color(hex: $0) } }
}

