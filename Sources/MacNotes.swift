import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Pakkeliste in the panel

/// What to bring, in the panel: tick things off as you pack, add your own, and right-click one
/// to repeat it every time there is that subject or to remove it. Same list as on the iPhone,
/// but kept on the Mac (the two do not share ticks).
struct MacPackSection: View {
    @ObservedObject private var store = PackStore.shared
    let day: Date
    let title: String
    @State private var adding = ""
    @FocusState private var typing: Bool

    var body: some View {
        let items = store.items(on: day)
        let left = items.filter { !store.isTicked($0, on: day) }.count
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                SectionHeader(title: title)
                Spacer()
                if !items.isEmpty {
                    Text(left == 0 ? "Alt er pakket" : "\(left) tilbage")
                        .font(Sz.f(10, .medium)).foregroundStyle(left == 0 ? .green : .secondary)
                        .padding(.top, 4)
                        .contentTransition(.numericText())
                }
            }
            ForEach(items) { row($0) }
            HStack(spacing: 8) {
                Image(systemName: "plus.circle").font(Sz.f(14)).foregroundStyle(.secondary)
                TextField("Tilføj noget at pakke", text: $adding)
                    .textFieldStyle(.plain)
                    .font(Sz.f(12))
                    .focused($typing)
                    .onSubmit {
                        withAnimation(.viggo) { store.add(adding, on: day) }
                        adding = ""
                    }
            }
        }
        .animation(.viggo, value: left)
    }

    private func row(_ i: PackItem) -> some View {
        let done = store.isTicked(i, on: day)
        return HStack(alignment: .top, spacing: 8) {
            Button { withAnimation(.viggo) { store.toggle(i, on: day) } } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(Sz.f(14))
                    .foregroundStyle(done ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressScale(scale: 0.8))
            VStack(alignment: .leading, spacing: 1) {
                Text(i.text).font(Sz.f(13)).strikethrough(done).foregroundStyle(done ? .secondary : .primary).lineLimit(2)
                Text(i.from).font(Sz.f(10.5)).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .help(i.sentence)
        .contextMenu {
            if !i.sentence.isEmpty { Text(i.sentence) }
            if let c = i.custom {
                if c.subject == nil {
                    ForEach(store.subjects(on: day), id: \.self) { s in
                        Button("Hver gang der er \(s)") { store.repeatEvery(c, subject: s, day: day) }
                    }
                } else {
                    Button("Kun denne dag") { store.repeatEvery(c, subject: nil, day: day) }
                }
            }
            Button(done ? "Ikke pakket" : "Pakket") { withAnimation(.viggo) { store.toggle(i, on: day) } }
            Divider()
            Button("Fjern", role: .destructive) { withAnimation(.viggo) { store.remove(i) } }
        }
    }

    /// Which day the panel packs for: today in the morning, tomorrow from noon. Nil when there is nothing.
    @MainActor static func day(now: Date) -> (Date, String)? {
        let store = PackStore.shared
        let hour = DateUtil.cal.component(.hour, from: now)
        let today = DateUtil.startOfDay(now)
        let tomorrow = DateUtil.add(.day, 1, today)
        if hour < 12 { return store.items(on: today).isEmpty ? nil : (today, "Pak til i dag") }
        if !store.items(on: tomorrow).isEmpty || hour >= 15 && !store.subjects(on: tomorrow).isEmpty { return (tomorrow, "Pak til i morgen") }
        return nil
    }
}

// MARK: - notes and board photos in the lesson window

/// Your own notes and pictures for a lesson, in the lesson window. Drop pictures on it, pick them
/// from the Mac, or take one with the iPhone's camera. Kept on the Mac; nothing goes to Viggo.
struct MacLessonNotes: View {
    @ObservedObject private var store = LessonNotes.shared
    let e: ViggoEvent
    @State private var text = ""
    @State private var loaded = false
    @State private var dropping = false

    private static let dayF: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "da_DK"); f.dateFormat = "EEEE d. MMMM"; return f
    }()

    var body: some View {
        let note = store.note(for: e)
        VStack(alignment: .leading, spacing: 10) {
            Text("Dine noter").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 64, maxHeight: 220)
                .fixedSize(horizontal: false, vertical: true)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Skriv noter til timen").font(.system(size: 13)).foregroundStyle(.tertiary)
                            .padding(.horizontal, 11).padding(.vertical, 6).allowsHitTesting(false)
                    }
                }
                .onChange(of: text) { if loaded { store.setText(text, for: e) } }

            if let photos = note?.photos, !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos, id: \.self) { name in
                            thumb(name, size: 84)
                                .contextMenu {
                                    Button("Åbn") { NSWorkspace.shared.open(store.url(of: name)) }
                                    Button("Vis i Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.url(of: name)]) }
                                    Divider()
                                    Button("Slet billede", role: .destructive) { withAnimation(.viggo) { store.remove(photo: name, from: e) } }
                                }
                        }
                    }
                }
                .frame(height: 84)
            }

            HStack(spacing: 8) {
                IPhoneCameraButton { img in withAnimation(.viggo) { store.add(img, for: e) } }
                    .fixedSize()
                Button { pickFiles() } label: { Label("Tilføj billeder…", systemImage: "photo.on.rectangle") }
                    .controlSize(.small)
                Spacer()
            }
            .font(.system(size: 12))
            Text("Du kan også trække billeder herind.").font(.system(size: 10.5)).foregroundStyle(.tertiary)

            if let last = store.previous(before: e) { lastTime(last) }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .opacity(dropping ? 1 : 0)
        }
        .padding(-8)
        .onDrop(of: [.image, .fileURL], isTargeted: $dropping) { providers in
            var any = false
            for p in providers where p.canLoadObject(ofClass: NSImage.self) {
                any = true
                _ = p.loadObject(ofClass: NSImage.self) { obj, _ in
                    guard let img = obj as? NSImage else { return }
                    DispatchQueue.main.async { MainActor.assumeIsolated { withAnimation(.viggo) { LessonNotes.shared.add(img, for: e) } } }
                }
            }
            return any
        }
        .onAppear {
            text = store.notes[e.key]?.text ?? ""
            // The first change after loading is the loaded text itself, not something you typed.
            DispatchQueue.main.async { loaded = true }
        }
    }

    private func pickFiles() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.allowsMultipleSelection = true
        p.message = "Vælg billeder til \(e.shortTitle)"
        p.prompt = "Tilføj"
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK else { return }
        for u in p.urls { if let img = NSImage(contentsOf: u) { withAnimation(.viggo) { store.add(img, for: e) } } }
    }

    private func thumb(_ name: String, size: CGFloat) -> some View {
        Group {
            if let img = store.image(name) {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                Color.secondary.opacity(0.15)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { NSWorkspace.shared.open(store.url(of: name)) }
        .help("Åbn billedet")
    }

    /// What you wrote in the last lesson of the same subject.
    private func lastTime(_ n: LessonNote) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Sidste gang i \(n.subject), \(Self.dayF.string(from: n.date))", systemImage: "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            if !n.text.isEmpty {
                Text(n.text).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(6).textSelection(.enabled)
            }
            if !n.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) { ForEach(n.photos, id: \.self) { thumb($0, size: 56) } }
                }
                .frame(height: 56)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    }
}

// MARK: - Continuity Camera

/// "Tavlebillede": takes a photo with the iPhone's camera, the way Notes and Pages do on the Mac
/// (Continuity Camera). macOS fills in the menu with the iPhones nearby.
struct IPhoneCameraButton: NSViewRepresentable {
    let onImage: (NSImage) -> Void

    func makeNSView(context: Context) -> CameraButtonView {
        let v = CameraButtonView()
        v.onImage = onImage
        return v
    }
    func updateNSView(_ v: CameraButtonView, context: Context) { v.onImage = onImage }

    final class CameraButtonView: NSView, NSServicesMenuRequestor {
        var onImage: (NSImage) -> Void = { _ in }
        private let button = NSButton(title: "Tavlebillede", image: NSImage(systemSymbolName: "camera.fill", accessibilityDescription: nil)!,
                                      target: nil, action: nil)

        override init(frame: NSRect) {
            super.init(frame: frame)
            button.controlSize = .small
            button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            button.bezelStyle = .rounded
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(showMenu)
            button.toolTip = "Tag et billede af tavlen med din iPhone"
            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: leadingAnchor), button.trailingAnchor.constraint(equalTo: trailingAnchor),
                button.topAnchor.constraint(equalTo: topAnchor), button.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        required init?(coder: NSCoder) { fatalError() }

        override var intrinsicContentSize: NSSize { button.intrinsicContentSize }
        override var acceptsFirstResponder: Bool { true }

        @objc private func showMenu() {
            window?.makeFirstResponder(self)
            let menu = NSMenu()
            // macOS replaces this item with "Tag billede" / "Scan dokumenter" for each iPhone it finds.
            let item = NSMenuItem(title: "Importér fra iPhone", action: nil, keyEquivalent: "")
            item.identifier = NSMenuItem.importFromDeviceIdentifier
            menu.addItem(item)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 4), in: self)
        }

        // The photo comes back through the pasteboard, like a service.
        override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
            if let r = returnType, NSImage.imageTypes.contains(r.rawValue) { return self }
            return super.validRequestor(forSendType: sendType, returnType: returnType)
        }
        func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool { false }
        func readSelection(from pboard: NSPasteboard) -> Bool {
            guard let img = NSImage(pasteboard: pboard) else { return false }
            onImage(img)
            return true
        }
    }
}
