import AppKit
import SwiftUI

// Transparent overlay added as subview of NSStatusBarButton.
// mouseDown fires reliably regardless of .app bundle / swift run context,
// exactly like WidgetInteractionView does for the floating orb.
private final class StatusBarClickView: NSView {
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        print("[BAR] overlay mouseDown (left)")
        onLeftClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        print("[BAR] overlay rightMouseDown")
        onRightClick?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isOpaque: Bool { false }
}

// ============================================================
// StatusBarController.swift
// Menu bar icon — single left-click toggles voice listening.
// ============================================================

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var clickOverlay: StatusBarClickView?
    private var widgetEverShown = false

    var onToggleVoice: (() -> Void)?
    var isVoiceActive: (() -> Bool)?
    var onToggleWidget: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    override init() {
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = makeIcon()
        statusItem.button?.toolTip = "Alakeya — нажмите, чтобы говорить"

        // NO statusItem.menu — it would intercept clicks before the overlay.
        // Add a transparent overlay on top of the button. Its mouseDown fires
        // directly, exactly like WidgetInteractionView on the floating orb.
        DispatchQueue.main.async { [weak self] in
            self?.installClickOverlay()
        }
    }

    private func installClickOverlay() {
        guard let button = statusItem.button else { return }
        let overlay = StatusBarClickView()
        overlay.frame = button.bounds
        overlay.autoresizingMask = [.width, .height]
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.clear.cgColor
        overlay.onLeftClick = { [weak self] in
            self?.onToggleVoice?()
        }
        overlay.onRightClick = { [weak self] in
            self?.showMenu()
        }
        button.addSubview(overlay)
        clickOverlay = overlay
    }

    private func showMenu() {
        let menu = buildMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // ── Menu (right-click) ────────────────────────────────

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let widgetItem = NSMenuItem(
            title: widgetEverShown ? "Показать виджет" : "Добавить виджет",
            action: #selector(handleWidgetItem),
            keyEquivalent: "")
        widgetItem.target = self
        menu.addItem(widgetItem)

        let settingsItem = NSMenuItem(
            title: "Настройки",
            action: #selector(handleSettings),
            keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem(
            title: "Выйти",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"))

        return menu
    }

    nonisolated func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor in
            menu.items.first?.title = self.widgetEverShown ? "Показать виджет" : "Добавить виджет"
        }
    }

    @objc private func handleWidgetItem() {
        widgetEverShown = true
        onToggleWidget?()
    }

    @objc private func handleSettings() { onOpenSettings?() }

    // ── Icon ──────────────────────────────────────────────

    private func makeIcon() -> NSImage {
        let size: CGFloat = 18
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let cs = CGColorSpaceCreateDeviceRGB()
            let c  = CGPoint(x: rect.midX, y: rect.midY)
            let r  = size / 2 - 1

            // Outer glow
            let glowC: [CGColor] = [
                CGColor(red: 0.024, green: 0.714, blue: 0.831, alpha: 0.4),
                CGColor(red: 0.024, green: 0.714, blue: 0.831, alpha: 0.0),
            ]
            if let g = CGGradient(colorsSpace: cs, colors: glowC as CFArray, locations: [0, 1]) {
                ctx.drawRadialGradient(g, startCenter: c, startRadius: r * 0.3,
                                       endCenter: c, endRadius: r * 1.3,
                                       options: [.drawsAfterEndLocation])
            }

            // Clip to circle
            ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.clip()

            // Sphere gradient: #C8F5FF → #06B6D4 → #1e1b4b → #050216
            let stops: [CGColor] = [
                CGColor(red: 0.784, green: 0.961, blue: 1.000, alpha: 1),
                CGColor(red: 0.024, green: 0.714, blue: 0.831, alpha: 1),
                CGColor(red: 0.118, green: 0.106, blue: 0.294, alpha: 1),
                CGColor(red: 0.020, green: 0.008, blue: 0.086, alpha: 1),
            ]
            let locs: [CGFloat] = [0, 0.35, 0.75, 1]
            if let g = CGGradient(colorsSpace: cs, colors: stops as CFArray, locations: locs) {
                let hl = CGPoint(x: c.x - r * 0.18, y: c.y + r * 0.20)
                ctx.drawRadialGradient(g, startCenter: hl, startRadius: 0,
                                       endCenter: c, endRadius: r,
                                       options: [.drawsAfterEndLocation])
            }
            return true
        }
        img.isTemplate = false
        return img
    }
}
