import Foundation
import Speech
import AVFoundation

// ============================================================
// SpeechRecognizer.swift — push-to-talk STT via the Speech framework
// (DOC2: "для MVP делайте push-to-talk"). On-device when available
// for the privacy mode; swap in whisper.cpp as an offline fallback.
// ============================================================

final class SpeechRecognizer {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var onPartial: ((String) -> Void)?
    var localOnly = false

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    /// Begin streaming recognition; partials flow through `onPartial`.
    func start() throws {
        stop()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if localOnly { req.requiresOnDeviceRecognition = true }
        request = req

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer?.recognitionTask(with: req) { [weak self] result, _ in
            if let result { self?.onPartial?(result.bestTranscription.formattedString) }
        }
    }

    /// Stop capture and return the final transcript.
    func stop() {
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning { audioEngine.stop() }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }
}
