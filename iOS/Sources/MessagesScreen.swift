import SwiftUI

// MARK: - Inbox list

struct MessagesScreen: View {
    @EnvironmentObject var state: AppState
    @StateObject private var inbox = Inbox.shared
    @State private var search = ""
    @State private var composing = false
    @State private var path: [Int] = []

    private var searching: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }
    private var shown: [MessageThread] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return inbox.otherThreads }
        return inbox.threads.filter { "\($0.sender) \($0.subject) \($0.preview)".lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let e = inbox.error {
                    Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                if !searching, !inbox.pinnedThreads.isEmpty {
                    PinnedGrid(threads: inbox.pinnedThreads) { path.append($0) }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 4, trailing: 12))
                }
                ForEach(shown) { t in
                    NavigationLink(value: t.id) { ThreadRow(t: t) }
                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 16))
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 76 }
                        .swipeActions(edge: .leading) { pinButton(t) }
                        .contextMenu { pinButton(t) } preview: { ThreadPreview(t: t) }
                }
            }
            .listStyle(.plain)
            .animation(.viggo, value: inbox.pinned)
            .animation(.viggo, value: inbox.threads)
            .overlay {
                if inbox.threads.isEmpty {
                    if inbox.loading { ProgressView("Henter beskeder") }
                    else if inbox.error == nil { ContentUnavailableView("Ingen beskeder", systemImage: "tray") }
                } else if searching, shown.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .navigationTitle("Beskeder")
            .navigationDestination(for: Int.self) { ThreadScreen(id: $0) }
            .navigationDestination(for: Found.self) { FoundScreen(found: $0) }
            .searchable(text: $search, prompt: "Søg")
            .refreshable { await inbox.load(); Haptic.soft() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { SearchButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Haptic.tap(); composing = true } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("Ny besked")
                }
            }
            .sheet(isPresented: $composing) { ComposeScreen() }
            .task { if inbox.threads.isEmpty { await inbox.load() } }
        }
    }

    private func pinButton(_ t: MessageThread) -> some View {
        let on = inbox.isPinned(t.id)
        return Button {
            Haptic.firm()
            withAnimation(.viggo) { inbox.togglePin(t.id) }
        } label: {
            Label(on ? "Frigør" : "Fastgør", systemImage: on ? "pin.slash.fill" : "pin.fill")
        }
        .tint(.yellow)
    }
}

/// Pinned threads as big round pictures on top, like pinned chats in Beskeder.
private struct PinnedGrid: View {
    @StateObject private var inbox = Inbox.shared
    let threads: [MessageThread]
    let open: (Int) -> Void
    private let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: cols, spacing: 14) {
            ForEach(threads) { t in
                Button { Haptic.tap(); open(t.id) } label: {
                    VStack(spacing: 6) {
                        Avatar(url: t.image, size: 70, name: t.sender)
                            .overlay(alignment: .topLeading) {
                                if t.unread {
                                    Circle().fill(Color.accentColor).frame(width: 16, height: 16)
                                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 3))
                                        .transition(.scale)
                                }
                            }
                            .overlay(alignment: .top) {
                                if t.unread {
                                    Text(t.preview).font(.caption2).lineLimit(2)
                                        .padding(.horizontal, 7).padding(.vertical, 4)
                                        .frame(maxWidth: 110)
                                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .offset(y: -22)
                                }
                            }
                        Text(t.sender.components(separatedBy: " ").first ?? t.sender)
                            .font(.caption.weight(t.unread ? .semibold : .regular)).lineLimit(1)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScale(scale: 0.92))
                .contextMenu {
                    Button { Haptic.firm(); withAnimation(.viggo) { inbox.togglePin(t.id) } } label: {
                        Label("Frigør", systemImage: "pin.slash.fill")
                    }
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .padding(.vertical, 6)
    }
}

private struct ThreadRow: View {
    @StateObject private var inbox = Inbox.shared
    let t: MessageThread
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle().fill(t.unread ? Color.accentColor : .clear).frame(width: 10, height: 10)
            Avatar(url: t.image, size: 50, name: t.sender)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(t.sender).font(.body.weight(.semibold)).lineLimit(1)
                    if t.others > 0 {
                        Text("+\(t.others)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Text(t.when.shortWhen).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                }
                Text(t.subject).font(.subheadline.weight(t.unread ? .semibold : .regular))
                    .foregroundStyle(t.unread ? .primary : .secondary).lineLimit(1)
                Text(t.preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 8)
    }
}

/// Long-press preview of a thread in the list.
private struct ThreadPreview: View {
    let t: MessageThread
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Avatar(url: t.image, size: 36, name: t.sender)
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.sender).font(.headline)
                    Text(t.when).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(t.subject).font(.subheadline.weight(.semibold))
            Text(t.preview).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
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
    @State private var sending: String?
    @State private var sendError: String?
    @FocusState private var typing: Bool

    private var me: Int { state.profile?.id ?? -1 }
    private var other: ThreadMessage? { detail?.messages.first { $0.authorID != me } }
    private var firstSender: String { other?.author.components(separatedBy: " ").first ?? "afsender" }
    private var group: Bool { (detail?.to.count ?? 0) > 1 }
    private var empty: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if let d = detail {
                    LazyVStack(spacing: 2) {
                        header(d)
                        ForEach(Array(d.messages.enumerated()), id: \.element.id) { i, m in
                            let prev = i > 0 ? d.messages[i - 1] : nil
                            let next = i + 1 < d.messages.count ? d.messages[i + 1] : nil
                            let first = prev?.authorID != m.authorID
                            let last = next?.authorID != m.authorID
                            if first {
                                Text(m.date.replacingOccurrences(of: " \(DateUtil.cal.component(.year, from: Date()))", with: ""))
                                    .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity).padding(.top, 14).padding(.bottom, 4)
                            }
                            Bubble(m: m, mine: m.authorID == me, showName: first && group && m.authorID != me,
                                   tail: last)
                                .id(m.id)
                                .padding(.bottom, last ? 6 : 0)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        if let s = sending {
                            Bubble(m: ThreadMessage(id: -1, authorID: me, author: "", image: nil, date: "", text: s, links: []),
                                   mine: true, showName: false, tail: true)
                                .opacity(0.6)
                                .id(-1)
                                .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
                            Text("Sender…").font(.caption2).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 6)
                        }
                    }
                    .padding(.horizontal, 12).padding(.bottom, 8)
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
                if let last = detail?.messages.last { withAnimation(.viggo) { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            .onChange(of: sending) { _, s in
                if s != nil { withAnimation(.viggo) { proxy.scrollTo(-1, anchor: .bottom) } }
            }
            .onChange(of: typing) { _, t in
                if t, let last = detail?.messages.last { withAnimation(.viggo) { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                // Tap the sender to see who they are.
                NavigationLink(value: Found.person(other?.authorID ?? 0)) {
                    VStack(spacing: 2) {
                        Avatar(url: other?.image, size: 28, name: other?.author)
                        Text(group ? "\(firstSender) +\((detail?.to.count ?? 1) - 1)" : (other?.author ?? ""))
                            .font(.caption2.weight(.semibold)).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(other == nil)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { Haptic.firm(); withAnimation(.viggo) { inbox.togglePin(id) } } label: {
                    Image(systemName: inbox.isPinned(id) ? "pin.fill" : "pin")
                        .contentTransition(.symbolEffect(.replace))
                }
                .tint(inbox.isPinned(id) ? .yellow : .accentColor)
                .accessibilityLabel(inbox.isPinned(id) ? "Frigør" : "Fastgør")
            }
        }
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
        VStack(spacing: 4) {
            Text(d.subject).font(.headline).multilineTextAlignment(.center)
            if !d.to.isEmpty {
                Text("Til \(d.to.prefix(3).joined(separator: ", "))\(d.to.count > 3 ? " og \(d.to.count - 3) andre" : "")")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.top, 12)
    }

    private var replyBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if detail?.canReplyAll == true, group {
                Menu {
                    Picker("Svar", selection: $kind) {
                        Label("Svar alle", systemImage: "person.2.fill").tag(ReplyKind.all)
                        Label("Kun \(firstSender)", systemImage: "person.fill").tag(ReplyKind.sender)
                    }
                } label: {
                    Image(systemName: kind == .all ? "person.2.fill" : "person.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color(.tertiarySystemFill)))
                }
                .onChange(of: kind) { Haptic.select() }
            }
            HStack(alignment: .bottom, spacing: 4) {
                TextField(kind == .all ? "Svar alle" : "Svar \(firstSender)", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($typing)
                    .padding(.leading, 14).padding(.vertical, 8)
                if !empty || sending != nil {
                    Button { Task { await send() } } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                    }
                    .disabled(empty || sending != nil)
                    .padding(.bottom, 3)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .padding(.trailing, 3)
            .frame(minHeight: 36)
            .background(RoundedRectangle(cornerRadius: 19, style: .continuous).fill(Color(.systemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).strokeBorder(Color(.separator), lineWidth: 1))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: empty)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(.bar)
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Haptic.tap()
        withAnimation(.viggo) { sending = text; draft = "" }
        do {
            try await inbox.reply(id, kind: kind, text: text)
            let d = try? await inbox.open(id)
            Haptic.success()
            withAnimation(.viggo) { sending = nil; if let d { detail = d } }
        } catch {
            Haptic.error()
            withAnimation(.viggo) { sending = nil; draft = text }
            Haptic.error()
            sendError = (error as? LocalizedError)?.errorDescription ?? "Prøv igen."
        }
    }
}

private struct Bubble: View {
    let m: ThreadMessage
    let mine: Bool
    var showName = false
    var tail = true

    private var shape: UnevenRoundedRectangle {
        let r: CGFloat = 18, t: CGFloat = tail ? 5 : 18
        return UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: mine ? r : t,
                                      bottomTrailingRadius: mine ? t : r, topTrailingRadius: r, style: .continuous)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if mine { Spacer(minLength: 56) }
            else {
                Group {
                    if tail { Avatar(url: m.image, size: 28, name: m.author) } else { Color.clear }
                }
                .frame(width: 28, height: 28)
            }
            VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                if showName {
                    Text(m.author.components(separatedBy: " ").first ?? m.author)
                        .font(.caption2).foregroundStyle(.secondary).padding(.leading, 12)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(m.text).font(.body)
                    ForEach(m.links, id: \.self) { u in
                        Link(destination: u) {
                            Label(u.host?.replacingOccurrences(of: "www.", with: "") ?? "Link", systemImage: "link")
                                .font(.subheadline.weight(.semibold)).lineLimit(1)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Capsule().fill(mine ? Color.white.opacity(0.2) : Color.accentColor.opacity(0.12)))
                        }
                        .tint(mine ? .white : .accentColor)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundStyle(mine ? .white : .primary)
                .background(shape.fill(mine ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color(.systemGray5))))
                .contentShape(.contextMenuPreview, shape)
                .contextMenu {
                    Button { UIPasteboard.general.string = m.text; Haptic.tap() } label: { Label("Kopiér", systemImage: "doc.on.doc") }
                }
            }
            if !mine { Spacer(minLength: 56) }
        }
    }
}

// MARK: - New message

struct ComposeScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var inbox = Inbox.shared
    @State private var to: [Person]
    @State private var query = ""
    @State private var subject = ""
    @State private var text = ""
    @State private var sending = false
    @State private var sendError: String?
    @FocusState private var searching: Bool

    init(to: [Person] = []) { _to = State(initialValue: to) }

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
                                        Button { Haptic.tap(); withAnimation(.viggo) { to.removeAll { $0 == p } } } label: {
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
                        Button { Haptic.select(); withAnimation(.viggo) { to.append(p) }; query = ""; searching = true } label: {
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
            Haptic.success()
            dismiss()
        } catch {
            Haptic.error()
            sendError = (error as? LocalizedError)?.errorDescription ?? "Prøv igen."
        }
    }
}
