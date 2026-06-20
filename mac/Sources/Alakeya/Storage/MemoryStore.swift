import Foundation

struct MemoryEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var key: String
    var value: String
    var updatedAt: Date

    init(key: String, value: String) {
        id = UUID()
        self.key = key
        self.value = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        updatedAt = .now
    }
}

// Write methods must be called from MainActor (ToolRunner, SwiftUI views).
// composeContext() is safe to call from any context.
final class MemoryStore: ObservableObject {
    static let shared = MemoryStore()

    @Published private(set) var entries: [MemoryEntry] = []

    private let fileURL: URL
    private let ioQueue = DispatchQueue(label: "com.selkorin.alakeya.memory")

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Alakeya", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("memory.json")
        entries = Self.load(from: fileURL)
    }

    // ── Read ──────────────────────────────────────────────
    func composeContext() -> String {
        guard !entries.isEmpty else { return "" }
        let lines = entries.map { "- \($0.key): \(String($0.value.prefix(200)))" }
        return "## Что я знаю о пользователе\n" + lines.joined(separator: "\n")
    }

    // ── Write ─────────────────────────────────────────────
    func upsert(key: String, value: String) {
        let v = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !v.isEmpty else { return }
        if let idx = entries.firstIndex(where: { $0.key.lowercased() == key.lowercased() }) {
            entries[idx].value = v
            entries[idx].updatedAt = .now
        } else {
            guard entries.count < 50 else { return }
            entries.append(MemoryEntry(key: key, value: v))
        }
        flush()
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        flush()
    }

    func deleteAll() {
        entries = []
        flush()
    }

    // ── Persistence ───────────────────────────────────────
    private func flush() {
        let snapshot = entries
        let target = fileURL
        ioQueue.async {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            let data = try? enc.encode(snapshot)
            try? data?.write(to: target)
        }
    }

    private static func load(from url: URL) -> [MemoryEntry] {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let arr = try? dec.decode([MemoryEntry].self, from: data)
        else { return [] }
        return arr
    }
}
