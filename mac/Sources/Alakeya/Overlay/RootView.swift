import SwiftUI
import AppKit

// ============================================================
// RootView.swift — routes to the correct surface:
//   onboarding → settings → activity → permission → chat
// ============================================================

struct RootView: View {
    @ObservedObject var store: AgentStore
    @ObservedObject var updateManager: UpdateManager
    let runner: ToolRunner
    let voice: VoiceController
    var onClosePanel:    (() -> Void)? = nil
    var onMinimizePanel: (() -> Void)? = nil
    var onFullscreenPanel: (() -> Void)? = nil
    var onBrowserToggle: ((Bool) -> Void)? = nil

    var body: some View {
        Group {
            if !store.onboarded {
                OnboardingView(
                    onComplete: { store.completeOnboarding($0) },
                    onSkip:     { store.completeOnboarding(.init()) })
            } else if let pending = store.pending {
                PermissionCardView(
                    action:        pending.action,
                    onAllowOnce:   { runner.resolvePending(.once) },
                    onAlwaysAllow: { runner.resolvePending(.always) },
                    onCancel:      { runner.resolvePending(.deny) })
            } else {
                ChatView(
                    store:        store,
                    updateManager: updateManager,
                    onSubmit:     {
                        guard let sessionID = store.activeSessionID else { return }
                        runner.runTask(
                            $0,
                            sessionID: sessionID,
                            agentID: store.settings.models.activeSkillID
                        )
                    },
                    onVoiceStart: { voice.start() },
                    onVoiceStop:  { voice.stop() },
                    onClose:      { onClosePanel?() },
                    onMinimize:   { onMinimizePanel?() },
                    onFullscreen: { onFullscreenPanel?() },
                    onBrowserToggle: { onBrowserToggle?($0) })
            }
        }
        .overlay(alignment: .topTrailing) {
            if let error = store.error {
                ErrorToastView(
                    message: error.message,
                    blocked: error.blocked,
                    onDismiss: { store.error = nil },
                    onOpenSettings: {
                        store.error = nil
                        store.showSettings = true
                    }
                )
                .padding(18)
            }
        }
        // Update prompt — shown as a centered modal overlay
        .overlay {
            if updateManager.showPrompt, let info = updateManager.pendingUpdate {
                UpdatePromptView(info: info, manager: updateManager)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .animation(.easeOut(duration: 0.2), value: updateManager.showPrompt)
            }
        }
        .preferredColorScheme({
            switch store.settings.appearance.theme {
            case "light": return .light
            case "dark":  return .dark
            default:      return .dark
            }
        }())
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "alakeya-activity.csv"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? store.exportCSV().data(using: .utf8)?.write(to: url)
            }
        }
    }
}
