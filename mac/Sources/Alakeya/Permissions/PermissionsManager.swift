import Foundation
import AppKit
import AVFoundation
import ApplicationServices
import CoreGraphics
import Combine

// ============================================================
// PermissionsManager.swift — the TCC perimeter (DOC1/DOC2): the app
// must explain and request Accessibility, Screen Recording and
// Microphone, and deep-link into System Settings when needed.
//
// Key TCC facts this implementation relies on:
// • The app appears in the System Settings privacy lists only after
//   it actually calls the request API (AXIsProcessTrustedWithOptions
//   with prompt / CGRequestScreenCaptureAccess). A passive preflight
//   never registers the app — the user would have to add it by hand.
// • TCC grants are keyed to the app's code-signing identity. If the
//   binary is rebuilt with a different (ad-hoc) signature, the old
//   grant silently stops matching: System Settings still shows the
//   checkbox ON, but AXIsProcessTrusted() returns false. The only
//   fix is `tccutil reset <service> <bundle-id>` + re-grant, which
//   resetStaleGrant(_:) automates.
// • Accessibility applies immediately once toggled; Screen Recording
//   requires an app relaunch to take effect.
// ============================================================

enum PermKind { case accessibility, screenRecording, microphone }

@MainActor
final class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()

    // ── live status (auto-refreshed) ──────────────────────
    @Published private(set) var accessibilityGranted: Bool = AXIsProcessTrusted()
    @Published private(set) var screenRecordingGranted: Bool = CGPreflightScreenCaptureAccess()
    @Published private(set) var microphoneGranted: Bool =
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

    private var pollTimer: Timer?
    private var activationObserver: NSObjectProtocol?

    private init() {
        // Refresh when the user comes back from System Settings.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshStatuses() }
        }
    }

    /// Re-read all TCC statuses. Cheap; safe to call often.
    func refreshStatuses() {
        let ax = AXIsProcessTrusted()
        let screen = CGPreflightScreenCaptureAccess()
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        if ax != accessibilityGranted { accessibilityGranted = ax }
        if screen != screenRecordingGranted { screenRecordingGranted = screen }
        if mic != microphoneGranted { microphoneGranted = mic }
    }

    /// Poll while a permissions UI is visible so toggles flip the moment
    /// the user grants access in System Settings (no manual "check" needed).
    func startMonitoring() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatuses() }
        }
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // ── requests ──────────────────────────────────────────

    /// Request Accessibility. Shows the system prompt (which also registers
    /// Alakeya in the Privacy → Accessibility list). If the prompt was already
    /// consumed earlier, falls back to opening System Settings.
    /// No app restart is needed — the grant applies as soon as it's toggled.
    @discardableResult
    func requestAccessibility() -> Bool {
        if AXIsProcessTrusted() {
            accessibilityGranted = true
            return true
        }

        // Registers the app in the TCC list and shows the system dialog
        // (once per TCC database state).
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        if !trusted {
            // Prompt may have been consumed previously — take the user
            // straight to the right pane.
            openSettings(.accessibility)
        }
        refreshStatuses()
        return trusted
    }

    /// Request Screen Recording. CGRequestScreenCaptureAccess registers the
    /// app in the Privacy → Screen Recording list and shows the system prompt.
    /// macOS requires an app relaunch after granting this one.
    @discardableResult
    func requestScreenRecording() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            screenRecordingGranted = true
            return true
        }

        let granted = CGRequestScreenCaptureAccess()
        if !granted {
            openSettings(.screenRecording)
        }
        refreshStatuses()
        return granted
    }

    func requestMicrophone() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            microphoneGranted = true
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            refreshStatuses()
            return granted
        default:
            // Previously denied — the system prompt won't show again.
            openSettings(.microphone)
            return false
        }
    }

    // ── stale-grant recovery ──────────────────────────────
    /// The "checkbox is ON but access doesn't work" state: the TCC grant
    /// belongs to an older build of Alakeya (different code signature).
    /// Resets the stale entry so the app can be granted fresh.
    /// Returns true if tccutil executed successfully.
    @discardableResult
    func resetStaleGrant(_ kind: PermKind) -> Bool {
        let service: String
        switch kind {
        case .accessibility:   service = "Accessibility"
        case .screenRecording: service = "ScreenCapture"
        case .microphone:      service = "Microphone"
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "com.selkorin.alakeya"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, bundleID]
        do {
            try process.run()
            process.waitUntilExit()
            refreshStatuses()
            return process.terminationStatus == 0
        } catch {
            return false
        }
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
