import AppKit
import SwiftUI

// ============================================================
// OrbWindow.swift — borderless, transparent, always-on-top overlay
// panel (HANDOFF §5.2). Auto-sizes to its SwiftUI content; anchors to
// the bottom-right corner when small, centers for the larger modals.
// ============================================================

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }     // text field needs key
    override var canBecomeMain: Bool { false }
}

final class OrbWindowController: NSWindowController, NSWindowDelegate {

    init(rootView: some View) {
        let host = NSHostingController(rootView: rootView)
        host.sizingOptions = [.preferredContentSize] // window follows content size

        let panel = OverlayPanel(
            contentViewController: host)
        panel.styleMask = [.borderless, .nonactivatingPanel]
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true   // drag anywhere (HANDOFF §5.3)
        panel.hidesOnDeactivate = false

        super.init(window: panel)
        panel.delegate = self
        anchorBottomRight()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func show() {
        window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    // Re-anchor whenever the content (and thus the window) resizes.
    func windowDidResize(_ notification: Notification) {
        guard let w = window else { return }
        if w.frame.width < 480 { anchorBottomRight() } else { center() }
    }

    private func anchorBottomRight() {
        guard let w = window, let screen = NSScreen.main else { return }
        let vis = screen.visibleFrame
        let size = w.frame.size
        w.setFrameOrigin(NSPoint(x: vis.maxX - size.width - 16, y: vis.minY + 16))
    }

    private func center() {
        guard let w = window, let screen = NSScreen.main else { return }
        let vis = screen.visibleFrame
        let size = w.frame.size
        w.setFrameOrigin(NSPoint(x: vis.midX - size.width / 2, y: vis.midY - size.height / 2))
    }
}
