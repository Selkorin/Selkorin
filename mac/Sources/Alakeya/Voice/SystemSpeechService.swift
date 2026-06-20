import AVFoundation
import Foundation

@MainActor
final class SystemSpeechService: NSObject, SpeechServiceProvider, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Error>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, voice: String) async throws {
        guard !text.isEmpty else { return }
        stop()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestVoice(hint: voice)
        // Slightly slower than default for more natural pacing
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate,
                             AVSpeechUtteranceDefaultSpeechRate - 0.04)
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            synthesizer.speak(utterance)
        }
    }

    // Picks the best available voice: prefers enhanced/premium quality.
    private static func bestVoice(hint: String) -> AVSpeechSynthesisVoice? {
        // Try exact identifier first
        if let v = AVSpeechSynthesisVoice(identifier: hint) { return v }

        // Try as language code
        let lang = hint.isEmpty ? "ru-RU" : hint

        // Prefer "enhanced" or "premium" quality voices for the language
        let all = AVSpeechSynthesisVoice.speechVoices()
        let langVoices = all.filter { $0.language.hasPrefix(lang.prefix(2)) }

        let quality: [AVSpeechSynthesisVoiceQuality] = [.premium, .enhanced, .default]
        for q in quality {
            if let v = langVoices.first(where: { $0.quality == q }) { return v }
        }

        // Final fallback
        return AVSpeechSynthesisVoice(language: lang)
            ?? AVSpeechSynthesisVoice(language: "ru-RU")
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        resume()
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.resume() }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.resume() }
    }

    private func resume() {
        continuation?.resume()
        continuation = nil
    }
}

