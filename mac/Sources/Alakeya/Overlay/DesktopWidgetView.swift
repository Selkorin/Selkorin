import SwiftUI
import AppKit

// ============================================================
// FloatingOrbView — content of the transparent orb window.
// Orb character + label/status only. No panel UI, no chat, no chrome.
// ============================================================

@MainActor
final class FloatingOrbModel: ObservableObject {
    @Published var size: CGFloat

    init(size: CGFloat) {
        self.size = size
    }
}

private final class WidgetInteractionView: NSView {
    var currentSize: CGFloat = 72
    var onOpen: (() -> Void)?
    var onResize: ((CGFloat, Bool) -> Void)?
    var onMove: ((NSPoint, Bool) -> Void)?

    private var mouseStart: NSPoint?
    private var windowStart: NSPoint?
    private var sizeStart: CGFloat = 72
    private var pendingSize: CGFloat?
    private var resizingFromMouseDown = false
    private var didDrag = false
    private var didResize = false
    private var magnifyCommitTimer: Timer?

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isOpaque: Bool { false }

    override func mouseDown(with event: NSEvent) {
        magnifyCommitTimer?.invalidate()
        magnifyCommitTimer = nil
        mouseStart = NSEvent.mouseLocation
        windowStart = window?.frame.origin
        sizeStart = currentSize
        pendingSize = nil
        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        resizingFromMouseDown = modifierFlags.contains(.option) || modifierFlags.contains(.shift)
        didDrag = false
        didResize = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseStart, let origin = windowStart else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - start.x
        let dy = current.y - start.y
        didDrag = didDrag || abs(dx) > 2 || abs(dy) > 2

        if resizingFromMouseDown {
            didResize = true
            let nextSize = sizeStart + dy * 0.4
            pendingSize = nextSize
            onResize?(nextSize, false)
        } else {
            onMove?(NSPoint(x: origin.x + dx, y: origin.y + dy), false)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if didResize {
            onResize?(pendingSize ?? currentSize, true)
        } else if didDrag {
            onMove?(window?.frame.origin ?? windowStart ?? .zero, true)
        } else {
            onOpen?()
        }
    }

    override func magnify(with event: NSEvent) {
        magnifyCommitTimer?.invalidate()
        let nextSize = currentSize + (event.magnification * 90)
        pendingSize = nextSize
        let isEnding = event.phase == .ended || event.phase == .cancelled
        onResize?(nextSize, isEnding)

        if !isEnding {
            magnifyCommitTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.onResize?(self.pendingSize ?? self.currentSize, true)
            }
        }
    }

    deinit {
        magnifyCommitTimer?.invalidate()
    }
}

private struct WidgetInteractionLayer: NSViewRepresentable {
    let currentSize: CGFloat
    var onOpen: (() -> Void)?
    var onResize: ((CGFloat, Bool) -> Void)?
    var onMove: ((NSPoint, Bool) -> Void)?

    func makeNSView(context: Context) -> WidgetInteractionView {
        let view = WidgetInteractionView()
        view.wantsLayer = true
        view.layer?.masksToBounds = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.isOpaque = false
        return view
    }

    func updateNSView(_ view: WidgetInteractionView, context: Context) {
        view.currentSize = currentSize
        view.onOpen = onOpen
        view.onResize = onResize
        view.onMove = onMove
    }
}

// ── Floating Orb View ─────────────────────────────────────

struct FloatingOrbView: View {
    @ObservedObject var store: AgentStore
    @ObservedObject var model: FloatingOrbModel
    var onOpen: (() -> Void)?
    var onResize: ((CGFloat, Bool) -> Void)?
    var onMove: ((NSPoint, Bool) -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            orbArea

            if let stateText {
                stateCloud(stateText)
                    .transition(
                        .opacity.combined(
                            with: .scale(scale: 0.92, anchor: .leading)
                        )
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .animation(WAI.easeOut, value: store.status)
        .overlay(
            WidgetInteractionLayer(
                currentSize: model.size,
                onOpen: onOpen,
                onResize: onResize,
                onMove: onMove
            )
        )
    }

    // ── Orb + aura ────────────────────────────────────────

    private var visualOrbSize: CGFloat {
        model.size * 0.5
    }

    private var orbArea: some View {
        OrbView(
            state: store.assistantState,
            emotion: store.orbEmotion,
            size: visualOrbSize,
            onTap: nil
        )
            .frame(width: visualOrbSize, height: visualOrbSize)
            .allowsHitTesting(false)
    }

    private var stateText: String? {
        switch store.status {
        case .ready:
            return nil
        case .listening:
            return "Слушаю..."
        case .thinking:
            return "Думаю..."
        case .acting:
            return "Выполняю..."
        case .speaking:
            return "Отвечаю..."
        case .awaiting:
            return "Жду..."
        case .error:
            return "Ошибка"
        }
    }

    private func stateCloud(_ text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(WAI.accentBright)
                .frame(width: 4, height: 4)
                .shadow(color: WAI.accentGlow, radius: 4)

            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WAI.text)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(WAI.surfaceStrong, in: Capsule())
        .overlay {
            Capsule()
                .stroke(WAI.lineAccent, lineWidth: 1)
        }
        .shadow(color: WAI.accentGlow.opacity(0.35), radius: 10)
        .fixedSize()
        .allowsHitTesting(false)
    }
}
