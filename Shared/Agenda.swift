import Foundation

/// A teacher on duty (Morgenvagt, Aftenvagt …). Viggo puts these in everyone's schedule.
struct Duty: Identifiable, Hashable {
    let id: Int
    let who: String
    let shift: String
    let start: Date
    let end: Date
}

extension AppState {
    /// "Niels Chr. Jørgensen - 7.00 - 8.00 Morgenvagt (07:00-08:00)" → who and shift.
    static func duty(_ e: ViggoEvent) -> Duty {
        let raw = e.rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = raw.components(separatedBy: " - ")
        let who = (parts.isEmpty ? raw : parts.removeFirst()).trimmingCharacters(in: CharacterSet(charactersIn: ", ").union(.whitespaces))
        var rest = parts.joined(separator: " - ")
        rest = rest.replacingOccurrences(of: "^[0-9.:]+\\s*-\\s*[0-9.:]+\\s*", with: "", options: .regularExpression)
        rest = rest.replacingOccurrences(of: "\\s*\\([^)]*\\)\\s*$", with: "", options: .regularExpression)
        rest = rest.replacingOccurrences(of: " - ", with: " ").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let shift = rest.trimmingCharacters(in: .whitespaces)
        return Duty(id: e.id, who: who, shift: shift.isEmpty ? "Vagt" : shift.prefix(1).uppercased() + shift.dropFirst(), start: e.start, end: e.end)
    }

    /// The teachers on duty that day, by start time.
    func duties(on d: Date, person: UUID? = nil) -> [Duty] {
        let list = person.flatMap { friendEvents[$0] } ?? events
        return list.filter { $0.kind == .duty && DateUtil.cal.isDate($0.start, inSameDayAs: d) }
            .map(Self.duty).sorted { ($0.start, $0.who) < ($1.start, $1.who) }
    }

    /// Birthdays Viggo shows that day ("Oscar Meldgaard Sørensen (12/11)" → the name), always, whatever the calendar setting.
    func birthdayNames(on d: Date, person: UUID? = nil) -> [String] {
        let list = person.flatMap { friendEvents[$0] } ?? events
        var seen = Set<String>()
        return list.filter { $0.kind == .birthday && DateUtil.cal.isDate($0.start, inSameDayAs: d) }
            .map { $0.rawName.replacingOccurrences(of: "\\s*\\([^)]*\\)\\s*$", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces) }
            .filter { seen.insert($0).inserted }
    }
}
