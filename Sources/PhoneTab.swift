import SwiftUI
import AppKit

/// Settings > iPhone-app: what you need, a step-by-step guide that ticks itself off, and the
/// install button. Once installed, Viggo+ renews the app before the 7 days run out.
struct PhoneTab: View {
    @ObservedObject var inst = PhoneInstaller.shared
    @State private var showPrep = true

    private struct Step: Identifiable {
        let id: Int
        let title: String
        let time: String
        let done: Bool
        let detail: String
        var doneNote: String? = nil
        var actions: [(String, () -> Void)] = []
    }

    private var steps: [Step] {
        let d = inst.device
        let rec = d.flatMap { inst.records[$0.id] }
        let phone = d?.name ?? "iPhonen"
        let openXcode: (String, () -> Void) = ("Åbn Xcode", { inst.openXcode() })
        return [
            Step(id: 1, title: "Hent Xcode", time: "20 til 60 min",
                 done: inst.xcodeApp != nil,
                 detail: "Xcode er et gratis program fra Apple. Viggo+ bruger det til at lave iPhone-appen, så du skal ikke selv bruge det.\n\nTryk Åbn App Store, og tryk Hent. Det fylder ca. 15 GB, så det tager et stykke tid. Denne side opdager selv, når det er hentet.",
                 doneNote: inst.xcodeApp?.lastPathComponent,
                 actions: [("Åbn App Store", { NSWorkspace.shared.open(URL(string: "macappstore://apps.apple.com/app/xcode/id497799835")!) })]),
            Step(id: 2, title: "Gør Xcode klar", time: "5 til 15 min",
                 done: inst.firstLaunchDone && inst.iosPlatform,
                 detail: inst.firstLaunchDone && !inst.iosPlatform
                    ? "Xcode mangler det, der skal til for at lave iPhone-apps.\n\n1. Klik på Xcode i menulinjen øverst, og vælg Settings.\n2. Vælg Components.\n3. Tryk Get ud for iOS, og vent til den er færdig."
                    : "Viggo+ har åbnet Xcode for dig.\n\n1. Tryk Agree, og skriv din Mac-kode hvis den spørger.\n2. Sæt flueben ved iOS, og tryk Download & Install.\n3. Vent til den er færdig. Du kan lade Xcode være åben.",
                 actions: [openXcode]),
            Step(id: 3, title: "Log ind med dit Apple-ID i Xcode", time: "2 min",
                 done: inst.team != nil,
                 detail: "Appen bliver lavet med dit Apple-ID. Det almindelige gratis Apple-ID er nok.\n\n1. Klik på Xcode i menulinjen øverst, og vælg Settings.\n2. Vælg Apple Accounts.\n3. Tryk + nederst til venstre, og vælg Apple Account.\n4. Log ind med dit Apple-ID.",
                 doneNote: inst.team.map { $0.free ? "\($0.name), gratis" : $0.name },
                 actions: [openXcode]),
            Step(id: 4, title: "Sæt iPhonen i Mac'en med et kabel", time: "1 min",
                 done: d.map { $0.paired && $0.reachable } ?? false,
                 detail: "1. Sæt iPhonen i Mac'en med et USB-kabel.\n2. Lås iPhonen op.\n3. Spørger den \"Stol på denne computer?\", så tryk Stol på og skriv din kode.\n\nKablet skal kun bruges første gang. Derefter finder Mac'en den på samme wifi.",
                 doneNote: d.map { "\($0.name), \($0.model), iOS \($0.os), \($0.wired ? "med kabel" : "over wifi")" }),
            Step(id: 5, title: "Slå Udviklertilstand til på \(phone)", time: "3 min",
                 done: d?.developerMode == true,
                 detail: "Det er en indstilling, der tillader apps, som ikke kommer fra App Store.\n\nPå iPhonen:\n1. Åbn Indstillinger.\n2. Tryk Anonymitet og sikkerhed.\n3. Rul helt ned, og tryk Udviklertilstand.\n4. Slå den til, og tryk Genstart.\n5. Når iPhonen er tændt igen, tryk Slå til og skriv din kode.\n\nKan du ikke finde Udviklertilstand? Tag kablet ud og sæt det i igen, mens Xcode er åben. Så dukker den op.",
                 actions: [openXcode]),
            Step(id: 6, title: "Installer Viggo+", time: "2 til 5 min første gang",
                 done: rec != nil,
                 detail: "Mac'en laver nu appen og lægger den på \(phone). Det starter af sig selv. Hold iPhonen låst op og i kablet imens.",
                 doneNote: rec.map { "Version \($0.version)" }),
            Step(id: 7, title: "Godkend dit Apple-ID på iPhonen", time: "1 min",
                 done: rec?.trusted == true,
                 detail: "Kun første gang. iPhonen skal godkende, at appen er lavet med dit Apple-ID.\n\nPå iPhonen:\n1. Åbn Indstillinger > Generelt > VPN og enhedsadministration.\n2. Tryk på \(inst.signer ?? "Apple Development: din e-mail").\n3. Tryk Stol på.\n\nTryk så på knappen herunder, så åbner Viggo+ på iPhonen.",
                 actions: d.map { dev in [("Åbn Viggo+ på iPhonen", { Task { await inst.launch(dev) } })] } ?? []),
        ]
    }

    /// Steps Xcode has already been opened for on this visit, so closing it doesn't make it pop up again.
    @State private var openedFor: Set<Int> = []
    /// Phones that got to step 6 by going through the guide here: their install starts by itself.
    @State private var walked: Set<String> = []
    @State private var autoStarted: Set<String> = []

    /// Does for you what the current step would otherwise ask: opens Xcode, and starts the install.
    private func helpWithCurrentStep() {
        guard inst.job == nil, let current = steps.first(where: { !$0.done })?.id else { return }
        switch current {
        case 2, 3:
            // You have to click in Xcode for these two, so it comes to the front.
            if !openedFor.contains(current), !inst.xcodeRunning {
                openedFor.insert(current)
                inst.openXcode()
            }
        case 4, 5:
            if let d = inst.device { walked.insert(d.id) }
            // While Xcode runs with the phone plugged in, the Udviklertilstand menu shows up on the phone.
            if current == 5, inst.device?.reachable == true, !inst.xcodeRunning, !openedFor.contains(5) {
                openedFor.insert(5)
                inst.openXcode(inBackground: true)
            }
        case 6:
            if let d = inst.device, d.reachable, walked.contains(d.id), !autoStarted.contains(d.id) {
                autoStarted.insert(d.id)
                Task { await inst.install(d) }
            }
        default: break
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let job = inst.job { JobCard(job: job) }
                if inst.job == nil {
                    ForEach(installed, id: \.0) { udid, rec in StatusCard(udid: udid, rec: rec) }
                }
                if let e = inst.error {
                    Label(e, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.orange.opacity(0.1)))
                }
                prep
                stepList
                loginCard
                renewal
            }
            .padding(20)
            .animation(.viggo, value: inst.job)
            .animation(.viggo, value: inst.error)
        }
        .task {
            showPrep = inst.records.isEmpty
            if DocRenderer.outDir != nil { return }
            // Look again every few seconds, so the steps tick off while you work through them.
            while !Task.isCancelled {
                if inst.job == nil {
                    await inst.refresh()
                    helpWithCurrentStep()
                }
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    /// Every iPhone Viggo+ is on, the one the guide is about first.
    private var installed: [(String, PhoneInstaller.Record)] {
        inst.records.sorted { a, b in
            (a.key == inst.selected ? 0 : 1, a.value.name) < (b.key == inst.selected ? 0 : 1, b.value.name)
        }.map { ($0.key, $0.value) }
    }

    // MARK: before you start

    private var prep: some View {
        DisclosureGroup(isExpanded: $showPrep) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Apple tillader kun iPhone-apps fra App Store, men med et Apple-ID kan du lægge din egen app på din egen iPhone. Viggo+ på Mac'en klarer det meste for dig.")
                    .foregroundStyle(.secondary)
                need("desktopcomputer", "En Mac med en nyere macOS", "Xcode kræver typisk den nyeste eller næstnyeste macOS.")
                need("internaldrive", "Ca. 20 GB fri plads", "Til Xcode og iOS-delen.")
                need("person.crop.circle", "Et Apple-ID", "Det gratis du allerede har er fint.")
                need("iphone", "En iPhone med iOS 18 eller nyere", "Og et USB-kabel første gang.")
                need("clock", "Tid", "Uden Xcode: ca. 30 til 75 min i alt, mest ventetid. Har du Xcode: ca. 10 min.")
                Divider()
                Text("Godt at vide").font(.subheadline.weight(.semibold))
                bullet("Med et gratis Apple-ID virker appen 7 dage ad gangen. Viggo+ fornyer den automatisk, når iPhonen er sat til eller er på samme wifi som Mac'en.")
                bullet("Du kan have appen på flere iPhones. Et gratis Apple-ID kan have den på højst 3.")
                bullet("Mac'en skal være tændt og Viggo+ køre, for at fornyelsen kan ske. Ellers giver Viggo+ besked, før den løber ud.")
            }
            .font(.callout)
            .padding(.top, 8)
        } label: {
            Label("Før du starter", systemImage: "info.circle.fill").font(.headline)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
    }

    private func need(_ icon: String, _ title: String, _ note: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).frame(width: 20).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(.medium)
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func bullet(_ t: String) -> some View {
        HStack(alignment: .top, spacing: 6) { Text("•"); Text(t) }.foregroundStyle(.secondary)
    }

    // MARK: steps

    private var stepList: some View {
        let all = steps
        let current = all.first { !$0.done }?.id
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Trin for trin").font(.headline)
                Spacer()
                if !inst.checked { ProgressView().controlSize(.small) }
                Text("\(all.filter(\.done).count) af \(all.count)").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)
            if inst.devices.count > 1 {
                Picker("iPhone", selection: $inst.selected) {
                    ForEach(inst.devices) { d in
                        Text(inst.records[d.id] != nil ? "\(d.name) (har Viggo+)" : d.name).tag(Optional(d.id))
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .padding(.bottom, 6)
            }
            ForEach(all) { s in
                StepRow(n: s.id, title: s.title, time: s.time, done: s.done, current: s.id == current,
                        detail: s.detail, doneNote: s.doneNote, actions: s.actions,
                        install: s.id == 6 && s.id == current ? installButton : nil)
                if s.id != all.last?.id { Divider().padding(.leading, 34) }
            }
            if current == nil {
                Label(inst.records.count > 1 ? "Viggo+ er klar på \(inst.device?.name ?? "iPhonen")" : "Viggo+ er klar på iPhonen",
                      systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green).font(.callout.weight(.semibold)).padding(.top, 10)
                Text("Vil du have Viggo+ på en iPhone mere? Sæt den til med kabel og lås den op, så starter guiden forfra for den. Trin 1 til 3 er klaret, og alle dine iPhones bliver fornyet automatisk.")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 2)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
    }

    private var installButton: AnyView? {
        guard let d = inst.device else { return nil }
        return AnyView(
            Button { Task { await inst.install(d) } } label: {
                Label("Installer på \(d.name)", systemImage: "arrow.down.app.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(inst.job != nil || !d.reachable)
        )
    }

    // MARK: login

    private var loginCard: some View {
        let t = LoginTransfer.make()
        let who = t.own.map { $0.user } ?? (t.session != nil ? "din nuværende Viggo-session" : nil)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Login", systemImage: "key.fill").font(.headline)
                Spacer()
                if let d = inst.device, inst.records[d.id] != nil {
                    Button("Overfør login nu") { Task { await inst.sendLogin(to: d) } }
                        .disabled(inst.job != nil || !d.reachable || t.isEmpty)
                }
            }
            Toggle("Overfør mit login fra Mac'en, når appen installeres på min første iPhone", isOn: $inst.sendLoginOnInstall)
            Group {
                if let who {
                    Text("Sender \(who)\(t.friends.isEmpty ? "" : (t.friends.count == 1 ? " og din ven" : " og dine \(t.friends.count) venner")), så iPhone-appen er logget ind med det samme. Det går direkte over kablet eller wifi til Viggo+ på iPhonen, som sletter filen så snart den er læst. Til en iPhone mere sendes det kun, når du trykker Overfør login nu.")
                } else {
                    Text("Log ind i Viggo+ på Mac'en først, så kan dit login sendes med over.")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            if let sent = inst.loginSent {
                Label(sent, systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green)
                    .transition(.opacity)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
        .animation(.viggo, value: inst.loginSent)
    }

    // MARK: renewal

    private var renewal: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Forny automatisk", isOn: $inst.autoRenew)
            Text("Når der er under 3 dage tilbage, bygger Viggo+ appen igen i baggrunden, så snart iPhonen kan nås med kabel eller på samme wifi. Den kigger hvert 20. minut og når Mac'en vågner. Det tager under et minut, iPhonen må gerne være låst, og dine data bliver liggende.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
        .onChange(of: inst.autoRenew) { if inst.autoRenew { inst.startRenewal() } }
    }
}

private struct StepRow: View {
    let n: Int
    let title: String
    let time: String
    let done: Bool
    let current: Bool
    let detail: String
    let doneNote: String?
    let actions: [(String, () -> Void)]
    let install: AnyView?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(done ? Color.green : current ? Color.accentColor : Color.primary.opacity(0.1))
                    if done { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white) }
                    else { Text("\(n)").font(.system(size: 11, weight: .bold)).foregroundStyle(current ? .white : .secondary) }
                }
                .frame(width: 22, height: 22)
                .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).fontWeight(current ? .semibold : .regular)
                        .foregroundStyle(done || current ? .primary : .secondary)
                    if done, let doneNote { Text(doneNote).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if !done { Text(time).font(.caption).foregroundStyle(.secondary) }
            }
            if current {
                VStack(alignment: .leading, spacing: 10) {
                    Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        if let install { install }
                        ForEach(actions.indices, id: \.self) { i in Button(actions[i].0, action: actions[i].1) }
                    }
                }
                .padding(.leading, 32)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 8)
        .animation(.viggo, value: done)
        .animation(.viggo, value: current)
    }
}

private struct JobCard: View {
    let job: PhoneInstaller.Job
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(job.title).font(.headline)
                Spacer()
                TimelineView(.periodic(from: job.started, by: 1)) { tl in
                    let s = Int(tl.date.timeIntervalSince(job.started))
                    Text(String(format: "%d:%02d", s / 60, s % 60)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            ProgressView(value: job.progress).animation(.easeOut(duration: 0.4), value: job.progress)
            Text(job.detail).font(.callout).foregroundStyle(.secondary)
                .contentTransition(.interpolate).animation(.viggo, value: job.detail)
            Text("Første gang tager det 2 til 5 minutter. Hold iPhonen ulåst.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.08)))
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}

private struct StatusCard: View {
    @ObservedObject var inst = PhoneInstaller.shared
    let udid: String
    let rec: PhoneInstaller.Record
    @State private var confirmForget = false

    private var device: PhoneInstaller.Device? { inst.devices.first { $0.id == udid } }

    var body: some View {
        let left = rec.expires.timeIntervalSinceNow
        let color: Color = left < 0 ? .red : left < 86400 ? .orange : .green
        HStack(spacing: 14) {
            Image(systemName: "iphone.gen3").font(.system(size: 30)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text("Viggo+ \(rec.version) på \(rec.name)").font(.headline)
                Text(left < 0 ? "Udløbet \(PhoneInstaller.when(rec.expires))" : "Virker til \(PhoneInstaller.when(rec.expires))")
                    .font(.callout).foregroundStyle(color)
                if rec.version != inst.bundledVersion {
                    Text("Version \(inst.bundledVersion) er klar. Forny for at få den.").font(.caption).foregroundStyle(.secondary)
                } else if inst.autoRenew {
                    Text(rec.renewFrom < Date() ? "Fornyes så snart iPhonen kan nås" : "Fornyes automatisk fra \(PhoneInstaller.when(rec.renewFrom))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                connection
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                if let d = device {
                    Button("Forny nu") { Task { await inst.install(d) } }
                        .disabled(inst.job != nil || !d.reachable)
                }
                if inst.records.count > 1 || device == nil {
                    Button("Glem") { confirmForget = true }
                        .buttonStyle(.link).font(.caption)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.08)))
        .confirmationDialog("Glem \(rec.name)?", isPresented: $confirmForget) {
            Button("Glem", role: .destructive) { inst.forget(udid) }
        } message: {
            Text("Viggo+ holder op med at forny appen på den. Appen bliver på iPhonen, til den udløber \(PhoneInstaller.when(rec.expires)).")
        }
    }

    /// How the Mac can reach the phone right now, and when it was last renewed.
    private var connection: some View {
        let d = device
        let (icon, text, tint): (String, String, Color) = {
            guard let d, d.reachable else { return ("wifi.slash", "Ikke i nærheden lige nu", .secondary) }
            return d.wired ? ("cable.connector", "Forbundet med kabel", .green) : ("wifi", "Forbundet over wifi", .green)
        }()
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: icon).foregroundStyle(tint).contentTransition(.symbolEffect(.replace))
                Text(text)
            }
            if let r = rec.renewed { Text("Sidst fornyet \(PhoneInstaller.when(r))").foregroundStyle(.secondary) }
        }
        .font(.caption)
        .padding(.top, 2)
    }
}
