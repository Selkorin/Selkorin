import Foundation

// ============================================================
// Store.swift — lightweight persistence for remembered permission
// rules, the action journal and user settings. JSON under
// ~/Library/Application Support/Alakeya (app-managed, user-editable —
// DOC2 §"Long-term memory должна быть приложенческой").
// ============================================================

struct ActivityEntry: Codable, Identifiable {
    let id: String
    let time: Date
    let kind: String
    let title: String
    let subtitle: String
    let status: String   // ok | blocked | awaiting | denied
}

final class Store {
    static let shared = Store()

    private let dir: URL
    private let queue = DispatchQueue(label: "com.selkorin.alakeya.store")
    private var pendingActivitySave: DispatchWorkItem?
    private var pendingSessionsSave: DispatchWorkItem?

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Alakeya", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        dir = base
    }

    private func url(_ name: String) -> URL { dir.appendingPathComponent(name) }

    // ── Remembered rules (action signatures) ──────────────
    func loadRules() -> Set<String> {
        guard let data = try? Data(contentsOf: url("rules.json")),
              let arr = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(arr)
    }

    func saveRules(_ rules: Set<String>) {
        queue.async {
            let data = try? JSONEncoder().encode(Array(rules))
            try? data?.write(to: self.url("rules.json"))
        }
    }

    // ── Activity journal ──────────────────────────────────
    func loadActivity() -> [ActivityEntry] {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url("activity.json")),
              let rows = try? dec.decode([ActivityEntry].self, from: data)
        else { return [] }
        return rows
    }

    func saveActivity(_ rows: [ActivityEntry]) {
        // Debounce: cancel any prior pending write to avoid overwrite races.
        pendingActivitySave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let trimmed = Array(rows.suffix(500))
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            let data = try? enc.encode(trimmed)
            guard let data else { return }
            try? data.write(to: self.url("activity.json"))
        }
        pendingActivitySave = work
        queue.asyncAfter(deadline: .now() + .milliseconds(100), execute: work)
    }

    // ── Chat sessions ─────────────────────────────────────
    func loadSessions() -> [ChatSession] {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url("sessions.json")),
              let sessions = try? dec.decode([ChatSession].self, from: data)
        else { return [] }
        return sessions
    }

    func saveSessions(_ sessions: [ChatSession]) {
        // Debounce: cancel any prior pending write to avoid overwrite races.
        pendingSessionsSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Keep last 100 sessions, strip images to avoid bloat
            let trimmed = Array(sessions.suffix(100)).map { session -> ChatSession in
                var s = session
                s.messages = s.messages.map { $0.strippingImages() }
                return s
            }
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            let data = try? enc.encode(trimmed)
            guard let data else { return }
            try? data.write(to: self.url("sessions.json"))
        }
        pendingSessionsSave = work
        queue.asyncAfter(deadline: .now() + .milliseconds(100), execute: work)
    }
}
