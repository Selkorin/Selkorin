import AVFoundation
import Foundation

@MainActor
final class OpenAITTSService: SpeechServiceProvider {
    private let apiKey: String
    private let model = "gpt-4o-mini-tts"
    private var player: AVAudioPlayer?

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func speak(_ text: String, voice: String) async throws {
        guard !text.isEmpty else { return }
        stop()

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "voice": voice,
            "input": text,
            "instructions": "Говори естественно, тепло и спокойно на русском языке.",
            "response_format": "mp3",
        ])

        let data = try await AIHTTP.data(for: request)
        let player = try AVAudioPlayer(data: data)
        self.player = player
        player.prepareToPlay()
        guard player.play() else {
            throw AIClientError.invalidResponse
        }

        while player.isPlaying {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        self.player = nil
    }

    func stop() {
        player?.stop()
        player = nil
    }
}

