import SwiftUI
import UIKit

/// The app icon styles. Each one is drawn by `IconArt`, which also renders the PNGs in
/// Assets.xcassets (`VIGGO_RENDER_ICONS=<dir>` in the simulator), so the picker and the
/// launch screen always match the real icon.
struct IconStyle: Identifiable, Equatable {
    let id: String          // asset name; "AppIcon" is the default icon
    let name: String
    let top: Color
    let bottom: Color
    let glyph: [Color]      // V colour, top to bottom
    let badge: [Color]      // "+" circle
    let plus: Color

    var alternateName: String? { id == "AppIcon" ? nil : id }

    static func hex(_ v: UInt32) -> Color {
        Color(red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    static let all: [IconStyle] = [
        IconStyle(id: "AppIcon", name: "Viggo", top: hex(0x306ABD), bottom: hex(0x1F4E96),
                  glyph: [.white], badge: [.white], plus: hex(0x285FB0)),
        IconStyle(id: "AppIcon-Midnat", name: "Midnat", top: hex(0x23233A), bottom: hex(0x07070D),
                  glyph: [.white, hex(0xC9D6FF)], badge: [hex(0x4F8BFF), hex(0x2A5BDB)], plus: .white),
        IconStyle(id: "AppIcon-Solnedgang", name: "Solnedgang", top: hex(0xFFB347), bottom: hex(0xFF3D7F),
                  glyph: [.white], badge: [.white], plus: hex(0xFF5A6E)),
        IconStyle(id: "AppIcon-Mint", name: "Mint", top: hex(0x4BE3B8), bottom: hex(0x0B8F7A),
                  glyph: [.white], badge: [.white], plus: hex(0x10A38A)),
        IconStyle(id: "AppIcon-Lilla", name: "Lilla", top: hex(0xB07BFF), bottom: hex(0x4B22C9),
                  glyph: [.white], badge: [.white], plus: hex(0x6A3BE6)),
        IconStyle(id: "AppIcon-Lys", name: "Lys", top: .white, bottom: hex(0xE6ECF6),
                  glyph: [hex(0x3A78D6), hex(0x1F4E96)], badge: [hex(0x3A78D6), hex(0x1F4E96)], plus: .white),
        IconStyle(id: "AppIcon-Neon", name: "Neon", top: hex(0x14141C), bottom: .black,
                  glyph: [hex(0x3CF0FF), hex(0xFF3CC8)], badge: [hex(0xFF3CC8), hex(0x9B3CFF)], plus: .white),
        IconStyle(id: "AppIcon-Guld", name: "Guld", top: hex(0x2B2216), bottom: hex(0x0F0B06),
                  glyph: [hex(0xFFE29A), hex(0xC8902E)], badge: [hex(0xFFE29A), hex(0xC8902E)], plus: hex(0x2B2216)),
    ]

    static var current: IconStyle {
        let n = UIApplication.shared.alternateIconName
        return all.first { $0.alternateName == n } ?? all[0]
    }
}

/// The "V" as a thick rounded stroke, so the launch screen can draw it in.
struct VShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.16, y: r.minY + r.height * 0.12))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY - r.height * 0.1))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.16, y: r.minY + r.height * 0.12))
        return p
    }
}

/// One icon. `progress` draws the V in (0 to 1) and `badge` pops the "+" in, for the launch screen.
struct IconArt: View {
    let style: IconStyle
    var size: CGFloat
    var masked = true
    var progress: CGFloat = 1
    var badge: CGFloat = 1

    var body: some View {
        let s = size
        ZStack {
            LinearGradient(colors: [style.top, style.bottom], startPoint: .top, endPoint: .bottom)
            // Soft light from the top left.
            RadialGradient(colors: [.white.opacity(0.22), .clear], center: UnitPoint(x: 0.2, y: 0.05),
                           startRadius: 0, endRadius: s * 0.75)
            VShape()
                .trim(from: 0, to: progress)
                .stroke(LinearGradient(colors: style.glyph.count > 1 ? style.glyph : style.glyph + style.glyph,
                                       startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: s * 0.13, lineCap: .round, lineJoin: .round))
                .frame(width: s * 0.46, height: s * 0.42)
                .shadow(color: .black.opacity(0.18), radius: s * 0.02, y: s * 0.012)
                .offset(x: -s * 0.05, y: s * 0.07)
            ZStack {
                Circle().fill(LinearGradient(colors: style.badge.count > 1 ? style.badge : style.badge + style.badge,
                                             startPoint: .top, endPoint: .bottom))
                Image(systemName: "plus")
                    .font(.system(size: s * 0.15, weight: .black))
                    .foregroundStyle(style.plus)
            }
            .frame(width: s * 0.25, height: s * 0.25)
            .shadow(color: .black.opacity(0.2), radius: s * 0.02, y: s * 0.01)
            .scaleEffect(badge)
            .opacity(badge > 0.01 ? 1 : 0)
            .offset(x: s * 0.27, y: -s * 0.26)
        }
        .frame(width: s, height: s)
        .clipShape(RoundedRectangle(cornerRadius: masked ? s * 0.225 : 0, style: .continuous))
    }
}

/// Settings > App-ikon: tap an icon to switch.
struct IconPicker: View {
    @State private var current = IconStyle.current
    @State private var error: String?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 18)], spacing: 22) {
                ForEach(IconStyle.all) { s in
                    Button { pick(s) } label: {
                        VStack(spacing: 8) {
                            IconArt(style: s, size: 76)
                                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 76 * 0.225 + 5, style: .continuous)
                                        .stroke(Color.accentColor, lineWidth: 3)
                                        .padding(-5)
                                        .opacity(current == s ? 1 : 0)
                                }
                                .scaleEffect(current == s ? 1.04 : 1)
                            Text(s.name).font(.footnote.weight(current == s ? .semibold : .regular))
                                .foregroundStyle(current == s ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(PressScale())
                }
            }
            .padding(20)
            if let error { Text(error).font(.footnote).foregroundStyle(.secondary).padding() }
        }
        .animation(.viggo, value: current)
    }

    private func pick(_ s: IconStyle) {
        guard s != current else { return }
        Haptic.select()
        withAnimation(.viggo) { current = s }
        UIApplication.shared.setAlternateIconName(s.alternateName) { err in
            Task { @MainActor in
                if let err { error = err.localizedDescription; current = IconStyle.current; Haptic.error() }
                else { Haptic.success() }
            }
        }
    }
}

/// Test hook: writes every icon as a 1024 px PNG, full bleed (iOS rounds the corners itself).
@MainActor enum IconRenderer {
    static func run(to dir: String) {
        for s in IconStyle.all {
            let r = ImageRenderer(content: IconArt(style: s, size: 1024, masked: false))
            r.scale = 1
            r.isOpaque = true
            guard let img = r.uiImage, let png = img.pngData() else { continue }
            try? png.write(to: URL(fileURLWithPath: "\(dir)/\(s.id).png"))
        }
        print("ICONS DONE")
    }
}
