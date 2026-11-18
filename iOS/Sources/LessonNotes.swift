import SwiftUI
import PhotosUI
import UIKit

// MARK: - in the lesson sheet

struct LessonNotesSection: View {
    @ObservedObject private var store = LessonNotes.shared
    let e: ViggoEvent
    /// Tells the sheet to grow while you type, so the keyboard does not cover the field.
    var onEditing: (Bool) -> Void = { _ in }

    @State private var text = ""
    @State private var loaded = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var camera = false
    @State private var shown: UIImage?
    @FocusState private var typing: Bool

    private static let dayF: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "da_DK"); f.dateFormat = "EEEE d. MMMM"; return f
    }()

    var body: some View {
        let note = store.note(for: e)
        VStack(alignment: .leading, spacing: 10) {
            Text("Dine noter").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            TextField("Skriv noter til timen", text: $text, axis: .vertical)
                .font(.system(size: 14))
                .lineLimit(2...12)
                .focused($typing)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
                .onChange(of: text) { if loaded { store.setText(text, for: e) } }
                .onChange(of: typing) { onEditing(typing) }

            if let photos = note?.photos, !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos, id: \.self) { name in
                            thumb(name, size: 84)
                                .contextMenu {
                                    Button("Slet billede", systemImage: "trash", role: .destructive) {
                                        withAnimation(.viggo) { store.remove(photo: name, from: e) }
                                    }
                                }
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { typing = false; camera = true } label: { Label("Tavlebillede", systemImage: "camera.fill") }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                PhotosPicker(selection: $picked, maxSelectionCount: 10, matching: .images) {
                    Label("Fra billeder", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered).controlSize(.small)
                .simultaneousGesture(TapGesture().onEnded { typing = false })
                Spacer()
            }
            .font(.system(size: 12, weight: .medium))

            if let last = store.previous(before: e) { lastTime(last) }
        }
        .onAppear {
            text = store.notes[e.key]?.text ?? ""
            // The first change after loading is the loaded text itself, not something you typed.
            DispatchQueue.main.async { loaded = true }
        }
        .onChange(of: picked) {
            let items = picked
            picked = []
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        withAnimation(.viggo) { store.add(img, for: e) }
                    }
                }
                Haptic.soft()
            }
        }
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { img in
                withAnimation(.viggo) { store.add(img, for: e) }
                Haptic.soft()
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: Binding(get: { shown.map(ShownPhoto.init) }, set: { shown = $0?.image })) { p in
            LocalPhotoViewer(image: p.image)
        }
    }

    private func thumb(_ name: String, size: CGFloat) -> some View {
        Group {
            if let img = store.image(name) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Color.secondary.opacity(0.15)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { if let img = store.image(name) { shown = img } }
    }

    /// What you wrote in the last lesson of the same subject.
    private func lastTime(_ n: LessonNote) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Sidste gang i \(n.subject), \(Self.dayF.string(from: n.date))", systemImage: "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            if !n.text.isEmpty {
                Text(n.text).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(6).textSelection(.enabled)
            }
            if !n.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) { ForEach(n.photos, id: \.self) { thumb($0, size: 56) } }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    }
}

private struct ShownPhoto: Identifiable {
    let image: UIImage
    var id: ObjectIdentifier { ObjectIdentifier(image) }
}

/// A board photo in full screen: pinch or double-tap to zoom, drag down to close.
struct LocalPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    @State private var scale: CGFloat = 1
    @State private var last: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image).resizable().scaledToFit()
                .scaleEffect(scale)
                .gesture(MagnifyGesture()
                    .onChanged { scale = max(1, last * $0.magnification) }
                    .onEnded { _ in last = scale; if scale < 1.05 { withAnimation(.viggo) { scale = 1; last = 1 } } })
                .onTapGesture(count: 2) {
                    Haptic.tap()
                    withAnimation(.viggo) { scale = scale > 1 ? 1 : 2.5; last = scale }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 10) {
                ShareLink(item: Image(uiImage: image), preview: SharePreview("Tavlebillede", image: Image(uiImage: image))) {
                    Image(systemName: "square.and.arrow.up").font(.body.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(Circle().fill(.white.opacity(0.2)))
                }
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.body.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(Circle().fill(.white.opacity(0.2)))
                }
            }
            .padding()
        }
        .gesture(DragGesture().onEnded { if $0.translation.height > 120, scale == 1 { dismiss() } })
    }
}

/// The camera, for a picture of the board.
struct CameraPicker: UIViewControllerRepresentable {
    let done: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.delegate = context.coordinator
        return c
    }
    func updateUIViewController(_ c: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.done(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
