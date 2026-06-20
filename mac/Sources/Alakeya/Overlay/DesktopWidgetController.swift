import AppKit
import SwiftUI

private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }
}

// ============================================================
// FloatingOrbWindowController.swift
// Transparent floating window showing ONLY the orb character.
// No chat, no header, no buttons, no background rectangle.
// ============================================================

private let kOrbPositionKey = "alakeya.orb.position"
private let kOrbSizeKey = "alakeya.orb.size"
private let kOrbDefaultSize: CGFloat = 72
private let kOrbMinSize: CGFloat = 56
private let kOrbMaxSize: CGFloat = 160
private let kOrbSafeInset: CGFloat = 120
private let kOrbVisualScale: CGFloat = 0.5
private let kOrbMinimumVisible: CGFloat = 12

@MainActor
final class FloatingOrbWindowController: NSObject, NSWindowDelegate {

    private var panel: NSPanel!
    private let store: AgentStore
    private let model: FloatingOrbModel

    var onOpenPanel: (() -> Void)?

    private var orbSize: CGFloat { model.size }

    var isShown: Bool { panel?.isVisible ?? false }

    init(store: AgentStore) {
        self.store = store
        self.model = FloatingOrbModel(size: Self.loadOrbSize())
        super.init()
        buildPanel()
        // Observe settings-driven size changes from UserDefaults
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let saved = UserDefaults.standard.double(forKey: kOrbSizeKey)
                guard saved >= Double(kOrbMinSize), saved <= Double(kOrbMaxSize) else { return }
                let newSize = CGFloat(saved)
                guard abs(self.model.size - newSize) > 1 else { return }
                self.model.size = newSize
            }
        }
    }

    // ── Panel construction ────────────────────────────────

    private func buildPanel() {
        let ps = panelSize()
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: ps),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque    = false
        panel.backgroundColor = .clear
        panel.hasShadow   = false
        panel.level       = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        attachContent(to: panel)

        self.panel = panel
        panel.delegate = self
    }

    private func attachContent(to panel: NSPanel) {
        let view = FloatingOrbView(
            store:   store,
            model:   model,
            onOpen:  { [weak self] in self?.onOpenPanel?() },
            onResize: { [weak self] size, commit in self?.setOrbSize(size, commit: commit) },
            onMove: { [weak self] origin, commit in self?.move(to: origin, commit: commit) }
        )
        let hostingView = TransparentHostingView(rootView: view.environment(\.colorScheme, .dark))
        hostingView.wantsLayer = true
        hostingView.layer?.masksToBounds = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        panel.contentViewController = nil
        panel.contentView = hostingView
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.masksToBounds = false
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.layer?.isOpaque = false
    }

    private func panelSize() -> NSSize {
        return NSSize(
            width: orbSize + 140,
            height: orbSize + 160
        )
    }

    // ── Show / Hide ───────────────────────────────────────

    func show() {
        restoreOrDefaultPosition()
        panel.orderFront(nil)
    }

    func hide() { panel.orderOut(nil) }

    func toggle() { if panel.isVisible { hide() } else { show() } }

    // ── Size ──────────────────────────────────────────────

    private static func loadOrbSize() -> CGFloat {
        let saved = UserDefaults.standard.double(forKey: kOrbSizeKey)
        guard saved > 0 else { return kOrbDefaultSize }

        if saved < kOrbMinSize || saved > kOrbMaxSize {
            UserDefaults.standard.set(Double(kOrbDefaultSize), forKey: kOrbSizeKey)
            return kOrbDefaultSize
        }

        return CGFloat(saved)
    }

    private func setOrbSize(_ newSize: CGFloat, commit: Bool) {
        let clampedSize = min(max(newSize, kOrbMinSize), kOrbMaxSize)
        guard abs(clampedSize - model.size) > 0.5 else {
            if commit {
                UserDefaults.standard.set(Double(model.size), forKey: kOrbSizeKey)
                savePosition()
            }
            return
        }

        let oldCenter = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        model.size = clampedSize

        let ps = panelSize()
        let origin = NSPoint(x: oldCenter.x - ps.width / 2, y: oldCenter.y - ps.height / 2)
        panel.setFrame(NSRect(origin: clampedOrigin(origin, size: ps), size: ps), display: true)
        if commit {
            UserDefaults.standard.set(Double(clampedSize), forKey: kOrbSizeKey)
            savePosition()
        }
    }

    // ── Position ──────────────────────────────────────────

    private func restoreOrDefaultPosition() {
        if let d = UserDefaults.standard.dictionary(forKey: kOrbPositionKey),
           let x = d["x"] as? Double, let y = d["y"] as? Double {
            let origin = NSPoint(x: x, y: y)
            let clamped = clampedOrigin(origin)
            panel.setFrameOrigin(clamped)
            if clamped != origin {
                savePosition()
            }
            return
        }

        defaultPosition()
    }

    private func defaultPosition() {
        guard let screen = NSScreen.main else { return }
        panel.setFrameOrigin(safeTopRightOrigin(in: screen.visibleFrame))
    }

    func resetPosition() {
        UserDefaults.standard.removeObject(forKey: kOrbPositionKey)
        defaultPosition()
    }

    private func move(to origin: NSPoint, commit: Bool) {
        panel.setFrameOrigin(clampedOrigin(origin))
        if commit {
            savePosition()
        }
    }

    nonisolated func windowDidMove(_ notification: Notification) {
        // Position is persisted by the interaction layer on mouseUp.
    }

    private func clampedOrigin(_ origin: NSPoint) -> NSPoint {
        clampedOrigin(origin, size: panel.frame.size)
    }

    private func clampedOrigin(_ origin: NSPoint, size: NSSize) -> NSPoint {
        guard let screen = targetScreen(for: origin, size: size) else { return origin }
        let vis = screen.visibleFrame
        let visualOrbSize = orbSize * kOrbVisualScale
        let leadingInset = (size.width - visualOrbSize) / 2
        let verticalInset = (size.height - visualOrbSize) / 2
        let minX = vis.minX + kOrbMinimumVisible - leadingInset - visualOrbSize
        let maxX = vis.maxX - kOrbMinimumVisible - leadingInset
        let minY = vis.minY + kOrbMinimumVisible - verticalInset - visualOrbSize
        let maxY = vis.maxY - kOrbMinimumVisible - verticalInset

        return NSPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }

    private func targetScreen(for origin: NSPoint, size: NSSize) -> NSScreen? {
        let center = NSPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        return NSScreen.screens.first(where: { $0.frame.contains(center) })
            ?? panel.screen
            ?? NSScreen.main
    }

    private func safeTopRightOrigin(in visibleFrame: NSRect) -> NSPoint {
        let ps = panel.frame.size
        let maxX = visibleFrame.maxX - ps.width
        let maxY = visibleFrame.maxY - ps.height
        let x = max(visibleFrame.minX, maxX - kOrbSafeInset)
        let y = max(visibleFrame.minY, maxY - kOrbSafeInset)
        return NSPoint(x: x, y: y)
    }

    private func savePosition() {
        guard let o = panel?.frame.origin else { return }
        UserDefaults.standard.set(["x": o.x, "y": o.y], forKey: kOrbPositionKey)
    }
}
