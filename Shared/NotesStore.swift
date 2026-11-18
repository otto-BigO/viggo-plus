import Foundation
import SwiftUI
#if os(iOS)
import UIKit
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformImage = NSImage
#endif

/// Your own notes and pictures of the board for a lesson. They stay on the phone (nothing goes to
/// Viggo), and the next lesson in the same subject shows what you wrote last time.
struct LessonNote: Codable, Hashable {
    var text = ""
    /// File names in the notes folder.
    var photos: [String] = []
    var date: Date
    var subject: String
    var title: String
    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && photos.isEmpty }
}

@MainActor
final class LessonNotes: ObservableObject {
    static let shared = LessonNotes()

    /// By lesson key ("lesson-123").
    @Published private(set) var notes: [String: LessonNote] = [:]

    private var dir: URL { CookieJar.dir.appendingPathComponent("notes", isDirectory: true) }
    private var indexURL: URL { dir.appendingPathComponent("notes.json") }
    private let cache = NSCache<NSString, PlatformImage>()

    init() {
        if let data = try? Data(contentsOf: indexURL), let n = try? JSONDecoder().decode([String: LessonNote].self, from: data) { notes = n }
    }

    private var saveTask: Task<Void, Never>?
    /// A moment later, so typing writes the file once in a while instead of on every letter.
    private func save() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(notes.filter { !$0.value.isEmpty }) { try? data.write(to: indexURL, options: .atomic) }
        }
    }

    static func subject(of e: ViggoEvent) -> String { e.shortTitle }

    func note(for e: ViggoEvent) -> LessonNote? { notes[e.key].flatMap { $0.isEmpty ? nil : $0 } }
    func hasNote(_ e: ViggoEvent) -> Bool { note(for: e) != nil }

    private func edit(_ e: ViggoEvent, _ change: (inout LessonNote) -> Void) {
        var n = notes[e.key] ?? LessonNote(date: e.start, subject: Self.subject(of: e), title: e.title)
        change(&n)
        notes[e.key] = n
        save()
    }

    func setText(_ text: String, for e: ViggoEvent) {
        guard text != (notes[e.key]?.text ?? "") else { return }
        edit(e) { $0.text = text }
    }

    /// Saved at most 2000 px wide as JPEG, which keeps a board photo around 400 KB.
    func add(_ image: PlatformImage, for e: ViggoEvent) {
        let name = UUID().uuidString + ".jpg"
        guard let (scaled, data) = Self.jpeg(image, max: 2000) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard (try? data.write(to: dir.appendingPathComponent(name), options: .atomic)) != nil else { return }
        cache.setObject(scaled, forKey: name as NSString)
        edit(e) { $0.photos.append(name) }
    }

    func remove(photo name: String, from e: ViggoEvent) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        cache.removeObject(forKey: name as NSString)
        edit(e) { $0.photos.removeAll { $0 == name } }
    }

    /// Where a photo is on disk, for opening it in Preview on the Mac.
    func url(of name: String) -> URL { dir.appendingPathComponent(name) }

    func image(_ name: String) -> PlatformImage? {
        if let i = cache.object(forKey: name as NSString) { return i }
        guard let i = PlatformImage(contentsOfFile: dir.appendingPathComponent(name).path) else { return nil }
        cache.setObject(i, forKey: name as NSString)
        return i
    }

    /// The newest earlier lesson in the same subject that has a note.
    func previous(before e: ViggoEvent) -> LessonNote? {
        let subject = Self.subject(of: e)
        return notes.filter { $0.key != e.key && $0.value.subject == subject && $0.value.date < e.start && !$0.value.isEmpty }
            .map(\.value).max { $0.date < $1.date }
    }

    func clear() {
        notes = [:]
        cache.removeAllObjects()
        try? FileManager.default.removeItem(at: dir)
    }

    /// The picture at most `side` pixels on its longest edge, and as JPEG.
    private static func jpeg(_ image: PlatformImage, max side: CGFloat) -> (PlatformImage, Data)? {
        #if os(iOS)
        let s = image.size
        let f = min(1, side / Swift.max(s.width, s.height))
        var out = image
        if f < 1 {
            let size = CGSize(width: (s.width * f).rounded(), height: (s.height * f).rounded())
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            out = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        }
        return out.jpegData(compressionQuality: 0.75).map { (out, $0) }
        #else
        // NSImage.size is in points; the pixels are in the bitmap behind it.
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let f = min(1, side / Swift.max(w, h))
        let pw = Int((w * f).rounded()), ph = Int((h * f).rounded())
        guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: pw, height: ph))
        guard let small = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: small)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.75]) else { return nil }
        return (NSImage(cgImage: small, size: NSSize(width: pw, height: ph)), data)
        #endif
    }
}

