import SwiftUI

/// Viggo's messages on the Mac, like Mail: the inbox on the left, the thread on the right.
struct MessagesWindow: View {
    @EnvironmentObject var state: AppState
    @StateObject private var inbox = Inbox.shared
    @State private var search = ""
    @State private var composing = false

    private var shown: [MessageThread] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return inbox.threads }
        return inbox.threads.filter { "\($0.sender) \($0.subject) \($0.preview)".lowercased().contains(q) }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $inbox.selected) {
                if let e = inbox.error {
                    Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                ForEach(shown) { t in MacThreadRow(t: t).tag(t.id) }
            }
            .overlay {
                if inbox.threads.isEmpty, inbox.loading { ProgressView() }
                else if !inbox.threads.isEmpty, shown.isEmpty { ContentUnavailableView.search(text: search) }
            }
            .searchable(text: $search, placement: .sidebar, prompt: "Søg i beskeder")
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
                Button { Task { await inbox.load() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Hent beskeder")
            }
            ToolbarItem {
                Button { composing = true } label: { Image(systemName: "square.and.pencil") }
                    .help("Ny besked")
                    .keyboardShortcut("n")
            }
        }
        .sheet(isPresented: $composing) { MacCompose() }
        .task { await inbox.load() }
        .frame(minWidth: 760, minHeight: 480)
    }
}

private struct MacThreadRow: View {
    let t: MessageThread
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar(url: t.image, size: 34, name: t.sender)
                .overlay(alignment: .topLeading) {
                    if t.unread { Circle().fill(Color.accentColor).frame(width: 9, height: 9).offset(x: -3, y: -2) }
                }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(t.sender).font(.system(size: 13, weight: t.unread ? .bold : .semibold)).lineLimit(1)
                    if t.others > 0 { Text("+\(t.others)").font(.system(size: 11)).foregroundStyle(.secondary) }
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
                            ForEach(d.messages) { m in MacBubble(m: m, mine: m.authorID == me).id(m.id) }
                        }
                        .padding(20)
                        .frame(maxWidth: 760, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    } else if failed {
                        ContentUnavailableView("Kunne ikke åbne beskeden", systemImage: "exclamationmark.bubble").padding(.top, 80)
                    } else {
                        ProgressView().padding(.top, 80).frame(maxWidth: .infinity)
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

private struct MacBubble: View {
    let m: ThreadMessage
    let mine: Bool
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if mine { Spacer(minLength: 80) } else { Avatar(url: m.image, size: 28, name: m.author) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                Text(mine ? m.date : "\(m.author) · \(m.date)").font(.system(size: 11)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Text(m.text).font(.system(size: 13)).textSelection(.enabled)
                    ForEach(m.links, id: \.self) { u in
                        Link(destination: u) {
                            Label(u.host?.replacingOccurrences(of: "www.", with: "") ?? "Link", systemImage: "arrow.up.right.square")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(mine ? Color.white : Color.accentColor)
                    }
                }
                .padding(.horizontal, 13).padding(.vertical, 9)
                .foregroundStyle(mine ? Color.white : Color.primary)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(mine ? Color.accentColor : Color.primary.opacity(0.07)))
            }
            if !mine { Spacer(minLength: 60) }
        }
    }
}

private struct MacCompose: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var inbox = Inbox.shared
    @State private var to: [Person] = []
    @State private var query = ""
    @State private var subject = ""
    @State private var text = ""
    @State private var sending = false
    @State private var sendError: String?

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
                    if sending { ProgressView().controlSize(.small) } else { Text("Send") }
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
