import SwiftUI

/// Viggo's messages on the Mac, like Mail: the inbox on the left, the thread on the right.
struct MessagesWindow: View {
    @EnvironmentObject var state: AppState
    @StateObject private var inbox = Inbox.shared
    @State private var search = ""
    @State private var composing = false
    @State private var composeTo: [Person] = []
    /// Indbakke or Sendt. A thread you start is only in Sendt until someone answers.
    @State private var folder: Folder = .inbox
    enum Folder: String { case inbox, sent }

    private var list: [MessageThread] { folder == .inbox ? inbox.threads : inbox.sent }
    private var listLoading: Bool { folder == .inbox ? inbox.loading : inbox.sentLoading }
    private var me: Int? { state.profile?.id }

    private var shown: [MessageThread] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return list }
        return list.filter { t in
            "\(t.sender) \(inbox.counterpart(t.id, me: me) ?? "") \(t.subject) \(t.preview)".lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $inbox.selected) {
                if let e = inbox.error {
                    Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                ForEach(shown) { t in
                    MacThreadRow(t: t, title: folder == .sent ? inbox.counterpart(t.id, me: me) : nil).tag(t.id)
                }
            }
            .overlay {
                if list.isEmpty, listLoading {
                    SkeletonRows(count: 9, avatar: 32).padding(.horizontal, 14).frame(maxHeight: .infinity, alignment: .top)
                        .transition(.opacity)
                }
                else if !list.isEmpty, shown.isEmpty { ContentUnavailableView.search(text: search) }
                else if list.isEmpty, folder == .sent {
                    ContentUnavailableView("Ingen sendte beskeder", systemImage: "paperplane",
                                           description: Text("Beskeder du skriver, kommer her, også før nogen har svaret."))
                }
            }
            .animation(.viggo, value: list.isEmpty)
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("", selection: $folder) {
                    Text("Indbakke").tag(Folder.inbox)
                    Text("Sendt").tag(Folder.sent)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 4)
            }
            .task(id: folder) { if folder == .sent { await inbox.loadSent() } }
            .searchable(text: $search, placement: .sidebar, prompt: folder == .inbox ? "Søg i beskeder" : "Søg i sendte")
            .navigationSplitViewColumnWidth(min: 280, ideal: 330, max: 440)
        } detail: {
            if let id = inbox.selected {
                MacThreadView(id: id).id(id)
            } else {
                ContentUnavailableView("Vælg en besked", systemImage: "bubble.left.and.bubble.right",
                                       description: Text("Eller skriv en ny med blyanten foroven."))
            }
        }
        .toolbar {
            ToolbarItem {
                Button { Task { if folder == .inbox { await inbox.load() } else { await inbox.loadSent() } } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Hent beskeder")
            }
            ToolbarItem {
                Button { composeTo = []; composing = true } label: { Image(systemName: "square.and.pencil") }
                    .help("Ny besked")
                    .keyboardShortcut("n")
            }
        }
        .sheet(isPresented: $composing) { MacCompose(to: composeTo) }
        .onReceive(state.$composeTo) { p in
            guard let p else { return }
            composeTo = p
            composing = true
            state.composeTo = nil
        }
        .task { await inbox.load() }
        .frame(minWidth: 760, minHeight: 480)
        .tint(Fomo.accent)
        .overlay(alignment: .top) { StatusPillView(compact: true).padding(.top, 10) }
    }
}

private struct MacThreadRow: View {
    let t: MessageThread
    /// In Sendt: who it went to ("Til Emilie, Jonas"), when the thread is known.
    var title: String? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar(url: t.image, size: 34, name: t.sender)
                .overlay(alignment: .topLeading) {
                    if t.unread { Circle().fill(Color.accentColor).frame(width: 9, height: 9).offset(x: -3, y: -2) }
                }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title ?? t.sender).font(.system(size: 13, weight: t.unread ? .bold : .semibold)).lineLimit(1)
                    if title == nil, t.others > 0 { Text("+\(t.others)").font(.system(size: 11)).foregroundStyle(.secondary) }
                    Spacer()
                    Text(t.when).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(t.subject).font(.system(size: 12, weight: t.unread ? .semibold : .regular)).lineLimit(1)
                Text(t.preview).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct MacThreadView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var inbox = Inbox.shared
    let id: Int
    @State private var detail: ThreadDetail?
    @State private var failed = false
    @State private var draft = ""
    @State private var kind: ReplyKind = .sender
    @State private var sending = false
    @State private var sendError: String?

    private var me: Int { state.profile?.id ?? -1 }
    private var firstSender: String {
        detail?.messages.first { $0.authorID != me }?.author.components(separatedBy: " ").first ?? "afsender"
    }
    private var group: Bool { detail?.canReplyAll == true && (detail?.to.count ?? 0) > 1 }

    var body: some View {
        VStack(spacing: 0) {
            if let d = detail {
                DeadlineSuggestion(source: "tråd:\(d.id)")
                    .frame(maxWidth: 720).padding(.horizontal, 20).padding(.top, 10)
                RosterCard(detail: d, padding: EdgeInsets(top: 8, leading: 20, bottom: 0, trailing: 20), maxWidth: 720)
                // Reads the thread's PDFs for your name (the stack has no spacing, so this takes no room).
                Color.clear.frame(height: 0).task(id: d.id) { await RosterStore.shared.check(d) }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    if let d = detail {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(d.subject).font(.system(size: 22, weight: .bold)).textSelection(.enabled)
                                if !d.to.isEmpty {
                                    Text("Til \(d.to.prefix(4).joined(separator: ", "))\(d.to.count > 4 ? " og \(d.to.count - 4) andre" : "")")
                                        .font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.bottom, 4)
                            ForEach(d.messages) { m in MacBubble(m: m, mine: m.authorID == me, subject: d.subject).id(m.id) }
                        }
                        .padding(20)
                        .frame(maxWidth: 760, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    } else if failed {
                        ContentUnavailableView("Kunne ikke åbne beskeden", systemImage: "exclamationmark.bubble").padding(.top, 80)
                    } else {
                        SkeletonRows(count: 5, avatar: 28).padding(24).frame(maxWidth: .infinity)
                    }
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: detail?.messages.count) { _, _ in
                    if let last = detail?.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            if detail != nil {
                Divider()
                replyBar
            }
        }
        .navigationTitle(detail?.subject ?? "Beskeder")
        .task { await load() }
        .alert("Beskeden blev ikke sendt", isPresented: .constant(sendError != nil)) {
            Button("OK") { sendError = nil }
        } message: { Text(sendError ?? "") }
    }

    private func load() async {
        do {
            detail = try await inbox.open(id)
            kind = group ? .sender : .all
        } catch { failed = true }
    }

    private var replyBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if group {
                Picker("", selection: $kind) {
                    Text("Kun \(firstSender)").tag(ReplyKind.sender)
                    Text("Svar alle").tag(ReplyKind.all)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField(kind == .all ? "Svar alle" : "Svar \(firstSender)", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...8)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.primary.opacity(0.06)))
                    .onSubmit { Task { await send() } }
                Button { Task { await send() } } label: {
                    if sending { ProgressView().controlSize(.small).frame(width: 26, height: 26) }
                    else { Image(systemName: "arrow.up.circle.fill").font(.system(size: 26)) }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                .help("Send (⌘↩)")
            }
        }
        .padding(12)
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        defer { sending = false }
        do {
            try await inbox.reply(id, kind: kind, text: text)
            draft = ""
            if let d = try? await inbox.open(id) { withAnimation(.viggo) { detail = d } }
        } catch {
            sendError = (error as? LocalizedError)?.errorDescription ?? "Prøv igen."
        }
    }
}

struct MacBubble: View {
    let m: ThreadMessage
    let mine: Bool
    var subject = ""
    /// A time clicked in the message, on its way to the schedule.
    @State private var plan: PlanDraft?
    private var personal: Bool { m.privateWith != nil }
    private var onAccent: Bool { mine && !personal }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if mine { Spacer(minLength: 80) } else { Avatar(url: m.image, size: 28, name: m.author) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                Text(mine ? m.date : "\(m.author) · \(m.date)").font(.system(size: 11)).foregroundStyle(.secondary)
                if let p = m.privateWith {
                    Label(mine ? "Privat til \(p)" : "Privat besked til dig", systemImage: "lock.fill")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.indigo)
                }
                ForEach(m.files.filter(\.isImage)) { f in MacFileImage(f: f) }
                ForEach(m.files.filter { !$0.isImage }) { f in MacFileChip(f: f) }
                if !m.text.isEmpty || !m.links.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if !m.text.isEmpty {
                        MacMessageText(text: m.text, posted: m.sentAt, subject: subject, onAccent: onAccent) { plan = $0 }
                            .popover(item: $plan, arrowEdge: .bottom) { d in PlanSheet(draft: d) { plan = nil } }
                    }
                    ForEach(m.links, id: \.self) { u in
                        Link(destination: u) {
                            Label(u.host?.replacingOccurrences(of: "www.", with: "") ?? "Link", systemImage: "arrow.up.right.square")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(mine && !personal ? Color.white : Color.accentColor)
                    }
                }
                .padding(.horizontal, 13).padding(.vertical, 9)
                .foregroundStyle(mine && !personal ? Color.white : Color.primary)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(personal ? Color.indigo.opacity(0.1) : mine ? Color.accentColor : Color.primary.opacity(0.07)))
                // A personal answer in a group thread: outlined, so it is clear only one person sees it.
                .overlay {
                    if personal {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.indigo.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    }
                }
                }
            }
            if !mine { Spacer(minLength: 60) }
        }
    }
}

/// Fetches an attachment with your Viggo login and saves it in a temporary folder.
private func fetchAttachment(_ f: MessageFile) async -> URL? {
    guard let d = try? await AppState.shared.client.data(f.url) else { return nil }
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("Viggo+ \(f.id) " + f.name.replacingOccurrences(of: "/", with: "-"))
    return (try? d.write(to: u, options: .atomic)) != nil ? u : nil
}

/// A picture sent in a message. Click to open it in Preview.
private struct MacFileImage: View {
    let f: MessageFile
    @State private var image: NSImage?
    @State private var failed = false
    private static let cache = NSCache<NSURL, NSImage>()

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(maxWidth: 320, maxHeight: 380)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onTapGesture { Task { if let u = await fetchAttachment(f) { NSWorkspace.shared.open(u) } } }
                    .help("Åbn \(f.name)")
            } else if failed {
                MacFileChip(f: f)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.07))
                    .frame(width: 200, height: 150).shimmer()
            }
        }
        .task(id: f.url) {
            if let hit = Self.cache.object(forKey: f.url as NSURL) { image = hit; return }
            if let d = try? await AppState.shared.client.data(f.url), let img = NSImage(data: d) {
                Self.cache.setObject(img, forKey: f.url as NSURL)
                withAnimation(.viggo) { image = img }
            } else { failed = true }
        }
    }
}

/// Any other file sent in a message. Click to fetch and open it.
private struct MacFileChip: View {
    let f: MessageFile
    @State private var loading = false
    var body: some View {
        Button {
            loading = true
            Task { if let u = await fetchAttachment(f) { NSWorkspace.shared.open(u) }; loading = false }
        } label: {
            HStack(spacing: 8) {
                if loading { ProgressView().controlSize(.small) } else { Image(systemName: "doc") }
                Text(f.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }
}

private struct MacCompose: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var inbox = Inbox.shared
    @State private var to: [Person]
    @State private var query = ""
    @State private var subject = ""
    @State private var text = ""
    @State private var sending = false
    @State private var sendError: String?

    init(to: [Person] = []) { _to = State(initialValue: to) }

    private var matches: [Person] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return inbox.people.filter { p in
            !to.contains(p) && (p.name.lowercased().hasPrefix(q) || p.name.lowercased().split(separator: " ").contains { $0.hasPrefix(q) })
        }.prefix(8).map { $0 }
    }
    private var groupMatches: [PersonGroup] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 2 else { return [] }
        return inbox.groups.filter { $0.name.lowercased().contains(q) }.prefix(4).map { $0 }
    }
    private var ready: Bool {
        !to.isEmpty && !subject.trimmingCharacters(in: .whitespaces).isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ny besked").font(.system(size: 17, weight: .bold))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Til:").foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    if !to.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(to) { p in
                                    HStack(spacing: 5) {
                                        Avatar(url: p.image, size: 18, name: p.name)
                                        Text(p.name).font(.system(size: 12, weight: .medium))
                                        Button { to.removeAll { $0 == p } } label: { Image(systemName: "xmark.circle.fill") }
                                            .buttonStyle(.plain).foregroundStyle(.secondary)
                                    }
                                    .padding(.leading, 3).padding(.trailing, 7).padding(.vertical, 3)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                                }
                            }
                        }
                    }
                    TextField(inbox.people.isEmpty ? "Henter elever og lærere" : "Søg efter navn eller gruppe", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { if let p = matches.first { to.append(p); query = "" } }
                }
            }
            if !matches.isEmpty || !groupMatches.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(matches) { p in
                        Button { to.append(p); query = "" } label: {
                            HStack(spacing: 8) {
                                Avatar(url: p.image, size: 24, name: p.name)
                                Text(p.name)
                                if !p.info.isEmpty { Text(p.info).font(.system(size: 11)).foregroundStyle(.secondary) }
                                Spacer()
                            }
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(groupMatches) { g in
                        Button {
                            to.append(contentsOf: inbox.people.filter { g.members.contains($0.id) && !to.contains($0) }); query = ""
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "person.3.fill").frame(width: 24, height: 24)
                                    .background(Circle().fill(Color.accentColor.opacity(0.15)))
                                Text(g.name)
                                Text("\(g.members.count) personer").font(.system(size: 11)).foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.05)))
                .padding(.leading, 52)
            }
            HStack(spacing: 8) {
                Text("Emne:").foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                TextField("Hvad handler det om?", text: $subject).textFieldStyle(.roundedBorder)
            }
            TextEditor(text: $text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.05)))
                .frame(minHeight: 200)
            HStack {
                Spacer()
                Button("Annuller") { dismiss() }.keyboardShortcut(.cancelAction)
                Button { Task { await send() } } label: {
                    Text(sending ? "Sender..." : "Send")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!ready || sending)
            }
        }
        .padding(20)
        .frame(width: 560)
        .task { await inbox.loadDirectory() }
        .alert("Beskeden blev ikke sendt", isPresented: .constant(sendError != nil)) {
            Button("OK") { sendError = nil }
        } message: { Text(sendError ?? "") }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        do {
            try await inbox.send(to: to.map(\.id), subject: subject, text: text)
            dismiss()
        } catch {
            sendError = (error as? LocalizedError)?.errorDescription ?? "Prøv igen."
        }
    }
}


/// The text of a message, selectable, with times and days marked. AppKit draws it: a click on a
/// marked time is a plain NSTextView link click, which (unlike a link in SwiftUI's Text) is
/// reliable and can be tested, and it opens PlanSheet instead of a browser.
struct MacMessageText: NSViewRepresentable {
    let text: String
    let posted: Date?
    let subject: String
    let onAccent: Bool
    let onPlan: (PlanDraft) -> Void

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onPlan: (PlanDraft) -> Void = { _ in }
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let u = link as? URL, let d = PlanDraft(url: u) else { return false }
            if CommandLine.arguments.contains("--plan-test") { print("[plan] link klikket: \(d.title)") }
            onPlan(d)
            return true
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    /// A click on a time works even when the window is in the background, like a button.
    final class LinkTextView: NSTextView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    func makeNSView(context: Context) -> NSTextView {
        let tv = LinkTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.isHorizontallyResizable = false
        tv.delegate = context.coordinator
        tv.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return tv
    }

    func updateNSView(_ tv: NSTextView, context: Context) {
        context.coordinator.onPlan = onPlan
        let s = attributed()
        if tv.attributedString() != s { tv.textStorage?.setAttributedString(s) }
        tv.linkTextAttributes = [.foregroundColor: onAccent ? NSColor.white : NSColor.controlAccentColor,
                                 .cursor: NSCursor.pointingHand]
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView tv: NSTextView, context: Context) -> CGSize? {
        let maxW = min(proposal.width ?? 520, 520)
        let r = attributed().boundingRect(with: NSSize(width: maxW, height: .greatestFiniteMagnitude),
                                          options: [.usesLineFragmentOrigin, .usesFontLeading])
        return CGSize(width: ceil(min(r.width, maxW)) + 1, height: ceil(r.height))
    }

    private func attributed() -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 13)
        let out = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: onAccent ? NSColor.white : NSColor.labelColor])
        for (r, url) in Deadlines.planLinks(text: text, posted: posted, subject: subject) {
            out.addAttributes([.font: NSFont.boldSystemFont(ofSize: 13),
                               .backgroundColor: onAccent ? NSColor.white.withAlphaComponent(0.22) : NSColor.controlAccentColor.withAlphaComponent(0.16)], range: r)
            if let url { out.addAttribute(.link, value: url, range: r) }
        }
        return out
    }
}
