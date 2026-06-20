import AVFoundation
import Foundation

// Dev-only: Silero Russian TTS via Python sidecar.
// Requires scripts/setup_silero_tts.sh to be run once.
// NOTE: Before commercial distribution, verify Silero model license.
@MainActor
final class LocalSileroTTSService: SpeechServiceProvider {
    private var player: AVAudioPlayer?

    func speak(_ text: String, voice: String) async throws {
        guard !text.isEmpty else { return }
        stop()

        let python = Self.pythonPath
        let script = Self.scriptPath

        print("""
        [Voice] provider=Silero Local TTS speaker=\(voice) \
        textLength=\(text.count)
        """)

        guard !python.isEmpty, FileManager.default.fileExists(atPath: python) else {
            throw SileroError.notInstalled
        }
        guard FileManager.default.fileExists(atPath: script) else {
            throw SileroError.scriptNotFound(script)
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("alakeya_silero_\(UUID().uuidString).wav")
        print("[Voice] output=\(outputURL.path)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [
            script,
            "--text", text,
            "--speaker", voice,
            "--output", outputURL.path,
            "--sample-rate", "48000",
            "--device", "cpu",
        ]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in cont.resume() }
            do {
                try process.run()
            } catch {
                cont.resume(throwing: error)
            }
        }

        let exitCode = process.terminationStatus
        let stderrText = String(
            data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        if exitCode != 0 {
            print("[Voice] Silero TTS failed: python=\(python) exitCode=\(exitCode) stderr=\(stderrText.prefix(300))")
            if stderrText.contains("ModuleNotFoundError") || stderrText.contains("No module named") {
                throw SileroError.notInstalled
            }
            throw SileroError.failed(stderrText.isEmpty ? "exit \(exitCode)" : String(stderrText.prefix(300)))
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw SileroError.outputNotFound
        }

        let audioPlayer = try AVAudioPlayer(contentsOf: outputURL)
        self.player = audioPlayer
        audioPlayer.prepareToPlay()
        guard audioPlayer.play() else { throw SileroError.playbackFailed }

        while audioPlayer.isPlaying {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        self.player = nil
        try? FileManager.default.removeItem(at: outputURL)
    }

    func stop() {
        player?.stop()
        player = nil
    }

    // ── Path resolution ───────────────────────────────────

    static var projectRoot: URL {
        // In dev .app: .build/Alakeya.app → .build → project root
        URL(fileURLWithPath: Bundle.main.bundlePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static var scriptPath: String {
        projectRoot.appendingPathComponent("scripts/silero_tts.py").path
    }

    static var pythonPath: String {
        let venv = projectRoot.appendingPathComponent(".venv/silero/bin/python3").path
        if FileManager.default.fileExists(atPath: venv) { return venv }
        for p in ["/usr/local/bin/python3", "/opt/homebrew/bin/python3", "/usr/bin/python3"] {
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        return ""
    }
}

enum SileroError: LocalizedError {
    case notInstalled
    case scriptNotFound(String)
    case outputNotFound
    case playbackFailed
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Silero Local TTS не установлен. Запустите scripts/setup_silero_tts.sh."
        case .scriptNotFound(let path):
            return "Скрипт Silero не найден: \(path). Убедитесь, что запуск идёт через scripts/run.sh."
        case .outputNotFound:
            return "Silero не сгенерировал аудиофайл. Проверьте вывод setup_silero_tts.sh."
        case .playbackFailed:
            return "Не удалось воспроизвести Silero аудио."
        case .failed(let msg):
            return "Silero TTS ошибка: \(msg)"
        }
    }
}
