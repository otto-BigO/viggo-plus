import Foundation

enum Config {
    static let baseURL = URL(string: "https://broeruphus.viggo.dk")!
    static let bundleID = "com.ottobigo.ViggoPlus"
    static let pollInterval: TimeInterval = 15 * 60
    static let weeksBack = 1
    /// Viggo has the schedule for the whole school year, so look ahead to the end of June.
    static var weeksAhead: Int {
        let cal = DateUtil.cal, now = Date()
        let y = cal.component(.year, from: now) + (cal.component(.month, from: now) >= 7 ? 1 : 0)
        guard let end = cal.date(from: DateComponents(year: y, month: 6, day: 30)) else { return 4 }
        let weeks = cal.dateComponents([.weekOfYear], from: DateUtil.mondayOf(now), to: end).weekOfYear ?? 4
        return min(max(weeks, 4), 45)
    }
    /// The Calendar import stays short, so the Calendar app is not filled with half a year.
    static let calendarWeeks = 4
    /// Fetched on every refresh; the weeks after that are fetched in the background once an hour.
    static let nearWeeks = 4
    static let calSchedule = "Viggo Skema"
    static let calHomework = "Viggo Lektier"
    static let calEvents = "Viggo Begivenheder"
    static let calRoutine = "Viggo Hverdag"
    static var allCalendars: [String] { [calSchedule, calHomework, calEvents, calRoutine] }
}

enum DateUtil {
    static let tz = TimeZone(identifier: "Europe/Copenhagen")!
    static let cal: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = tz
        c.locale = Locale(identifier: "da_DK")
        return c
    }()
    static let iso = ISO8601DateFormatter()
    private static func fmt(_ f: String) -> DateFormatter {
        let d = DateFormatter()
        d.dateFormat = f
        d.timeZone = tz
        d.locale = Locale(identifier: "da_DK")
        return d
    }
    static let ymdF = fmt("yyyy-MM-dd")
    static let hmF = fmt("HH:mm")
    static let dayF = fmt("EEE d. MMM")
    static let longDayF = fmt("EEEE d. MMMM")
    static let weekdayF = fmt("EEE")
    static func ymd(_ d: Date) -> String { ymdF.string(from: d) }
    static func hm(_ d: Date) -> String { hmF.string(from: d) }
    static func day(_ d: Date) -> String { dayF.string(from: d) }
    static func mondayOf(_ d: Date) -> Date { cal.dateInterval(of: .weekOfYear, for: d)!.start }
    static func startOfDay(_ d: Date) -> Date { cal.startOfDay(for: d) }
    static func add(_ c: Calendar.Component, _ n: Int, _ d: Date) -> Date { cal.date(byAdding: c, value: n, to: d)! }
    static var fetchStart: Date { add(.weekOfYear, -Config.weeksBack, mondayOf(Date())) }
    static var fetchEnd: Date { add(.weekOfYear, Config.calendarWeeks + 1, mondayOf(Date())) }
}

/// Compiled patterns, kept: titles and parsers ask for the same few patterns thousands of times.
private enum RegexCache {
    private static var cache: [String: NSRegularExpression] = [:]
    private static let lock = NSLock()
    static func get(_ pattern: String) -> NSRegularExpression? {
        lock.lock(); defer { lock.unlock() }
        if let re = cache[pattern] { return re }
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return nil }
        cache[pattern] = re
        return re
    }
}

extension String {
    /// "fredag 13. november" → "Fredag 13. november". `.capitalized` also made the month a capital.
    var capFirst: String { prefix(1).uppercased() + dropFirst() }

    /// Soft hyphens at the places Danish allows a break, so a long word in a narrow box breaks
    /// as "Temaefter-middag" instead of in the middle of a syllable.
    var softHyphenated: String {
        let da = Locale(identifier: "da_DK") as CFLocale
        guard count > 9, CFStringIsHyphenationAvailableForLocale(da) else { return self }
        return split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
            guard word.count > 9 else { return String(word) }
            let ns = String(word) as NSString
            var cuts: [Int] = []
            var i = ns.length - 2
            while i > 2 {
                let at = CFStringGetHyphenationLocationBeforeIndex(ns, i, CFRange(location: 0, length: ns.length), 0, da, nil)
                guard at != kCFNotFound, at > 1 else { break }
                cuts.append(at)
                i = at - 1
            }
            let m = NSMutableString(string: ns)
            for at in cuts { m.insert("\u{00AD}", at: at) }
            return m as String
        }.joined(separator: " ")
    }

    func matches(_ pattern: String) -> [[String]] {
        guard let re = RegexCache.get(pattern) else { return [] }
        let ns = self as NSString
        return re.matches(in: self, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }
    func firstMatch(_ pattern: String) -> [String]? { matches(pattern).first }

    var htmlDecoded: String {
        guard contains("&") else { return self }
        let re = try! NSRegularExpression(pattern: "&(#x[0-9A-Fa-f]+|#[0-9]+|[a-zA-Z]+);")
        let ns = self as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: self, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let ent = ns.substring(with: m.range(at: 1))
            var rep: String?
            if ent.hasPrefix("#x"), let v = UInt32(ent.dropFirst(2), radix: 16), let u = Unicode.Scalar(v) {
                rep = String(Character(u))
            } else if ent.hasPrefix("#"), let v = UInt32(ent.dropFirst()), let u = Unicode.Scalar(v) {
                rep = String(Character(u))
            } else {
                rep = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "][ent]
            }
            out += rep ?? ns.substring(with: m.range)
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    var strippedHTML: String {
        var s = replacingOccurrences(of: "<script.*?</script>", with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<li[^>]*>", with: "• ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<br ?/?>|</p>|</li>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = s.htmlDecoded
        s = s.replacingOccurrences(of: "[ \\t\\r]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\n\\s*\\n+", with: "\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
