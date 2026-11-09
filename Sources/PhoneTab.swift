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
        let openXcode: (String, () -> Void) = ("Åbn Xcode", { if let x = inst.xcodeApp { NSWorkspace.shared.open(x) } })
        return [
            Step(id: 1, title: "Hent Xcode", time: "20 til 60 min",
                 done: inst.xcodeApp != nil,
                 detail: "Xcode er Apples gratis program til at lave apps. Viggo+ bruger det til at bygge iPhone-appen og signere den med dit Apple-ID. Det fylder ca. 15 GB, så det meste af tiden er ventetid på download. Du skal ikke selv bruge Xcode bagefter.",
                 doneNote: inst.xcodeApp?.lastPathComponent,
                 actions: [("Åbn App Store", { NSWorkspace.shared.open(URL(string: "macappstore://apps.apple.com/app/xcode/id497799835")!) })]),
            Step(id: 2, title: "Åbn Xcode én gang", time: "5 til 15 min",
                 done: inst.firstLaunchDone && inst.iosPlatform,
                 detail: inst.firstLaunchDone && !inst.iosPlatform
                    ? "Xcode mangler iOS-delen. Gå til Xcode > Indstillinger > Components, og tryk Get ud for iOS. Den er på nogle GB."
                    : "Åbn Xcode, accepter licensen, og sæt flueben ved iOS når den spørger hvilke platforme du vil have. Den henter så det sidste. Luk Xcode bagefter.",
                 actions: [openXcode]),
            Step(id: 3, title: "Log ind med dit Apple-ID i Xcode", time: "2 min",
                 done: inst.team != nil,
                 detail: "I Xcode: Xcode > Indstillinger > Apple Accounts > + > Apple Account, og log ind. Et almindeligt gratis Apple-ID er nok, det koster ingenting.",
                 doneNote: inst.team.map { $0.free ? "\($0.name), gratis" : $0.name },
                 actions: [openXcode]),
            Step(id: 4, title: "Sæt iPhonen til med kabel", time: "1 min",
                 done: d.map { $0.paired && $0.reachable } ?? false,
                 detail: "Brug et USB-kabel og lås iPhonen op. Når den spørger \"Stol på denne computer?\", tryk Stol på og skriv din kode. Kablet skal kun bruges første gang; derefter kan Mac'en finde den på samme wifi.",
                 doneNote: d.map { "\($0.name), \($0.model), iOS \($0.os), \($0.wired ? "med kabel" : "over wifi")" }),
            Step(id: 5, title: "Slå Udviklertilstand til på iPhonen", time: "3 min",
                 done: d?.developerMode == true,
                 detail: "På iPhonen: Indstillinger > Anonymitet og sikkerhed > Udviklertilstand (helt nederst) > slå til. iPhonen genstarter. Tryk Slå til når den er tændt igen, og skriv din kode. Menuen dukker først op efter iPhonen har været sat til en Mac med Xcode, så gør trin 4 først."),
            Step(id: 6, title: "Installer Viggo+", time: "2 til 5 min første gang",
                 done: rec != nil,
                 detail: "Mac'en bygger appen, signerer den med dit Apple-ID og lægger den på iPhonen. Hold iPhonen ulåst imens.",
                 doneNote: rec.map { "Version \($0.version)" }),
            Step(id: 7, title: "Stol på dit Apple-ID på iPhonen", time: "1 min",
                 done: rec?.trusted == true,
                 detail: "Kun første gang. På iPhonen: Indstillinger > Generelt > VPN og enhedsadministration > \(inst.signer ?? "Apple Development: din e-mail") > Stol på. Tryk så på knappen her, så åbner Viggo+ på iPhonen.",
                 actions: d.map { dev in [("Åbn Viggo+ på iPhonen", { Task { await inst.launch(dev) } })] } ?? []),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let job = inst.job { JobCard(job: job) }
                if let rec = inst.record, inst.job == nil { StatusCard(rec: rec) }
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
                if inst.job == nil { await inst.refresh() }
                try? await Task.sleep(for: .seconds(4))
            }
        }
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
                bullet("Et gratis Apple-ID kan have appen på højst 3 iPhones.")
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
            ForEach(all) { s in
                StepRow(n: s.id, title: s.title, time: s.time, done: s.done, current: s.id == current,
                        detail: s.detail, doneNote: s.doneNote, actions: s.actions,
                        install: s.id == 6 && s.id == current ? installButton : nil)
                if s.id != all.last?.id { Divider().padding(.leading, 34) }
            }
            if current == nil {
                Label("Viggo+ er klar på iPhonen", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green).font(.callout.weight(.semibold)).padding(.top, 10)
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
                if let d = inst.device, inst.record != nil {
                    Button("Overfør login nu") { Task { await inst.sendLogin(to: d) } }
                        .disabled(inst.job != nil || !d.reachable || t.isEmpty)
                }
            }
            Toggle("Overfør mit login fra Mac'en, når appen installeres", isOn: $inst.sendLoginOnInstall)
            Group {
                if let who {
                    Text("Sender \(who)\(t.friends.isEmpty ? "" : (t.friends.count == 1 ? " og din ven" : " og dine \(t.friends.count) venner")), så iPhone-appen er logget ind med det samme. Det går direkte over kablet eller wifi til Viggo+ på iPhonen, som sletter filen så snart den er læst.")
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
    let rec: PhoneInstaller.Record

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
            if let d = inst.device {
                Button("Forny nu") { Task { await inst.install(d) } }
                    .disabled(inst.job != nil || !d.reachable)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.08)))
    }

    /// How the Mac can reach the phone right now, and when it was last renewed.
    private var connection: some View {
        let d = inst.devices.first { $0.name == rec.name } ?? inst.device
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
