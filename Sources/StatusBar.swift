import AppKit
import Combine
import SwiftUI

/// Viggo+'s own menu bar item and panel. SwiftUI's MenuBarExtra can't be opened from code
/// (its button has no action, so the ⌥V hotkey did nothing); this one can.
@MainActor
final class PanelController: NSObject {
    static let shared = PanelController()

    private var item: NSStatusItem?
    private var panel: KeyPanel?
    private var host: PanelHost?
    private var monitors: [Any] = []
    private var bag: Set<AnyCancellable> = []
    /// Where the panel's top edge sits, so it grows downward when its content changes.
    private var top: CGFloat = 0

    var isShown: Bool { panel?.isVisible == true }
    var frame: NSRect? { isShown ? panel?.frame : nil }

    func setup() {
        guard item == nil else { return }
        let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        it.button?.target = self
        it.button?.action = #selector(clicked)
        it.button?.imagePosition = .imageLeading
        item = it
        updateLabel()
        // The menu bar text follows the app state (time, lesson names, badge).
        AppState.shared.objectWillChange.merge(with: Prefs.shared.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateLabel() } }
            .store(in: &bag)
    }

    private func updateLabel() {
        guard let b = item?.button else { return }
        let s = AppState.shared
        let img = NSImage(systemSymbolName: s.badgeCount > 0 ? "graduationcap.circle.fill" : "graduationcap.fill",
                          accessibilityDescription: "Viggo+")
        img?.isTemplate = true
        b.image = img
        let badge = s.badgeCount > 0 ? "  ✉︎ \(s.badgeCount)" : ""
        let text = s.menuTitle + badge
        let title = text.isEmpty ? "" : " " + text
        if b.title != title { b.title = title }
    }

    @objc private func clicked() { toggle() }

    func toggle() { isShown ? close() : show() }

    func show() {
        guard let button = item?.button, let bw = button.window else { return }
        let p = panel ?? makePanel()
        panel = p
        let anchor = bw.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = (NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main)?.visibleFrame ?? .zero
        top = screen.maxY - 4
        let size = host?.fittingSize ?? NSSize(width: 320, height: 600)
        let x = min(max(screen.minX + 8, anchor.minX), screen.maxX - 8 - size.width)
        p.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
        NSApp.activate(ignoringOtherApps: true)
        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; p.animator().alphaValue = 1 }
        button.highlight(true)
        watch()
    }

    func close() {
        guard let p = panel, p.isVisible else { return }
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        item?.button?.highlight(false)
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.1; p.animator().alphaValue = 0 }) {
            MainActor.assumeIsolated { p.orderOut(nil); p.alphaValue = 1 }
        }
    }

    private func makePanel() -> KeyPanel {
        let root = MenuView().environmentObject(AppState.shared)
            .background(VisualEffect())
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        let h = PanelHost(rootView: AnyView(root))
        h.onResize = { [weak self] in self?.fit() }
        host = h
        let p = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 600),
                         styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        p.contentView = h
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        return p
    }

    /// Resizes the panel to its content, keeping the top edge where it is (a note folding out grows it downward).
    private func fit() {
        guard let p = panel, p.isVisible, let h = host else { return }
        let size = h.fittingSize
        guard abs(size.height - p.frame.height) > 0.5 || abs(size.width - p.frame.width) > 0.5 else { return }
        p.setFrame(NSRect(x: p.frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
        p.invalidateShadow()
    }

    /// Closes on a click outside, on Escape, and when you switch to another app.
    private func watch() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { _ in
            Task { @MainActor in PanelController.shared.close() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { e in
            if e.keyCode == 53, PanelController.shared.panel?.isKeyWindow == true { PanelController.shared.close(); return nil }
            return e
        }) { monitors.append(m) }
    }
}

/// Tells the controller when the SwiftUI content changes size.
final class PanelHost: NSHostingView<AnyView> {
    var onResize: (() -> Void)?
    private var pending = false
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        guard !pending else { return }
        pending = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.pending = false; self?.onResize?() }
        }
    }
}

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func resignKey() {
        super.resignKey()
        // Clicking one of Viggo+'s own windows (or the app losing focus) closes the panel, like a menu.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if NSApp.keyWindow !== self { PanelController.shared.close() }
            }
        }
    }
}

/// The frosted background the system uses for menus and popovers.
struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { PanelController.shared.setup() }
    }
}
