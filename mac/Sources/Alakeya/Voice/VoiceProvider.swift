import Foundation

enum VoiceProvider: String, Codable, CaseIterable, Identifiable {
    case system
    case openAI
    case silero

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System Voice"
        case .openAI: return "OpenAI TTS"
        case .silero: return "Silero Local TTS"
        }
    }

    var isLocal: Bool {
        switch self {
        case .system, .silero: return true
        case .openAI: return false
        }
    }

    var availableVoices: [String] {
        switch self {
        case .system: return ["ru-RU", "en-US"]
        case .openAI: return ["nova", "alloy", "coral", "sage", "shimmer"]
        case .silero: return ["xenia", "aidar", "baya", "kseniya", "eugene"]
        }
    }

    var defaultVoice: String {
        switch self {
        case .system: return "ru-RU"
        case .openAI: return "nova"
        case .silero: return "xenia"
        }
    }

    func voiceDisplayName(_ voice: String) -> String {
        guard self == .silero else { return voice }
        return "Silero — \(voice.capitalized)"
    }
}

@MainActor
protocol SpeechServiceProvider {
    func speak(_ text: String, voice: String) async throws
    func stop()
}
