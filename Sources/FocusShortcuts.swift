import AppKit
import Foundation

/// "Fokus i timerne". macOS has no API for apps to turn a Focus on, but a Shortcut can, and the
/// `shortcuts` tool can run one. Viggo+ writes the two shortcuts itself (one action, Indstil fokus),
/// signs them and opens them, so the only thing left is clicking Tilføj genvej in Genveje.
@MainActor
final class FocusShortcuts: ObservableObject {
    static let shared = FocusShortcuts()

    struct Mode: Identifiable, Hashable {
        let id: String      // com.apple.donotdisturb.mode.default
        let name: String    // the name Genveje matches on, e.g. "Do Not Disturb"
    }

    @Published private(set) var modes: [Mode] = []
    /// Shortcut name to its id. Duplicates with the same name made `shortcuts run <name>` fail, so
    /// shortcuts are always run by id.
    @Published private(set) var installed: [String: String] = [:]
    @Published var message = ""

    private let dbDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB")

    init() { reload() }

    func reload() {
        modes = Self.readModes(dbDir.appendingPathComponent("ModeConfigurations.json"))
        installed = Self.list()
    }

    func mode(_ id: String) -> Mode {
        modes.first { $0.id == id } ?? Mode(id: id, name: id == Self.defaultMode ? "Do Not Disturb" : id)
    }

    static let defaultMode = "com.apple.donotdisturb.mode.default"

    /// One pair of shortcuts per Focus, so picking another Focus never collides with the old ones.
    static func names(for m: Mode) -> (on: String, off: String) {
        // Genveje drops punctuation from imported names, so keep to letters, digits and spaces.
        let clean = String(m.name.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " })
        return ("Viggo Fokus til \(clean)", "Viggo Fokus fra \(clean)")
    }

    func ready(_ m: Mode) -> Bool {
        let n = Self.names(for: m)
        return installed[n.on] != nil && installed[n.off] != nil
    }

    /// Which Focus is on right now, from the Mac's own Focus database. nil when it can't be read.
    func activeModes() -> [String]? {
        guard let data = try? Data(contentsOf: dbDir.appendingPathComponent("Assertions.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (json["data"] as? [[String: Any]])?.first else { return nil }
        return (first["storeAssertionRecords"] as? [[String: Any]] ?? []).compactMap {
            ($0["assertionDetails"] as? [String: Any])?["assertionDetailsModeIdentifier"] as? String
        }
    }

    // MARK: making the shortcuts

    /// Writes, signs and opens the missing shortcuts for this Focus. Genveje shows Tilføj genvej for each.
    func install(_ m: Mode) async {
        let n = Self.names(for: m)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ViggoFokus-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        message = "Laver genvejene…"
        let missing = [(n.on, true), (n.off, false)].filter { installed[$0.0] == nil }
        // Genveje shows one import window at a time, so open the next only when the first is added.
        for (i, (name, on)) in missing.enumerated() {
            let raw = dir.appendingPathComponent("raw-\(on).shortcut")
            let signed = dir.appendingPathComponent("\(name).shortcut")
            guard let data = try? PropertyListSerialization.data(fromPropertyList: Self.shortcut(m, on: on), format: .binary, options: 0),
                  (try? data.write(to: raw)) != nil else { message = "Kunne ikke skrive genvejen."; return }
            let r = await Self.run("/usr/bin/shortcuts", ["sign", "--mode", "anyone", "--input", raw.path, "--output", signed.path])
            guard r.status == 0, FileManager.default.fileExists(atPath: signed.path) else {
                message = "Genveje kunne ikke signere genvejen: \(r.err.isEmpty ? "ukendt fejl" : r.err)"
                return
            }
            NSWorkspace.shared.open(signed) // imported under the file's name
            message = "Tryk Tilføj genvej i Genveje" + (missing.count > 1 ? " (\(i + 1) af \(missing.count))." : ".")
            var added = false
            for _ in 0..<150 {
                try? await Task.sleep(for: .seconds(2))
                installed = Self.list()
                if installed[name] != nil { added = true; break }
            }
            guard added else { message = "Genvejen blev ikke tilføjet. Prøv igen."; return }
        }
        message = ready(m) ? "Genvejene er klar ✓" : ""
    }

    static func shortcut(_ m: Mode, on: Bool) -> [String: Any] {
        var p: [String: Any] = ["Enabled": on ? 1 : 0, "FocusModes": ["Identifier": m.id, "DisplayString": m.name]]
        if on { p["AssertionType"] = "Turned Off" } // on until the lesson ends and we turn it off
        return [
            "WFWorkflowClientVersion": "2607.0.2",
            "WFWorkflowMinimumClientVersion": 900,
            "WFWorkflowMinimumClientVersionString": "900",
            "WFWorkflowIcon": ["WFWorkflowIconStartColor": on ? 1440408063 : 463140863, "WFWorkflowIconGlyphNumber": 59511],
            "WFWorkflowImportQuestions": [], "WFWorkflowTypes": [], "WFQuickActionSurfaces": [],
            "WFWorkflowInputContentItemClasses": [], "WFWorkflowOutputContentItemClasses": [],
            "WFWorkflowHasOutputFallback": false, "WFWorkflowHasShortcutInputVariables": false,
            "WFWorkflowActions": [["WFWorkflowActionIdentifier": "is.workflow.actions.dnd.set", "WFWorkflowActionParameters": p]],
        ]
    }

    // MARK: running

    /// Runs a shortcut by id. Returns an error message, or nil when it ran.
    @discardableResult
    func run(_ name: String) async -> String? {
        if installed[name] == nil { installed = Self.list() }
        guard let id = installed[name] else { return "Genvejen \"\(name)\" findes ikke. Tryk Opret genveje." }
        let r = await Self.run("/usr/bin/shortcuts", ["run", id])
        return r.status == 0 ? nil : (r.err.isEmpty ? "Genvejen fejlede." : r.err)
    }

    // MARK: helpers

    static func readModes(_ url: URL) -> [Mode] {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (json["data"] as? [[String: Any]])?.first,
              let configs = first["modeConfigurations"] as? [String: [String: Any]] else { return [] }
        return configs.compactMap { id, c -> Mode? in
            guard let mode = c["mode"] as? [String: Any], let name = mode["name"] as? String,
                  !name.isEmpty, name != "…", id != "com.apple.focus.reduce-interruptions" else { return nil }
            return Mode(id: id, name: name)
        }
        .sorted { ($0.id == defaultMode ? 0 : 1, $0.name) < ($1.id == defaultMode ? 0 : 1, $1.name) }
    }

    /// "Name (ID)" lines from `shortcuts list --show-identifiers`. The last one wins on duplicates.
    static func list() -> [String: String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = ["list", "--show-identifiers"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return [:] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        var map: [String: String] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard let m = String(line).firstMatch("^(.*) \\(([0-9A-F-]{36})\\)$") else { continue }
            map[m[1]] = m[2]
        }
        return map
    }

    static func run(_ tool: String, _ args: [String]) async -> (status: Int32, err: String) {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            let err = Pipe()
            p.standardError = err
            p.standardOutput = Pipe()
            guard (try? p.run()) != nil else { return (-1, "Kunne ikke starte \(tool)") }
            let e = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let msg = String(decoding: e, as: UTF8.self).replacingOccurrences(of: "Error: ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (p.terminationStatus, msg)
        }.value
    }
}
