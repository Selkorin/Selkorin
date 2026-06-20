import AppKit
import SwiftUI

// ============================================================
// StatusBarController.swift
// Menu bar icon with a minimal dropdown.
// ============================================================

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var widgetEverShown = false

    /// Toggles voice listening (start/stop). First item of the menu.
    var onToggleVoice: (() -> Void)?
    /// Returns whether voice is currently listening, for the menu title.
    var isVoiceActive: (() -> Bool)?
    var onToggleWidget: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    override init() {
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = makeIcon()
        statusItem.button?.toolTip = "Alakeya"

        // A persistent menu is the only click handling that works reliably
        // when running via `swift run` (no .app bundle). The first item is
        // the voice toggle — one click on the icon, one click to start.
        let menu = buildMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // ── Menu ──────────────────────────────────────────────

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let voiceItem = NSMenuItem(
            title: "🎤 Слушать",
            action: #selector(handleVoiceToggle),
            keyEquivalent: "")
        voiceItem.target = self
        menu.addItem(voiceItem)

        menu.addItem(.separator())

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
            let listening = self.isVoiceActive?() ?? false
            menu.items.first?.title = listening ? "⏹ Остановить" : "🎤 Слушать"
            if menu.items.count > 2 {
                menu.items[2].title = self.widgetEverShown ? "Показать виджет" : "Добавить виджет"
            }
        }
    }

    @objc private func handleVoiceToggle() {
        widgetEverShown = true
        onToggleVoice?()
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
