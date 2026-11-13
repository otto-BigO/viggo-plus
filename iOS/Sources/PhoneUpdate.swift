import SwiftUI
import UserNotifications

/// The iPhone app can't install itself: it is signed by the Apple ID on the Mac, so Viggo+ on the
/// Mac puts every new version on the phone. This side only looks at GitHub to tell you that a new
/// version is on its way, and shows what is new once it has arrived.
@MainActor final class PhoneUpdate: ObservableObject {
    static let shared = PhoneUpdate()
    static let repo = "otto-BigO/viggo-plus"

    struct Info: Codable, Equatable {
        var version: String      // iPhone app version
        var mac: String          // the Mac release it came with
        var notes: [String]
    }

    /// A newer iPhone app than this one is out.
    @Published private(set) var waiting: Info?
    /// We were just updated: what is new (shown once).
    @Published var arrived: Info?

    private let d = UserDefaults.standard
    private var lastCheck: Date { d.object(forKey: "updateCheck") as? Date ?? .distantPast }

    /// VIGGO_PRETEND_VERSION makes the app think it is older, to test this in the simulator.
    var current: String {
        ProcessInfo.processInfo.environment["VIGGO_PRETEND_VERSION"]
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// This launch is the first one after the Mac put a newer version on the phone.
    private var justUpdated = false

    private init() {
        let last = d.string(forKey: "lastRunVersion")
        justUpdated = last.map { isNewer(current, than: $0) } ?? false
        if ProcessInfo.processInfo.environment["VIGGO_PRETEND_VERSION"] == nil { d.set(current, forKey: "lastRunVersion") }
        if let data = d.data(forKey: "updateInfo"), let i = try? JSONDecoder().decode(Info.self, from: data) {
            if i.version == current, justUpdated || d.string(forKey: "updateNotified") == i.version,
               d.string(forKey: "updateShown") != i.version {
                arrived = i
            } else if isNewer(i.version, than: current) {
                waiting = i
            }
        }
    }

    func dismissArrived() {
        if let a = arrived { d.set(a.version, forKey: "updateShown") }
        arrived = nil
    }

    /// At most every 3 hours, unless `force`.
    func check(force: Bool = false) async {
        guard force || -lastCheck.timeIntervalSinceNow > 3 * 3600 else { return }
        d.set(Date(), forKey: "updateCheck")
        guard let info = await Self.latest() else { return }
        if let data = try? JSONEncoder().encode(info) { d.set(data, forKey: "updateInfo") }
        print("[opdatering] nyeste iPhone-app \(info.version) (Mac \(info.mac)), denne er \(current)")
        if isNewer(info.version, than: current) {
            waiting = info
            if d.string(forKey: "updateNotified") != info.version {
                d.set(info.version, forKey: "updateNotified")
                notify(info)
            }
        } else {
            waiting = nil
            if info.version == current, justUpdated, arrived == nil, d.string(forKey: "updateShown") != info.version {
                arrived = info
            }
        }
    }

    /// The newest release on GitHub and the iPhone app version inside it (read from iOS/project.yml at that tag).
    /// A Mac-only release keeps the iPhone version, so the notes come from the release that brought that
    /// iPhone version: the oldest in the run of newest releases with the same iPhone version.
    static func latest() async -> Info? {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=8")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        let releases = list.filter { $0["draft"] as? Bool != true && $0["prerelease"] as? Bool != true }
        guard let first = releases.first, let tag = first["tag_name"] as? String,
              let version = await phoneVersion(at: tag) else { return nil }
        var intro = first
        for r in releases.dropFirst().prefix(5) {
            guard let t = r["tag_name"] as? String, let v = await phoneVersion(at: t), v == version else { break }
            intro = r
        }
        return Info(version: version, mac: tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
                    notes: notes(intro["body"] as? String ?? ""))
    }

    private static func phoneVersion(at tag: String) async -> String? {
        guard let yml = URL(string: "https://raw.githubusercontent.com/\(repo)/\(tag)/iOS/project.yml"),
              let (y, _) = try? await URLSession.shared.data(from: yml),
              let text = String(data: y, encoding: .utf8),
              let m = text.firstMatch("MARKETING_VERSION:\\s*\"?([0-9.]+)") else { return nil }
        return m[1]
    }

    /// The bold start of each "- " line in the release notes, e.g. "Søg i alt".
    static func notes(_ body: String) -> [String] {
        let lines = body.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("- ") }
        let bold = lines.filter { $0.hasPrefix("- **") }
        return (bold.isEmpty ? lines : bold)
            .prefix(4)
            .map { line in
                var t = String(line.dropFirst(2))
                if t.hasPrefix("**"), let end = t.range(of: "**", range: t.index(t.startIndex, offsetBy: 2)..<t.endIndex) {
                    return String(t[t.index(t.startIndex, offsetBy: 2)..<end.lowerBound])
                }
                if let r = t.range(of: ". ") { t = String(t[..<r.lowerBound]) }
                return t.count > 70 ? String(t.prefix(68)) + "…" : t
            }
    }

    private func notify(_ i: Info) {
        let c = UNMutableNotificationContent()
        c.title = "Viggo+ \(i.version) er på vej"
        c.body = (i.notes.first.map { "\($0). " } ?? "") + "Den kommer på din iPhone, næste gang den er på samme wifi som din Mac."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "update-\(i.version)", content: c, trigger: nil))
    }

    func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}

/// Card on I dag: a new version is on its way, or what is new since the last one.
struct UpdateCard: View {
    @ObservedObject var u = PhoneUpdate.shared

    var body: some View {
        if let a = u.arrived {
            card(icon: "sparkles", tint: .purple, title: "Nyt i Viggo+ \(a.version)", notes: a.notes,
                 footer: nil, close: { withAnimation(.viggo) { u.dismissArrived() } })
        } else if let w = u.waiting {
            card(icon: "arrow.down.circle.fill", tint: .blue, title: "Viggo+ \(w.version) er på vej", notes: w.notes,
                 footer: "Din Mac lægger den på iPhonen, næste gang den er på samme wifi eller sat til med kabel.", close: nil)
        }
    }

    private func card(icon: String, tint: Color, title: String, notes: [String], footer: String?, close: (() -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon).font(.headline).foregroundStyle(tint)
                Spacer()
                if let close {
                    Button(action: close) {
                        Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                            .frame(width: 26, height: 26).background(Circle().fill(.quaternary))
                    }
                    .buttonStyle(.plain)
                }
            }
            ForEach(notes, id: \.self) { n in
                Label(n, systemImage: "checkmark").font(.subheadline).labelStyle(NoteLabel())
            }
            if let footer { Text(footer).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(tint.opacity(0.1)))
    }

    private struct NoteLabel: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                configuration.icon.font(.caption.weight(.bold)).foregroundStyle(.secondary)
                configuration.title
            }
        }
    }
}

/// Indstillinger > Opdateringer: which version you have, what is out, and how updates reach the phone.
struct UpdateTab: View {
    @ObservedObject var u = PhoneUpdate.shared
    @State private var checking = false
    @State private var latest: PhoneUpdate.Info?

    var body: some View {
        List {
            Section {
                LabeledContent("Din version", value: u.current)
                if let l = latest ?? u.waiting {
                    LabeledContent("Nyeste", value: l.version)
                }
                Button {
                    checking = true
                    Task {
                        await u.check(force: true)
                        latest = await PhoneUpdate.latest()
                        checking = false
                    }
                } label: {
                    HStack {
                        Text("Tjek nu")
                        Spacer()
                        if checking { ProgressView() }
                    }
                }
                .disabled(checking)
            } footer: {
                if let w = u.waiting {
                    Text("Viggo+ \(w.version) er på vej. Din Mac lægger den på iPhonen, næste gang den er på samme wifi eller sat til med kabel. Du skal ikke gøre noget.")
                } else if latest != nil {
                    Text("Du har den nyeste version.")
                }
            }
            if let n = (u.waiting ?? latest ?? u.arrived)?.notes, !n.isEmpty {
                Section("Nyt i \((u.waiting ?? latest ?? u.arrived)!.version)") {
                    ForEach(n, id: \.self) { Text($0) }
                }
            }
            Section {
                Text("iPhone-appen er signeret med Apple-ID'et på din Mac, så den kan ikke opdatere sig selv. Viggo+ på Mac'en opdaterer sig selv, når Mac'en ikke bruges, og lægger så den nye iPhone-app på telefonen. Den kigger hvert 5. minut, så snart der er en ny version, og du får en besked når den er lagt på.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } header: { Text("Sådan virker det") }
        }
        .task { latest = await PhoneUpdate.latest() }
    }
}
