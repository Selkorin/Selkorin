import Foundation

// Persists per-message rating to
// ~/Library/Application Support/Alakeya/message_feedback.json
// Keys: messageID (UUID string) → "good" | "bad"

final class FeedbackStore {
    static let shared = FeedbackStore()

    private let queue = DispatchQueue(label: "com.selkorin.alakeya.feedback")
    private var cache: [String: String] = [:]
    private let fileURL: URL

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Alakeya", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("message_feedback.json")
        if let data = try? Data(contentsOf: fileURL),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            cache = dict
        }
    }

    func rating(for id: UUID) -> String? { cache[id.uuidString] }

    func setRating(_ rating: String, for id: UUID) {
        cache[id.uuidString] = rating
        persist()
    }

    func clearRating(for id: UUID) {
        cache.removeValue(forKey: id.uuidString)
        persist()
    }

    private func persist() {
        let snapshot = cache
        queue.async { [weak self] in
            guard let self else { return }
            let data = try? JSONEncoder().encode(snapshot)
            try? data?.write(to: self.fileURL)
        }
    }
}
