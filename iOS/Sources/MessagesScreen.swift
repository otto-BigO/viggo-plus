import SwiftUI

// MARK: - Inbox list

struct MessagesScreen: View {
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
        NavigationStack {
            List {
                if let e = inbox.error {
                    Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                ForEach(shown) { t in
                    NavigationLink(value: t.id) { ThreadRow(t: t) }
                }
            }
            .listStyle(.plain)
            .overlay {
                if inbox.threads.isEmpty {
                    if inbox.loading { ProgressView("Henter beskeder") }
                    else if inbox.error == nil { ContentUnavailableView("Ingen beskeder", systemImage: "tray") }
                } else if shown.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .navigationTitle("Beskeder")
            .navigationDestination(for: Int.self) { ThreadScreen(id: $0) }
            .searchable(text: $search, prompt: "Søg i beskeder")
            .refreshable { await inbox.load() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { composing = true } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("Ny besked")
                }
            }
            .sheet(isPresented: $composing) { ComposeScreen() }
            .task { if inbox.threads.isEmpty { await inbox.load() } }
        }
    }
}

private struct ThreadRow: View {
    let t: MessageThread
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .topLeading) {
                Avatar(url: t.image, size: 44, name: t.sender)
                if t.unread {
                    Circle().fill(Color.accentColor).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                        .offset(x: -3, y: -3)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(t.sender).font(.body.weight(t.unread ? .bold : .semibold)).lineLimit(1)
                    if t.others > 0 {
                        Text("+\(t.others)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(t.when).font(.caption).foregroundStyle(t.unread ? Color.accentColor : .secondary).lineLimit(1)
                }
                Text(t.subject).font(.subheadline.weight(t.unread ? .semibold : .regular)).lineLimit(1)
                Text(t.preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - A thread

struct ThreadScreen: View {
    @EnvironmentObject var state: AppState
    @StateObject private var inbox = Inbox.shared
    let id: Int
    @State private var detail: ThreadDetail?
    @State private var failed = false
    @State private var draft = ""
    @State private var kind: ReplyKind = .all
    @State private var sending = false
    @State private var sendError: String?
    @FocusState private var typing: Bool

    private var me: Int { state.profile?.id ?? -1 }
    private var firstSender: String {
        detail?.messages.first { $0.authorID != me }?.author.components(separatedBy: " ").first ?? "afsender"
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if let d = detail {
                    VStack(alignment: .leading, spacing: 14) {
                        header(d)
                        ForEach(d.messages) { m in
                            Bubble(m: m, mine: m.authorID == me).id(m.id)
                        }
                    }
                    .padding(16)
                } else if failed {
                    ContentUnavailableView("Kunne ikke åbne beskeden", systemImage: "exclamationmark.bubble")
                        .padding(.top, 80)
                } else {
                    ProgressView().padding(.top, 80).frame(maxWidth: .infinity)
                }
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { if detail != nil { replyBar } }
            .onChange(of: detail?.messages.count) { _, _ in
                if let last = detail?.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(detail?.subject ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("Beskeden blev ikke sendt", isPresented: .constant(sendError != nil)) {
            Button("OK") { sendError = nil }
        } message: { Text(sendError ?? "") }
    }

    private func load() async {
        do { detail = try await inbox.open(id); kind = detail?.canReplyAll == true && (detail?.to.count ?? 0) <= 1 ? .all : .sender }
        catch { failed = true }
    }

    private func header(_ d: ThreadDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(d.subject).font(.title2.bold())
            if !d.to.isEmpty {
                Text("Til \(d.to.prefix(3).joined(separator: ", "))\(d.to.count > 3 ? " og \(d.to.count - 3) andre" : "")")
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.bottom, 4)
    }

    private var replyBar: some View {
        VStack(spacing: 6) {
            if detail?.canReplyAll == true, (detail?.to.count ?? 0) > 1 {
                Picker("Svar", selection: $kind) {
                    Text("Svar alle").tag(ReplyKind.all)
                    Text("Kun \(firstSender)").tag(ReplyKind.sender)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(kind == .all ? "Svar alle" : "Svar \(firstSender)", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($typing)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                Button { Task { await send() } } label: {
                    if sending { ProgressView().frame(width: 34, height: 34) }
                    else { Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)) }
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        defer { sending = false }
        do {
            try await inbox.reply(id, kind: kind, text: text)
            draft = ""
            typing = false
            if let d = try? await inbox.open(id) { withAnimation(.viggo) { detail = d } }
        } catch {
            sendError = (error as? LocalizedError)?.errorDescription ?? "Prøv igen."
        }
    }
}

private struct Bubble: View {
    let m: ThreadMessage
    let mine: Bool
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if mine { Spacer(minLength: 40) } else { Avatar(url: m.image, size: 30, name: m.author) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                Text(mine ? m.date : "\(m.author) · \(m.date)").font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Text(m.text).font(.body).textSelection(.enabled)
                    ForEach(m.links, id: \.self) { u in
                        Link(destination: u) {
                            Label(u.host?.replacingOccurrences(of: "www.", with: "") ?? "Link", systemImage: "arrow.up.right.square")
                                .font(.subheadline.weight(.medium))
                        }
                        .tint(mine ? .white : .accentColor)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .foregroundStyle(mine ? .white : .primary)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(mine ? Color.accentColor : Color(.secondarySystemGroupedBackground)))
            }
            if !mine { Spacer(minLength: 24) }
        }
    }
}

// MARK: - New message

struct ComposeScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var inbox = Inbox.shared
    @State private var to: [Person] = []
    @State private var query = ""
    @State private var subject = ""
    @State private var text = ""
    @State private var sending = false
    @State private var sendError: String?
    @FocusState private var searching: Bool

    private var matches: [Person] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return inbox.people.filter { p in !to.contains(p) && p.name.lowercased().split(separator: " ").contains { $0.hasPrefix(q) } || p.name.lowercased().hasPrefix(q) }
            .filter { !to.contains($0) }.prefix(20).map { $0 }
    }
    private var groupMatches: [PersonGroup] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 2 else { return [] }
        return inbox.groups.filter { $0.name.lowercased().contains(q) }.prefix(6).map { $0 }
    }
    private var ready: Bool {
        !to.isEmpty && !subject.trimmingCharacters(in: .whitespaces).isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Til") {
                    if !to.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(to) { p in
                                    HStack(spacing: 6) {
                                        Avatar(url: p.image, size: 22, name: p.name)
                                        Text(p.firstName).font(.subheadline.weight(.medium))
                                        Button { to.removeAll { $0 == p } } label: {
                                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.leading, 4).padding(.trailing, 8).padding(.vertical, 4)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                                }
                            }
                        }
                    }
                    TextField(inbox.people.isEmpty ? "Henter elever og lærere" : "Søg efter navn eller gruppe", text: $query)
                        .focused($searching)
                        .onAppear { searching = true }
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    ForEach(matches) { p in
                        Button { to.append(p); query = ""; searching = true } label: {
                            HStack(spacing: 10) {
                                Avatar(url: p.image, size: 32, name: p.name)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.name).foregroundStyle(.primary)
                                    if !p.info.isEmpty { Text(p.info).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                    .tint(.primary)
                    ForEach(groupMatches) { g in
                        Button {
                            let add = inbox.people.filter { g.members.contains($0.id) && !to.contains($0) }
                            to.append(contentsOf: add); query = ""
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "person.3.fill").frame(width: 32, height: 32)
                                    .background(Circle().fill(Color.accentColor.opacity(0.15)))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(g.name).foregroundStyle(.primary)
                                    Text("\(g.members.count) personer").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section("Emne") {
                    TextField("Hvad handler det om?", text: $subject)
                }
                Section("Besked") {
                    TextField("Skriv din besked", text: $text, axis: .vertical).lineLimit(6...20)
                }
            }
            .navigationTitle("Ny besked")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuller") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if sending { ProgressView() }
                    else { Button("Send") { Task { await send() } }.disabled(!ready).fontWeight(.semibold) }
                }
            }
            .task { await inbox.loadDirectory() }
            .alert("Beskeden blev ikke sendt", isPresented: .constant(sendError != nil)) {
                Button("OK") { sendError = nil }
            } message: { Text(sendError ?? "") }
        }
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
