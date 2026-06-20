import Foundation
import AppKit
import CoreGraphics

// ============================================================
// InputFallback.swift — clipboard + ⌘V and raw CGEvent keystrokes.
// Last resort when AX value-setting fails (DOC1/DOC2 paste fallback).
// ============================================================

final class InputFallback {

    /// Put text on the pasteboard and send ⌘V (handles Unicode/layouts
    /// far more reliably than per-character key events — DOC1 §production-fallback).
    func pasteText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        let src = CGEventSource(stateID: .combinedSessionState)
        let vKeyV: CGKeyCode = 0x09 // 'v'
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKeyV, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKeyV, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// Press a virtual key (e.g. Return = 36) with optional modifier flags.
    func pressKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    func pressReturn() { pressKey(0x24) } // kVK_Return

    /// Click at an absolute screen point (coordinate fallback only).
    func click(at point: CGPoint) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
