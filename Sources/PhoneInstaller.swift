import AppKit
import Foundation

/// Builds the iPhone app from the source inside Viggo+.app, signs it with the Apple ID that is
/// signed in to Xcode, installs it on an iPhone with `devicectl`, and renews it before the
/// 7 days a free Apple ID gives run out.
@MainActor final class PhoneInstaller: ObservableObject {
    static let shared = PhoneInstaller()

    struct Device: Identifiable, Equatable {
        let id: String          // UDID
        let name: String
        let model: String
        let os: String
        let wired: Bool
        let reachable: Bool
        let paired: Bool
        let developerMode: Bool?
    }

    struct Team: Equatable { let id: String; let name: String; let free: Bool }

    struct Record: Codable {
        var name: String
        var expires: Date
        var version: String
        var bundleID: String
        var trusted: Bool?
        var warned: Date?
    }

    struct Job: Equatable {
        var title: String
        var detail: String
        var progress: Double
        var started = Date()
    }

    // What is in place on this Mac.
    @Published private(set) var xcodeApp: URL?
    @Published private(set) var firstLaunchDone = false
    @Published private(set) var iosPlatform = false
    @Published private(set) var team: Team?
    @Published private(set) var signer: String?
    @Published private(set) var devices: [Device] = []
    @Published private(set) var checked = false
    @Published var selected: String?

    @Published private(set) var job: Job?
    @Published private(set) var error: String?
    @Published private(set) var records: [String: Record] = [:]
    @Published var autoRenew: Bool { didSet { UserDefaults.standard.set(autoRenew, forKey: "phoneAutoRenew") } }
    @Published var sendLoginOnInstall: Bool { didSet { UserDefaults.standard.set(sendLoginOnInstall, forKey: "phoneSendLogin") } }
    @Published private(set) var loginSent: String?

    private var renewTask: Task<Void, Never>?

    private init() {
        autoRenew = UserDefaults.standard.object(forKey: "phoneAutoRenew") as? Bool ?? true
        sendLoginOnInstall = UserDefaults.standard.object(forKey: "phoneSendLogin") as? Bool ?? true
        if let d = UserDefaults.standard.data(forKey: "phoneInstalls"),
           let r = try? JSONDecoder().decode([String: Record].self, from: d) { records = r }
    }

    var device: Device? { devices.first { $0.id == selected } ?? devices.first }
    var record: Record? { device.flatMap { records[$0.id] } ?? records.values.sorted { $0.expires > $1.expires }.first }
    var bundledVersion: String {
        (try? String(contentsOf: Self.bundledSource.appendingPathComponent("VERSION"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"
    }

    private func save() {
        if let d = try? JSONEncoder().encode(records) { UserDefaults.standard.set(d, forKey: "phoneInstalls") }
    }

    // MARK: paths

    static let bundledSource = Bundle.main.resourceURL!.appendingPathComponent("iPhoneSource")
    static let home = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ViggoPlus/iPhone")
    private var developerDir: String? { xcodeApp?.appendingPathComponent("Contents/Developer").path }
    private var env: [String: String] { developerDir.map { ["DEVELOPER_DIR": $0] } ?? [:] }

    /// Otto's own Apple ID keeps the original IDs (so his installed app and its data stay);
    /// every other Apple ID gets its own, since app IDs are unique across all of Apple.
    private func prefix(for team: Team) -> String {
        team.id == "M9H38A3AGD" ? "com.ottobigo" : "dk.viggoplus.t" + team.id.lowercased()
    }

    // MARK: checking

    func refresh() async {
        xcodeApp = Self.findXcode()
        guard xcodeApp != nil else { checked = true; devices = []; return }
        async let first = Shell.run("/usr/bin/xcodebuild", ["-checkFirstLaunchStatus"], env: env)
        async let sdk = Shell.run("/usr/bin/xcrun", ["--sdk", "iphoneos", "--show-sdk-path"], env: env)
        async let found = listDevices()
        firstLaunchDone = await first.status == 0
        iosPlatform = await sdk.status == 0
        team = Self.readTeam()
        signer = await Self.readSigner()
        devices = await found
        if selected == nil || !devices.contains(where: { $0.id == selected }) { selected = devices.first?.id }
        checked = true
    }

    static func findXcode() -> URL? {
        let fm = FileManager.default
        if let p = try? Shell.runSync("/usr/bin/xcode-select", ["-p"]),
           let r = p.range(of: ".app/") {
            let app = URL(fileURLWithPath: String(p[..<r.lowerBound]) + ".app")
            if fm.fileExists(atPath: app.path) { return app }
        }
        for name in ["Xcode.app", "Xcode-beta.app"] {
            let u = URL(fileURLWithPath: "/Applications/" + name)
            if fm.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    /// The Apple IDs signed in to Xcode (Settings > Apple Accounts). A paid team wins, since it signs for a year.
    static func readTeam() -> Team? {
        guard let out = try? Shell.runSync("/usr/bin/defaults", ["export", "com.apple.dt.Xcode", "-"]),
              let data = out.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let byAccount = plist["IDEProvisioningTeamByIdentifier"] as? [String: [[String: Any]]]
        else { return nil }
        let teams = byAccount.values.flatMap { $0 }.compactMap { t -> Team? in
            guard let id = t["teamID"] as? String else { return nil }
            return Team(id: id, name: t["teamName"] as? String ?? id, free: (t["isFreeProvisioningTeam"] as? Int ?? 1) == 1)
        }
        return teams.first { !$0.free } ?? teams.first
    }

    /// "Apple Development: name@example.com", which is what the iPhone asks you to trust.
    static func readSigner() async -> String? {
        let r = await Shell.run("/usr/bin/security", ["find-identity", "-v", "-p", "codesigning"])
        guard let line = r.output.split(separator: "\n").first(where: { $0.contains("Apple Development:") }),
              let a = line.range(of: "\"Apple Development: "), let b = line.range(of: " (", range: a.upperBound..<line.endIndex)
        else { return nil }
        return "Apple Development: " + line[a.upperBound..<b.lowerBound]
    }

    private func listDevices() async -> [Device] {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("viggo-devices-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        _ = await Shell.run("/usr/bin/xcrun", ["devicectl", "list", "devices", "--json-output", tmp.path], env: env)
        guard let data = try? Data(contentsOf: tmp),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = (json["result"] as? [String: Any])?["devices"] as? [[String: Any]] else { return [] }
        return list.compactMap { d in
            let hw = d["hardwareProperties"] as? [String: Any] ?? [:]
            let dp = d["deviceProperties"] as? [String: Any] ?? [:]
            let cp = d["connectionProperties"] as? [String: Any] ?? [:]
            guard hw["reality"] as? String == "physical", hw["deviceType"] as? String == "iPhone",
                  let udid = hw["udid"] as? String else { return nil }
            let mode = dp["developerModeStatus"] as? String
            return Device(id: udid,
                          name: dp["name"] as? String ?? "iPhone",
                          model: hw["marketingName"] as? String ?? "iPhone",
                          os: dp["osVersionNumber"] as? String ?? "",
                          wired: cp["transportType"] as? String == "wired",
                          reachable: (cp["tunnelState"] as? String ?? "unavailable") != "unavailable",
                          paired: cp["pairingState"] as? String == "paired",
                          developerMode: mode.map { $0 == "enabled" })
        }
        .sorted { ($0.reachable ? 0 : 1, $0.name) < ($1.reachable ? 0 : 1, $1.name) }
    }

    // MARK: installing

    /// Builds, signs and installs. `quiet` is for renewing in the background: no app launch on the phone.
    @discardableResult
    func install(_ d: Device, quiet: Bool = false) async -> Bool {
        guard job == nil else { return false }
        error = nil
        await refresh()
        guard let team else { error = "Log ind med dit Apple-ID i Xcode først (trin 3)."; return false }
        guard let developerDir else { error = "Xcode mangler (trin 1)."; return false }
        let pre = prefix(for: team)
        let bundleID = pre + ".viggoplus.ios"
        job = Job(title: quiet ? "Fornyer Viggo+ på \(d.name)" : "Installerer Viggo+ på \(d.name)",
                  detail: "Gør koden klar", progress: 0.02)

        // 1. A private copy of the source, refreshed when Viggo+ itself is updated.
        let src = Self.home.appendingPathComponent("src")
        do { try prepareSource(at: src) } catch {
            return fail("Kunne ikke kopiere koden: \(error.localizedDescription)")
        }

        // 2. Xcode reuses a cached signature while it is still valid, so an early renewal would not add
        //    any days. Removing Viggo+'s own cached profiles makes Apple issue a fresh 7-day one.
        await Self.removeProfiles(for: ["\(team.id).\(bundleID)", "\(team.id).\(bundleID).widget"])

        // 3. Build and sign. Progress is part time, part what xcodebuild says it is doing.
        job?.detail = "Bygger appen"
        job?.progress = 0.05
        let build = Self.home.appendingPathComponent("build")
        let args = ["-project", src.appendingPathComponent("iOS/ViggoPlusPhone.xcodeproj").path,
                    "-scheme", "ViggoPlus", "-configuration", "Release",
                    "-destination", "id=\(d.id)", "-derivedDataPath", build.path,
                    "-allowProvisioningUpdates", "-allowProvisioningDeviceRegistration",
                    "DEVELOPMENT_TEAM=\(team.id)", "VIGGO_PREFIX=\(pre)", "CODE_SIGN_STYLE=Automatic", "build"]
        let r = await Shell.run("/usr/bin/xcodebuild", args, env: ["DEVELOPER_DIR": developerDir]) { line in
            Task { @MainActor in
                guard var j = self.job else { return }
                let t = -j.started.timeIntervalSinceNow
                j.progress = max(j.progress, 0.05 + 0.75 * (1 - exp(-t / 45)))
                if line.hasPrefix("ProcessProvisioningProfile") || line.hasPrefix("Signing Identity") {
                    j.detail = "Henter signatur fra Apple"
                } else if line.hasPrefix("SwiftCompile") || line.hasPrefix("CompileSwift") || line.hasPrefix("CompileAssetCatalog") {
                    j.detail = "Bygger appen"
                } else if line.hasPrefix("Ld ") {
                    j.detail = "Samler appen"
                } else if line.hasPrefix("CodeSign") {
                    j.detail = "Signerer"
                    j.progress = max(j.progress, 0.82)
                }
                self.job = j
            }
        }
        guard r.status == 0 else { return fail(Self.explain(r.output)) }

        // 4. Copy it to the phone.
        job?.detail = "Kopierer til iPhonen"
        job?.progress = 0.88
        let app = build.appendingPathComponent("Build/Products/Release-iphoneos/Viggo+.app")
        let inst = await Shell.run("/usr/bin/xcrun", ["devicectl", "device", "install", "app", "--device", d.id, app.path],
                                   env: ["DEVELOPER_DIR": developerDir])
        guard inst.status == 0 else { return fail(Self.explain(inst.output)) }

        // 5. When does the signature run out?
        var rec = Record(name: d.name, expires: Date().addingTimeInterval(7 * 86400), version: bundledVersion,
                         bundleID: bundleID, trusted: records[d.id]?.trusted)
        let prof = await Shell.run("/usr/bin/security", ["cms", "-D", "-i", app.appendingPathComponent("embedded.mobileprovision").path])
        if let data = prof.output.data(using: .utf8),
           let p = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let exp = p["ExpirationDate"] as? Date { rec.expires = exp }
        records[d.id] = rec
        save()

        // 6. Your login, so the iPhone app is ready without typing anything.
        if !quiet, sendLoginOnInstall, !LoginTransfer.make().isEmpty {
            job?.detail = "Overfører dit login"
            job?.progress = 0.93
            _ = await copyLogin(to: d, bundleID: bundleID)
        }

        // 7. Open it on the phone: that also tells us whether the phone trusts the Apple ID yet.
        if !quiet {
            job?.detail = "Åbner Viggo+ på iPhonen"
            job?.progress = 0.96
            await launch(d)
        }
        job = nil
        startRenewal()
        Notifier.shared.post(quiet ? "Viggo+ er fornyet på \(d.name)" : "Viggo+ er installeret på \(d.name)",
                             "Virker til \(Self.when(rec.expires)).")
        return true
    }

    /// Sends your login to an iPhone that already has the app, and restarts the app so it reads it.
    func sendLogin(to d: Device) async {
        guard job == nil else { return }
        error = nil
        loginSent = nil
        guard !LoginTransfer.make().isEmpty else { error = "Du er ikke logget ind i Viggo+ på Mac'en endnu."; return }
        guard let bundleID = records[d.id]?.bundleID ?? team.map({ prefix(for: $0) + ".viggoplus.ios" }) else {
            error = "Installer Viggo+ på iPhonen først."; return
        }
        job = Job(title: "Overfører login til \(d.name)", detail: "Sender", progress: 0.3)
        let ok = await copyLogin(to: d, bundleID: bundleID)
        if ok {
            job?.detail = "Genstarter Viggo+ på iPhonen"
            job?.progress = 0.8
            if let developerDir {
                _ = await Shell.run("/usr/bin/xcrun", ["devicectl", "device", "process", "launch", "--terminate-existing",
                                                       "--device", d.id, bundleID], env: ["DEVELOPER_DIR": developerDir])
            }
        }
        job = nil
    }

    /// Copies the login file into the iPhone app's data container. The phone deletes it once read.
    private func copyLogin(to d: Device, bundleID: String) async -> Bool {
        guard let developerDir else { return false }
        let t = LoginTransfer.make()
        let file = Self.home.appendingPathComponent("viggo-import.plist")
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            try FileManager.default.createDirectory(at: Self.home, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
            try PropertyListEncoder().encode(t).write(to: file)
        } catch { self.error = "Kunne ikke gemme login-filen."; return false }
        let r = await Shell.run("/usr/bin/xcrun", ["devicectl", "device", "copy", "to", "--device", d.id,
                                                   "--source", file.path, "--destination", LoginTransfer.devicePath,
                                                   "--domain-type", "appDataContainer", "--domain-identifier", bundleID],
                                env: ["DEVELOPER_DIR": developerDir])
        guard r.status == 0 else { self.error = Self.explain(r.output); return false }
        let who = t.own.map { $0.user.components(separatedBy: "@").first ?? $0.user } ?? "din session"
        loginSent = t.friends.isEmpty ? "Login (\(who)) sendt til \(d.name)." : "Login (\(who)) og \(t.friends.count == 1 ? "1 ven" : "\(t.friends.count) venner") sendt til \(d.name)."
        return true
    }

    /// Opens Viggo+ on the phone. Fails with a trust error until the Apple ID is trusted in Settings.
    func launch(_ d: Device) async {
        guard var rec = records[d.id], let developerDir else { return }
        let r = await Shell.run("/usr/bin/xcrun", ["devicectl", "device", "process", "launch", "--device", d.id, rec.bundleID],
                                env: ["DEVELOPER_DIR": developerDir])
        let out = r.output.lowercased()
        if r.status == 0 { rec.trusted = true }
        else if out.contains("trust") || out.contains("profile has not been") || out.contains("invalid code signature") { rec.trusted = false }
        else if out.contains("locked") { error = "Viggo+ er på iPhonen, men den var låst, så den kunne ikke åbnes. Lås den op og tryk Åbn Viggo+ på iPhonen." }
        records[d.id] = rec
        save()
    }

    private func fail(_ message: String) -> Bool {
        job = nil
        error = message
        return false
    }

    private func prepareSource(at dst: URL) throws {
        let fm = FileManager.default
        let have = try? String(contentsOf: dst.appendingPathComponent("VERSION"), encoding: .utf8)
        let want = try? String(contentsOf: Self.bundledSource.appendingPathComponent("VERSION"), encoding: .utf8)
        if have != nil, have == want, fm.fileExists(atPath: dst.appendingPathComponent("iOS").path) { return }
        try? fm.removeItem(at: dst)
        try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: Self.bundledSource, to: dst)
    }

    /// Deletes cached provisioning profiles for exactly these app identifiers ("TEAM.bundle.id").
    private static func removeProfiles(for ids: Set<String>) async {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        for dir in ["Library/Developer/Xcode/UserData/Provisioning Profiles", "Library/MobileDevice/Provisioning Profiles"] {
            let d = home.appendingPathComponent(dir)
            for f in (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? [] where f.pathExtension == "mobileprovision" {
                let r = await Shell.run("/usr/bin/security", ["cms", "-D", "-i", f.path])
                guard let data = r.output.data(using: .utf8),
                      let p = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let ent = p["Entitlements"] as? [String: Any],
                      let app = ent["application-identifier"] as? String, ids.contains(app) else { continue }
                try? fm.removeItem(at: f)
            }
        }
    }

    /// Turns xcodebuild / devicectl output into one plain sentence.
    static func explain(_ output: String) -> String {
        let o = output.lowercased()
        if o.contains("no account") || o.contains("no accounts") || o.contains("requires a development team") || o.contains("not signed in") {
            return "Xcode har ikke et Apple-ID. Log ind under Xcode > Indstillinger > Apple Accounts (trin 3)."
        }
        if o.contains("developer mode") { return "Udviklertilstand er slået fra på iPhonen (trin 5)." }
        if o.contains("maximum number") || o.contains("app id limit") || o.contains("cannot be registered") {
            return "Et gratis Apple-ID kan kun lave 10 app-id'er om ugen eller have 3 iPhones. Vent et par dage og prøv igen."
        }
        if o.contains("locked") { return "iPhonen er låst. Lås den op og prøv igen." }
        if o.contains("unable to find a destination") || o.contains("not connected") || o.contains("unavailable") {
            return "Mac'en kan ikke se iPhonen lige nu. Sæt den til med kabel, lås den op og prøv igen."
        }
        if o.contains("pair") { return "iPhonen er ikke parret. Lås den op og tryk Stol på når den spørger." }
        if o.contains("license") { return "Åbn Xcode én gang og accepter licensen (trin 2)." }
        let lines = output.split(separator: "\n").map(String.init)
        if let e = lines.last(where: { $0.contains("error:") }) {
            return "Det gik galt: " + e.components(separatedBy: "error:").last!.trimmingCharacters(in: .whitespaces)
        }
        return "Det gik galt. Prøv igen, eller åbn Xcode og se om den beder om noget."
    }

    static func when(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "da_DK")
        f.dateFormat = Calendar.current.isDate(d, equalTo: Date(), toGranularity: .weekOfYear) ? "EEEE 'kl.' HH.mm" : "EEEE d. MMMM 'kl.' HH.mm"
        return f.string(from: d)
    }

    // MARK: renewing

    /// Every couple of hours: renew any install with less than two days left, if the phone is reachable.
    func startRenewal() {
        guard renewTask == nil, !records.isEmpty else { return }
        renewTask = Task {
            try? await Task.sleep(for: .seconds(90))
            while !Task.isCancelled {
                await renewIfNeeded()
                try? await Task.sleep(for: .seconds(2 * 3600))
            }
        }
    }

    func renewIfNeeded() async {
        guard autoRenew, job == nil else { return }
        let due = records.filter { $0.value.expires.timeIntervalSinceNow < 2 * 86400 }
        guard !due.isEmpty else { return }
        await refresh()
        for (udid, rec) in due {
            if let d = devices.first(where: { $0.id == udid && $0.reachable }), await install(d, quiet: true) { continue }
            error = nil
            // Couldn't reach it: one reminder a day once there is less than a day left.
            let left = rec.expires.timeIntervalSinceNow
            if left < 86400, (rec.warned.map { -$0.timeIntervalSinceNow > 20 * 3600 } ?? true) {
                records[udid]?.warned = Date()
                save()
                Notifier.shared.post(left > 0 ? "Viggo+ på \(rec.name) udløber snart" : "Viggo+ på \(rec.name) er udløbet",
                                     "Sæt iPhonen til Mac'en med kabel eller på samme wifi, så fornyer Viggo+ den.")
            }
        }
    }

    /// Made-up state for the README pictures (no real phone or Apple ID).
    func loadDemo(done: Bool) {
        xcodeApp = URL(fileURLWithPath: "/Applications/Xcode.app")
        firstLaunchDone = true
        iosPlatform = true
        team = Team(id: "DEMO", name: "Emma Jensen (Personal Team)", free: true)
        signer = "Apple Development: emma@example.com"
        devices = [Device(id: "demo", name: "Emmas iPhone", model: "iPhone 15", os: "18.2", wired: true,
                          reachable: true, paired: true, developerMode: done)]
        selected = "demo"
        checked = true
        records = done ? ["demo": Record(name: "Emmas iPhone", expires: Date().addingTimeInterval(5 * 86400 + 3 * 3600),
                                         version: bundledVersion, bundleID: "demo", trusted: true)] : [:]
    }

    func forget(_ udid: String) {
        records[udid] = nil
        save()
    }
}

/// Runs command line tools off the main thread.
enum Shell {
    struct Result: Sendable { let status: Int32; let output: String }

    static func run(_ tool: String, _ args: [String], env: [String: String] = [:],
                    onLine: (@Sendable (String) -> Void)? = nil) async -> Result {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            p.environment = ProcessInfo.processInfo.environment.merging(env) { $1 }
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            let box = OutputBox()
            pipe.fileHandleForReading.readabilityHandler = { h in
                let data = h.availableData
                guard !data.isEmpty else { return }
                for line in box.append(data) { onLine?(line) }
            }
            p.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                let rest = pipe.fileHandleForReading.readDataToEndOfFile()
                for line in box.append(rest) { onLine?(line) }
                cont.resume(returning: Result(status: proc.terminationStatus, output: box.text))
            }
            do { try p.run() } catch {
                cont.resume(returning: Result(status: -1, output: error.localizedDescription))
            }
        }
    }

    static func runSync(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// Collects output and hands back whole lines as they arrive.
    private final class OutputBox: @unchecked Sendable {
        private let lock = NSLock()
        private var all = Data()
        private var partial = ""
        var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: all, as: UTF8.self) }
        func append(_ d: Data) -> [String] {
            lock.lock(); defer { lock.unlock() }
            all.append(d)
            partial += String(decoding: d, as: UTF8.self)
            var lines = partial.components(separatedBy: "\n")
            partial = lines.removeLast()
            return lines
        }
    }
}
