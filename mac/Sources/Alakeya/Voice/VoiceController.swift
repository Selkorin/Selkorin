import Foundation

// ============================================================
// VoiceController.swift — bridges push-to-talk STT to the agent:
// start → Слушаю + live partials; stop → transcribe → runTask.
// ============================================================

@MainActor
final class VoiceController {
    private let store: AgentStore
    private let runner: ToolRunner
    private let recognizer = SpeechRecognizer()
    private var listening = false

    init(store: AgentStore, runner: ToolRunner) {
        self.store = store
        self.runner = runner
        recognizer.onPartial = { [weak self] text in
            Task { @MainActor in self?.store.transcript = text }
        }
    }

    func start() {
        guard !listening else { return }
        recognizer.localOnly = store.settings.voice.localOnly
        Task { @MainActor in
            // Request microphone lazily here, so the app works via `swift run`
            // (no Info.plist in bundle) without crashing on startup.
            _ = await PermissionsManager.shared.requestMicrophone()
            guard await recognizer.requestAuthorization() else {
                store.showError("Нет доступа к распознаванию речи.", blocked: true); return
            }
            do {
                store.transcript = ""
                store.setStatus(.listening)
                try recognizer.start()
                listening = true
            } catch {
                store.showError("Не удалось включить микрофон.", blocked: false)
            }
        }
    }

    func stop() {
        guard listening else { return }
        listening = false
        recognizer.stop()
        let text = store.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { store.setStatus(.ready) }
        else {
            guard let sessionID = store.activeSessionID else { return }
            let agentID = store.settings.models.activeSkillID
            store.appendMessage(ChatMessage(role: .user, content: text))
            runner.runTask(text, sessionID: sessionID, agentID: agentID)
        }
    }
}
