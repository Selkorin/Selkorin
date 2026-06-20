import Foundation
import AppKit
import AVFoundation
import ApplicationServices
import CoreGraphics

// ============================================================
// PermissionsManager.swift — the TCC perimeter (DOC1/DOC2): the app
// must explain and request Accessibility, Screen Recording and
// Microphone, and deep-link into System Settings when needed.
// ============================================================

enum PermKind { case accessibility, screenRecording, microphone }

final class PermissionsManager {
    static let shared = PermissionsManager()

    // ── status ────────────────────────────────────────────
    var accessibilityGranted: Bool { AXIsProcessTrusted() }

    var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }

    var microphoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    // ── requests ──────────────────────────────────────────
    /// Shows the system Accessibility prompt the first time.
    @discardableResult
    func requestAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    @discardableResult
    func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    // ── deep links into System Settings ───────────────────
    func openSettings(_ kind: PermKind) {
        let anchor: String
        switch kind {
        case .accessibility:   anchor = "Privacy_Accessibility"
        case .screenRecording: anchor = "Privacy_ScreenCapture"
        case .microphone:      anchor = "Privacy_Microphone"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
