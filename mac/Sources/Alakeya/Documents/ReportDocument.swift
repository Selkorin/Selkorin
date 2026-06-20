import Foundation

// ============================================================
// ReportDocument.swift — structured report model used by
// PDF/DOCX/CSV renderers. AI builds this from research results.
// ============================================================

struct ReportDocument: Codable {
    var title: String
    var subtitle: String
    var createdAt: Date
    var author: String
    var sections: [ReportSection]
    var sources: [SourceReference]

    init(title: String, subtitle: String = "",
         author: String = "Alakeya",
         sections: [ReportSection] = [],
         sources: [SourceReference] = []) {
        self.title     = title
        self.subtitle  = subtitle
        self.createdAt = Date()
        self.author    = author
        self.sections  = sections
        self.sources   = sources
    }

    // Parse from JSON string (produced by AI tool call)
    static func from(json: String) -> ReportDocument? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ReportDocument.self, from: data)
    }
}

struct ReportSection: Codable {
    var heading: String
    var body: String
    var bullets: [String]
    var table: ReportTable?

    init(heading: String = "", body: String = "",
         bullets: [String] = [], table: ReportTable? = nil) {
        self.heading = heading
        self.body    = body
        self.bullets = bullets
        self.table   = table
    }
}

struct ReportTable: Codable {
    var headers: [String]
    var rows: [[String]]
}

// ============================================================
// ExportedFile — result returned to the AI after generating a file.
// ============================================================

struct ExportedFile {
    let path: URL
    let format: DocumentFormat
    let sizeBytes: Int64
    var displaySize: String {
        sizeBytes < 1024 ? "\(sizeBytes) B"
            : sizeBytes < 1_048_576 ? "\(sizeBytes / 1024) KB"
            : String(format: "%.1f MB", Double(sizeBytes) / 1_048_576)
    }
    var summary: String {
        "✅ Файл создан: \(path.lastPathComponent) (\(displaySize))\nПуть: \(path.path)\nФормат: \(format.rawValue)"
    }
}
