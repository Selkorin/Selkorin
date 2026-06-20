import SwiftUI

struct VoiceSettingsView: View {
    @ObservedObject var store: AgentStore

    @State private var isTesting = false
    @State private var statusMessage = ""
    @State private var speechService = SpeechService()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Голос")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(WAI.text)

            settingRow("Активация") {
                Picker("", selection: $store.settings.voice.activation) {
                    Text("Click").tag("click")
                    Text("Wake word").tag("wake")
                    Text("Push to talk").tag("push")
                }
                .labelsHidden()
                .frame(width: 240)
                .onChange(of: store.settings.voice.activation) { _, _ in
                    store.settings.save()
                }
            }

            settingRow("Voice Provider") {
                Picker("", selection: $store.settings.voice.provider) {
                    ForEach(VoiceProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                .labelsHidden()
                .frame(width: 240)
                .onChange(of: store.settings.voice.provider) { _, provider in
                    store.settings.voice.voiceName = provider.defaultVoice
                    store.settings.save()
                }
            }

            settingRow("Voice") {
                Picker("", selection: $store.settings.voice.voiceName) {
                    ForEach(store.settings.voice.provider.availableVoices, id: \.self) { voice in
                        Text(store.settings.voice.provider.voiceDisplayName(voice)).tag(voice)
                    }
                }
                .labelsHidden()
                .frame(width: 240)
                .onChange(of: store.settings.voice.voiceName) { _, _ in
                    store.settings.save()
                }
            }

            if store.settings.voice.provider == .silero {
                Text("Локальный голос. Работает офлайн после установки модели.\nЗапустите scripts/setup_silero_tts.sh для первоначальной настройки.")
                    .font(.system(size: 11))
                    .foregroundStyle(WAI.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(isOn: $store.settings.voice.ttsEnabled) {
                Text("Auto Speak Responses")
                    .font(.system(size: 13))
                    .foregroundStyle(WAI.textDim)
            }
            .toggleStyle(.switch)
            .tint(WAI.accent)
            .onChange(of: store.settings.voice.ttsEnabled) { _, _ in
                store.settings.save()
            }

            Toggle(isOn: $store.settings.voice.localOnly) {
                Text("Локальная речь (privacy)")
                    .font(.system(size: 13))
                    .foregroundStyle(WAI.textDim)
            }
            .toggleStyle(.switch)
            .tint(WAI.accent)
            .onChange(of: store.settings.voice.localOnly) { _, _ in
                store.settings.save()
            }

            HStack(spacing: 14) {
                Button(isTesting ? "Speaking…" : "Test Voice") {
                    Task { await testVoice() }
                }
                .buttonStyle(.bordered)
                .disabled(isTesting)

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(WAI.textMuted)
                }
            }
        }
    }

    private func settingRow(_ title: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(WAI.textDim)
            Spacer()
            control()
        }
    }

    private func testVoice() async {
        isTesting = true
        statusMessage = ""
        defer { isTesting = false }

        let phrase = store.settings.voice.provider == .silero
            ? "Привет, я Алакея. Это локальный голос Silero."
            : "Привет, я Алакея."
        do {
            try await speechService.speak(phrase, settings: store.settings)
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
