import Foundation

enum Config {
    static let baseURL = URL(string: "https://broeruphus.viggo.dk")!
    static let bundleID = "com.ottobigo.ViggoPlus"
    static let pollInterval: TimeInterval = 15 * 60
    static let weeksBack = 1
    static let weeksAhead = 4
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
    static var fetchEnd: Date { add(.weekOfYear, Config.weeksAhead + 1, mondayOf(Date())) }
}

extension String {
    func matches(_ pattern: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
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
        s = s.replacingOccurrences(of: "<br ?/?>|</p>|</li>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = s.htmlDecoded
        s = s.replacingOccurrences(of: "[ \\t\\r]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\n\\s*\\n+", with: "\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
