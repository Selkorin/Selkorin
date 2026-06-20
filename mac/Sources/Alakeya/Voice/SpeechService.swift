import Foundation

@MainActor
final class SpeechService {
    private let system = SystemSpeechService()
    private let silero = LocalSileroTTSService()
    private var current: SpeechServiceProvider?

    func speak(_ text: String, settings: Settings) async throws {
        // In localOnly mode, network TTS (OpenAI) is blocked; local providers are allowed
        let requested = settings.voice.provider
        let provider: VoiceProvider = (settings.voice.localOnly && !requested.isLocal) ? .system : requested

        let service: SpeechServiceProvider
        switch provider {
        case .system:
            service = system
        case .openAI:
            if let key = try AIProviderStore.shared.apiKey(for: AIProviderKind.openAI.rawValue),
               !key.isEmpty {
                service = OpenAITTSService(apiKey: key)
            } else {
                service = system
            }
        case .silero:
            service = silero
        }

        current?.stop()
        current = service
        let voice: String
        if service is SystemSpeechService && provider == .openAI {
            voice = VoiceProvider.system.defaultVoice
        } else {
            voice = settings.voice.voiceName
        }
        try await service.speak(text, voice: voice)
    }

    func stop() {
        current?.stop()
        current = nil
    }
}
