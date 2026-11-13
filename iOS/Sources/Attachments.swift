import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The paperclip in Beskeder: pick pictures from Photos or any file from Files. Adds them to `files`.
struct AttachButton: View {
    @Binding var files: [Attachment]
    @Binding var error: String?
    @State private var photos = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var importing = false

    var body: some View {
        Menu {
            Button { photos = true } label: { Label("Billeder", systemImage: "photo.on.rectangle") }
            Button { importing = true } label: { Label("Filer", systemImage: "folder") }
        } label: {
            Image(systemName: "paperclip")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color(.tertiarySystemFill)))
        }
        .accessibilityLabel("Vedhæft")
        .photosPicker(isPresented: $photos, selection: $picked, maxSelectionCount: 10, matching: .any(of: [.images, .videos]))
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            Task { await addPhotos(items) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { r in
            guard case .success(let urls) = r else { return }
            for u in urls { addFile(u) }
        }
    }

    private func add(_ a: Attachment) {
        guard a.data.count <= ViggoClient.maxFileSize else {
            error = "\(a.name) fylder \(a.size). Viggo tager højst 10 MB pr. fil."
            Haptic.error()
            return
        }
        Haptic.tap()
        withAnimation(.viggo) { files.append(a) }
    }

    private func addPhotos(_ items: [PhotosPickerItem]) async {
        for (i, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let type = item.supportedContentTypes.first
            let n = files.count + 1
            if type?.conforms(to: .movie) == true {
                let ext = type?.preferredFilenameExtension ?? "mov"
                add(Attachment(name: "Video \(n).\(ext)", mime: type?.preferredMIMEType ?? "video/quicktime", data: data))
            } else if let img = UIImage(data: data), let jpg = Self.jpeg(img) {
                // HEIC does not open everywhere, so pictures go as JPEG, scaled to at most 2560 px.
                add(Attachment(name: "Billede \(n).jpg", mime: "image/jpeg", data: jpg))
            } else {
                add(Attachment(name: "Fil \(n + i)", mime: type?.preferredMIMEType ?? "application/octet-stream", data: data))
            }
        }
    }

    static func jpeg(_ img: UIImage) -> Data? {
        let maxSide: CGFloat = 2560
        let side = max(img.size.width, img.size.height)
        var image = img
        if side > maxSide {
            let s = maxSide / side
            let size = CGSize(width: img.size.width * s, height: img.size.height * s)
            let format = UIGraphicsImageRendererFormat(); format.scale = 1 // not the screen's 3x
            image = UIGraphicsImageRenderer(size: size, format: format).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        }
        // Aim for a few MB: quick to upload on mobile data and far from Viggo's 10 MB limit.
        let target = 4 * 1024 * 1024
        var q: CGFloat = 0.8
        var data = image.jpegData(compressionQuality: q)
        while let d = data, d.count > target, q > 0.3 { q -= 0.15; data = image.jpegData(compressionQuality: q) }
        return data
    }

    private func addFile(_ u: URL) {
        let access = u.startAccessingSecurityScopedResource()
        defer { if access { u.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: u) else { error = "Kunne ikke læse \(u.lastPathComponent)."; return }
        let mime = UTType(filenameExtension: u.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        add(Attachment(name: u.lastPathComponent, mime: mime, data: data))
    }
}

/// The picked files above the text field, each with a button to take it off again.
struct AttachmentChips: View {
    @Binding var files: [Attachment]

    var body: some View {
        if !files.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(files) { f in
                        HStack(spacing: 8) {
                            if f.isImage, let img = UIImage(data: f.data) {
                                Image(uiImage: img).resizable().scaledToFill()
                                    .frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            } else {
                                Image(systemName: Self.icon(f)).font(.system(size: 16, weight: .semibold)).foregroundStyle(.tint)
                                    .frame(width: 34, height: 34)
                                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor.opacity(0.14)))
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                Text(f.name).font(.caption.weight(.medium)).lineLimit(1)
                                Text(f.size).font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: 130, alignment: .leading)
                            Button {
                                Haptic.tap()
                                withAnimation(.viggo) { files.removeAll { $0.id == f.id } }
                            } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 17)).foregroundStyle(.secondary)
                            }
                            .accessibilityLabel("Fjern \(f.name)")
                        }
                        .padding(6).padding(.trailing, 2)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemBackground)))
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 10)
            }
        }
    }

    static func icon(_ f: Attachment) -> String {
        if f.mime.hasPrefix("video/") { return "film" }
        if f.mime == "application/pdf" { return "doc.richtext" }
        if f.mime.hasPrefix("audio/") { return "waveform" }
        return "doc"
    }
}
