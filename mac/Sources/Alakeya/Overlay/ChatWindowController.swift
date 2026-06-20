import AppKit
import SwiftUI

// ============================================================
// ChatWindowController.swift
// ============================================================

// .titled NSWindow becomes key/main by default, so no subclass
// needed for keyboard input. We keep this for clarity.
private final class ChatWindow: NSWindow {
    override var canBecomeKey:  Bool { true }
    override var canBecomeMain: Bool { true }
}

private let kDefaultWindowSize = NSSize(width: 1440, height: 780)
private let kMinimumWindowSize = NSSize(width: 960, height: 540)

@MainActor
final class MainPanelWindowController: NSObject, NSWindowDelegate {

    private var window: ChatWindow!
    private var eventMonitor: Any?

    let store: AgentStore
    private let runner: ToolRunner
    private let voice:  VoiceController
    private let updateManager: UpdateManager

    // Fullscreen state
    private var isExpanded  = false
    private var normalFrame = NSRect.zero

    // Token cancels stale completion blocks (e.g. show() during minimize)
    private var animToken = 0

    init(store: AgentStore, runner: ToolRunner, voice: VoiceController, updateManager: UpdateManager) {
        self.store         = store
        self.runner        = runner
        self.voice         = voice
        self.updateManager = updateManager
        super.init()
        buildWindow()
    }

    // ── Build ─────────────────────────────────────────────

    private func buildWindow() {
        // Start from one calm, predictable size every time. Resizing remains
        // fully available during the session.
        let size = fittedToVisibleScreen(kDefaultWindowSize)
        let w = ChatWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.isOpaque           = false
        w.backgroundColor    = .clear
        w.hasShadow          = true
        w.level              = .normal
        w.isReleasedWhenClosed = false
        // Resize bounds — both minSize and contentMinSize needed when using NSHostingController
        w.minSize        = kMinimumWindowSize
        w.contentMinSize = kMinimumWindowSize
        // No hard maxSize — let users expand the window as wide as the screen allows
        w.maxSize        = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        // Transparent titlebar — content fills the whole frame
        w.titlebarAppearsTransparent = true
        w.titleVisibility            = .hidden
        // Hide native traffic lights (we use custom ones in SwiftUI header)
        w.standardWindowButton(.closeButton)?   .isHidden = true
        w.standardWindowButton(.miniaturizeButton)?.isHidden = true
        w.standardWindowButton(.zoomButton)?    .isHidden = true
        // Draggable from any empty area
        w.isMovableByWindowBackground = true

        let root = RootView(
            store:             store,
            updateManager:     updateManager,
            runner:            runner,
            voice:             voice,
            onClosePanel:      { [weak self] in self?.close() },
            onMinimizePanel:   { [weak self] in self?.minimize() },
            onFullscreenPanel: { [weak self] in self?.toggleFullscreen() },
            onBrowserToggle:   { [weak self] in self?.setBrowserPresented($0) }
        )
        let hvc = NSHostingController(rootView: root.environment(\.colorScheme, .dark))
        w.contentViewController = hvc
        // Allow the orb halo to render beyond the hosting view boundary
        hvc.view.wantsLayer = true
        hvc.view.layer?.masksToBounds = false
        self.window = w
        w.delegate = self   // set AFTER self.window is assigned to avoid crash in windowDidResize

        // Set default browser width (browser opens only when user requests it)
        if !UserDefaults.standard.bool(forKey: "alakeya.browserInitialized") {
            UserDefaults.standard.set(true, forKey: "alakeya.browserInitialized")
            UserDefaults.standard.set(Double(680), forKey: "browserSidebarWidth")
        }
        // Browser opens on-demand only — NOT on app launch
    }

    // ── Toggle (from widget tap) ──────────────────────────

    func toggle() {
        if window.isVisible {
            close()
        } else {
            open()
        }
    }

    func open() {
        if !window.isVisible {
            positionCentered()
            show()
        } else {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func toggle(relativeTo anchor: NSWindow) {
        if window.isVisible { close() } else { position(near: anchor); show() }
    }

    // ── Open from menu "Настройки" ────────────────────────

    func openWithSettings() {
        if !window.isVisible { positionCentered(); show() }
        store.showSettings = true
    }

    func openActivityLog() {
        if !window.isVisible { positionCentered(); show() }
        store.showActivity = true
    }

    // ── Show ──────────────────────────────────────────────

    private func show() {
        animToken += 1
        // Simple opacity fade — no scale so the window never looks tiny
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: false)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            self.window.animator().alphaValue = 1
        }
    }

    // ── Close (X button / outside click / Esc) ────────────

    func close() {
        removeEventMonitor()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            self.window.animator().alphaValue = 0
        }, completionHandler: {
            self.window.orderOut(nil)
            self.window.alphaValue = 1
        })
    }

    // ── Minimize (yellow dot): scale+fade ─────────────────

    func minimize() {
        guard window.isVisible else { return }
        removeEventMonitor()

        let cv = window.contentView!
        cv.wantsLayer = true

        guard let layer = cv.layer else { close(); return }

        layer.removeAllAnimations()
        animToken += 1
        let capturedToken = animToken
        let dur: CFTimeInterval = 0.28
        let timing = CAMediaTimingFunction(name: .easeInEaseOut)

        let scaleAnim              = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue        = 1.0
        scaleAnim.toValue          = 0.15
        scaleAnim.duration         = dur
        scaleAnim.timingFunction   = timing
        scaleAnim.fillMode         = .forwards
        scaleAnim.isRemovedOnCompletion = false

        let alphaAnim              = CABasicAnimation(keyPath: "opacity")
        alphaAnim.fromValue        = 1.0
        alphaAnim.toValue          = 0.0
        alphaAnim.duration         = dur
        alphaAnim.timingFunction   = timing
        alphaAnim.fillMode         = .forwards
        alphaAnim.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.animToken == capturedToken else { return }
            self.window.orderOut(nil)
            layer.removeAllAnimations()
            layer.transform = CATransform3DIdentity
            layer.opacity   = 1
        }
        layer.add(scaleAnim, forKey: "min.scale")
        layer.add(alphaAnim, forKey: "min.opacity")
        CATransaction.commit()
    }

    // ── Fullscreen toggle (green dot) ─────────────────────

    func toggleFullscreen() {
        if isExpanded {
            isExpanded = false
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.window.animator().setFrame(self.normalFrame, display: true)
            }
        } else {
            isExpanded  = true
            normalFrame = window.frame
            guard let screen = NSScreen.main else { return }
            let vis = screen.visibleFrame
            let pad: CGFloat = 40
            let expanded = NSRect(x: vis.minX + pad, y: vis.minY + pad,
                                  width: vis.width - pad * 2, height: vis.height - pad * 2)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.window.animator().setFrame(expanded, display: true)
            }
        }
    }

    func setBrowserPresented(_ presented: Bool) {
        // Never force-resize the window — the SwiftUI split handles layout internally.
        // Keep a single consistent minimum so the user can't squish below readable bounds.
        window.minSize        = kMinimumWindowSize
        window.contentMinSize = kMinimumWindowSize
    }

    // ── Positioning ───────────────────────────────────────

    private func position(near anchor: NSWindow) {
        let af = anchor.frame
        let cw = window.frame.size.width
        let ch = window.frame.size.height
        var origin = NSPoint(x: af.midX - cw / 2, y: af.maxY + 8)
        if let screen = NSScreen.main {
            let vis = screen.visibleFrame
            origin.x = max(vis.minX + 8, min(origin.x, vis.maxX - cw - 8))
            if origin.y + ch > vis.maxY { origin.y = af.minY - ch - 8 }
            origin.y = max(vis.minY + 8, origin.y)
        }
        window.setFrameOrigin(origin)
    }

    private func positionCentered() {
        guard let screen = NSScreen.main else { return }
        let vis = screen.visibleFrame
        window.setFrameOrigin(NSPoint(
            x: vis.midX - window.frame.size.width  / 2,
            y: vis.midY - window.frame.size.height / 2
        ))
    }

    private func fittedToVisibleScreen(_ size: NSSize) -> NSSize {
        guard let visible = NSScreen.main?.visibleFrame.size else { return size }
        let maxWidth = max(kMinimumWindowSize.width, visible.width * 0.86)
        let maxHeight = max(kMinimumWindowSize.height, visible.height * 0.84)
        return NSSize(
            width: min(maxWidth, max(kMinimumWindowSize.width, size.width)),
            height: min(maxHeight, max(kMinimumWindowSize.height, size.height))
        )
    }

    // ── Helpers ───────────────────────────────────────────

    private func setupEventMonitor() {
        removeEventMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in self?.close() }
    }

    private func removeEventMonitor() {
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }

    // ── NSWindowDelegate ──────────────────────────────────

    func windowShouldClose(_ sender: NSWindow) -> Bool { close(); return false }

    // Hard floor on live resize — prevents NSHostingController from allowing
    // the window to shrink below the minimum regardless of SwiftUI layout.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(
            width: max(kMinimumWindowSize.width, frameSize.width),
            height: max(kMinimumWindowSize.height, frameSize.height)
        )
    }

    func windowDidResize(_ notification: Notification) {
        // SwiftUI reacts to live geometry changes; no persisted legacy frame
        // is restored on the next launch.
    }
}
