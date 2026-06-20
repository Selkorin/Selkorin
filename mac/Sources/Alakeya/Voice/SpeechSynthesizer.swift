import Foundation
import AVFoundation

// ============================================================
// SpeechSynthesizer.swift — TTS via AVSpeechSynthesizer (DOC2:
// "TTS — Apple AVSpeechSynthesizer", local & private by default).
// ============================================================

final class SpeechSynthesizer {
    private let synth = AVSpeechSynthesizer()
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate

    /// Speak text and resume when playback finishes.
    func speak(_ text: String, language: String = "ru-RU") async {
        guard !text.isEmpty else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: language)
            utterance.rate = rate
            let delegate = FinishDelegate { cont.resume() }
            self.retainedDelegate = delegate
            self.synth.delegate = delegate
            self.synth.speak(utterance)
        }
    }

    func stop() { synth.stopSpeaking(at: .immediate) }

    private var retainedDelegate: FinishDelegate?

    private final class FinishDelegate: NSObject, AVSpeechSynthesizerDelegate {
        let onFinish: () -> Void
        init(_ onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { onFinish() }
        func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { onFinish() }
    }
}
