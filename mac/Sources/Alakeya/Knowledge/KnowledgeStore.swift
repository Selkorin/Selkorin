import Foundation

struct KnowledgeDoc: Identifiable {
    let id: String       // filename without .md
    let title: String    // from first # heading, or filename
    let content: String  // full text
    let charCount: Int   // original length before any truncation
}

final class KnowledgeStore: ObservableObject {
    static let shared = KnowledgeStore()

    @Published private(set) var docs: [KnowledgeDoc] = []

    private let knowledgeDir: URL

    static let perDocLimit = 4_000
    static let totalLimit  = 8_000

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Alakeya", isDirectory: true)
        knowledgeDir = base.appendingPathComponent("Knowledge", isDirectory: true)
        try? FileManager.default.createDirectory(at: knowledgeDir, withIntermediateDirectories: true)
        docs = loadDocs()
    }

    // ── Compose context for system prompt ─────────────────

    func composeContext() -> String {
        guard !docs.isEmpty else { return "" }
        var sections: [String] = []
        var total = 0

        for doc in docs {
            var body = doc.content
            if body.count > Self.perDocLimit {
                body = String(body.prefix(Self.perDocLimit)) + "...[усечено]"
            }
            let section = "### \(doc.title)\n\(body)"
            if total + section.count > Self.totalLimit { break }
            sections.append(section)
            total += section.count
        }

        guard !sections.isEmpty else { return "" }
        return "## База знаний\n\n" + sections.joined(separator: "\n\n")
    }

    // ── Mutations ─────────────────────────────────────────

    func addFiles(urls: [URL]) {
        let fm = FileManager.default
        for src in urls {
            let dest = knowledgeDir.appendingPathComponent(src.lastPathComponent)
            if fm.fileExists(atPath: dest.path) {
                try? fm.removeItem(at: dest)
            }
            try? fm.copyItem(at: src, to: dest)
        }
        docs = loadDocs()
    }

    func delete(doc: KnowledgeDoc) {
        let fileURL = knowledgeDir.appendingPathComponent("\(doc.id).md")
        try? FileManager.default.removeItem(at: fileURL)
        docs = loadDocs()
    }

    func reload() {
        docs = loadDocs()
    }

    // ── Loading ───────────────────────────────────────────

    private func loadDocs() -> [KnowledgeDoc] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: knowledgeDir, includingPropertiesForKeys: nil
        ) else { return [] }

        return urls
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let content = try? String(contentsOf: url, encoding: .utf8),
                      !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { return nil }
                let id = url.deletingPathExtension().lastPathComponent
                let title = parseTitle(from: content) ?? id
                return KnowledgeDoc(id: id, title: title, content: content, charCount: content.count)
            }
    }

    private func parseTitle(from content: String) -> String? {
        for line in content.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("# ") {
                let title = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                return title.isEmpty ? nil : title
            }
        }
        return nil
    }
}
