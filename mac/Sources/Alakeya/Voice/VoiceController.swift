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

    var isListening: Bool { listening }

    /// Toggle listening on/off — used by the menu bar icon.
    func toggle() {
        if listening { stop() } else { start() }
    }

    init(store: AgentStore, runner: ToolRunner) {
        self.store = store
        self.runner = runner
        recognizer.onPartial = { [weak self] text in
            Task { @MainActor in self?.store.transcript = text }
        }
    }

    func start() {
        print("[VOICE] start() called, listening=\(listening)")
        guard !listening else { print("[VOICE] already listening, returning"); return }
        recognizer.localOnly = store.settings.voice.localOnly
        Task { @MainActor in
            print("[VOICE] Task started")
            let micOK = await PermissionsManager.shared.requestMicrophone()
            print("[VOICE] microphone permission: \(micOK)")
            let speechOK = await recognizer.requestAuthorization()
            print("[VOICE] speech authorization: \(speechOK)")
            guard speechOK else {
                store.showError("Нет доступа к распознаванию речи.", blocked: true); return
            }
            do {
                store.transcript = ""
                store.setStatus(.listening)
                print("[VOICE] status set to listening, starting recognizer")
                try recognizer.start()
                listening = true
                print("[VOICE] recognizer started OK")
            } catch {
                print("[VOICE] recognizer.start() threw: \(error)")
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
