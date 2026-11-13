import SwiftUI

/// A post from the bulletin board, read in the app: the whole text, its pictures and links.
struct BulletinScreen: View {
    let b: Bulletin
    @State private var zoomed: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Avatar(url: b.authorImage, size: 44, name: b.author)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.author).font(.subheadline.weight(.semibold))
                        Text("\(b.when) · \(b.board.trimmingCharacters(in: CharacterSet(charactersIn: "[]")))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(b.title).font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                DeadlineSuggestion(source: "opslag:\(b.id)")
                if !b.body.isEmpty {
                    Text(b.body).font(.body).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(b.images, id: \.self) { u in
                    Button { Haptic.tap(); zoomed = u } label: {
                        ViggoImage(url: u)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(PressScale(scale: 0.97))
                }
                ForEach(b.links, id: \.self) { u in
                    Link(destination: u) {
                        HStack(spacing: 10) {
                            Image(systemName: "link").font(.body.weight(.semibold))
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(Color.accentColor.opacity(0.14)))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(u.host?.replacingOccurrences(of: "www.", with: "") ?? "Link").font(.subheadline.weight(.semibold))
                                Text(u.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                    }
                    .buttonStyle(PressScale(scale: 0.97))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background {
            LinearGradient(colors: [(b.color ?? .accentColor).opacity(0.25), Color(.systemGroupedBackground)],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        }
        .navigationTitle("Opslag")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $zoomed) { u in ZoomImage(url: u) }
    }
}

extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

/// A picture full screen, pinch to zoom, double tap to zoom in and out.
struct ZoomImage: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    @State private var scale: CGFloat = 1
    @State private var last: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            ViggoImage(url: url, zoom: true) { img in
                img.resizable().scaledToFit()
                    .scaleEffect(scale)
                    .gesture(MagnifyGesture()
                        .onChanged { scale = max(1, last * $0.magnification) }
                        .onEnded { _ in last = scale; if scale < 1.05 { withAnimation(.viggo) { scale = 1; last = 1 } } })
                    .onTapGesture(count: 2) {
                        Haptic.tap()
                        withAnimation(.viggo) { scale = scale > 1 ? 1 : 2.5; last = scale }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.body.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(Circle().fill(.white.opacity(0.2)))
            }
            .padding()
        }
        .gesture(DragGesture().onEnded { if $0.translation.height > 120, scale == 1 { dismiss() } })
    }
}

/// Loads a picture with your Viggo login, since post attachments are not public.
struct ViggoImage<Shown: View>: View {
    let url: URL
    var zoom = false
    var shown: (Image) -> Shown
    @State private var image: UIImage?
    @State private var failed = false

    init(url: URL, zoom: Bool = false, @ViewBuilder shown: @escaping (Image) -> Shown) {
        self.url = url; self.zoom = zoom; self.shown = shown
    }

    var body: some View {
        Group {
            if let image { shown(Image(uiImage: image)).transition(.opacity) }
            else if failed {
                Label("Billedet kunne ikke hentes", systemImage: "photo").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if zoom {
                ProgressView().tint(.white)
            } else {
                RoundedRectangle(cornerRadius: 14).fill(Color(.tertiarySystemFill))
                    .frame(height: 200).overlay(ProgressView())
            }
        }
        .task(id: url) {
            if let hit = ImageCache.shared.object(forKey: url as NSURL) { image = hit; return }
            if let d = try? await AppState.shared.client.data(url), let img = UIImage(data: d) {
                ImageCache.shared.setObject(img, forKey: url as NSURL)
                withAnimation(.viggo) { image = img }
            } else { failed = true }
        }
    }
}

extension ViggoImage where Shown == AnyView {
    init(url: URL) { self.init(url: url) { AnyView($0.resizable().scaledToFit()) } }
}

/// Pictures stay in memory while the app runs, so reopening a thread or post does not fetch them again.
enum ImageCache {
    nonisolated(unsafe) static let shared: NSCache<NSURL, UIImage> = { let c = NSCache<NSURL, UIImage>(); c.countLimit = 60; return c }()
}
