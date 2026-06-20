import Foundation

// ============================================================
// Settings.swift — user settings, ported from SettingsWindow's
// SETTINGS_DEFAULTS (handoff/src/SettingsWindow.jsx).
// ============================================================

enum VoiceMode: String, Codable, CaseIterable {
    case off        // silent — display text only
    case brief      // short spoken summary, full text in chat
    case voiceChat  // longer responses for voice-first interaction

    var icon: String {
        switch self {
        case .off:       return "speaker.slash"
        case .brief:     return "speaker.wave.1"
        case .voiceChat: return "speaker.wave.3"
        }
    }

    func next() -> VoiceMode {
        switch self {
        case .off:       return .brief
        case .brief:     return .voiceChat
        case .voiceChat: return .off
        }
    }
}

struct Settings: Codable {
    struct Appearance: Codable {
        var size = "medium"          // small | medium | large
        var corner = "bottom-right"
        var theme = "system"
        var glow = 0.68
        var particles = 0.5
        var faceStyle = "friendly"
        var accentHex: UInt32 = 0x1D9BF0
    }
    struct Voice: Codable {
        var activation = "push"      // click | wake | push
        var wakeWord = "Hey Alakeya"
        var micDeviceId = "default"
        var ttsEnabled = true        // legacy — kept for Settings UI compat
        var voiceMode: VoiceMode = .brief
        var speed = 1.0
        var localOnly = false        // privacy mode (DOC2 §"Локальная речь")
        var provider: VoiceProvider = .openAI
        var voiceName = VoiceProvider.openAI.defaultVoice

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            activation = try container.decodeIfPresent(String.self, forKey: .activation) ?? "push"
            wakeWord = try container.decodeIfPresent(String.self, forKey: .wakeWord) ?? "Hey Alakeya"
            micDeviceId = try container.decodeIfPresent(String.self, forKey: .micDeviceId) ?? "default"
            ttsEnabled = try container.decodeIfPresent(Bool.self, forKey: .ttsEnabled) ?? true
            speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? 1.0
            localOnly = try container.decodeIfPresent(Bool.self, forKey: .localOnly) ?? false
            provider = try container.decodeIfPresent(VoiceProvider.self, forKey: .provider) ?? .openAI
            voiceName = try container.decodeIfPresent(String.self, forKey: .voiceName)
                ?? provider.defaultVoice
            // Migrate: if voiceMode not saved yet, derive from legacy ttsEnabled
            voiceMode = try container.decodeIfPresent(VoiceMode.self, forKey: .voiceMode)
                ?? (ttsEnabled ? .brief : .off)
        }
    }
    struct Models: Codable {
        var activeProviderID = AIProviderKind.openAI.rawValue
        var providers = AIProviderConfiguration.defaults
        var activeSkillID: String = "general"

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            activeProviderID = try container.decodeIfPresent(
                String.self,
                forKey: .activeProviderID
            ) ?? AIProviderKind.openAI.rawValue

            let saved = try container.decodeIfPresent(
                [AIProviderConfiguration].self,
                forKey: .providers
            ) ?? []
            providers = AIProviderConfiguration.defaults.map { defaultConfiguration in
                saved.first(where: { $0.id == defaultConfiguration.id }) ?? defaultConfiguration
            }
            activeSkillID = try container.decodeIfPresent(String.self, forKey: .activeSkillID) ?? "general"
        }
    }
    struct Automation: Codable {
        var autoSafe = false         // auto-confirm low-risk
        var neverSend = true
        var neverDelete = true
        var neverPay = true
        var allowedApps = ["Safari", "Chrome", "Notes", "Mail"]
    }
    struct Developer: Codable {
        var model = "gpt-4o"
        var sttModel = "whisper-1"
        var ttsVoice = "alloy"
    }
    struct Updates: Codable {
        var autoCheck: Bool = true
        var channel: UpdateChannel = .stable
        var lastChecked: Date? = nil
        var skippedVersion: String? = nil
    }

    var appearance = Appearance()
    var voice = Voice()
    var models = Models()
    var automation = Automation()
    var developer = Developer()
    var updates = Updates()

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appearance = try container.decodeIfPresent(Appearance.self, forKey: .appearance) ?? Appearance()
        voice = try container.decodeIfPresent(Voice.self, forKey: .voice) ?? Voice()
        models = try container.decodeIfPresent(Models.self, forKey: .models) ?? Models()
        automation = try container.decodeIfPresent(Automation.self, forKey: .automation) ?? Automation()
        developer = try container.decodeIfPresent(Developer.self, forKey: .developer) ?? Developer()
        updates = try container.decodeIfPresent(Updates.self, forKey: .updates) ?? Updates()
    }

    static func load() -> Settings {
        guard let data = UserDefaults.standard.data(forKey: "alakeya.settings"),
              let s = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "alakeya.settings")
        }
    }
}

struct OnboardingResult {
    var accent: UInt32? = nil
    var faceStyle: String? = nil
}
