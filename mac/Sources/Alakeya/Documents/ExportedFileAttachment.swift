import Foundation

// ============================================================
// ExportedFileAttachment.swift — structured file attachment
// stored in ChatMessage after a successful document export.
// Replaces fragile text-parsing of "✅ Файл создан:" markers.
// ============================================================

struct ExportedFileAttachment: Identifiable, Codable, Equatable {
    let id: UUID
    let filename: String
    let filePath: String          // stored as String — URL isn't always Codable in arrays
    let format: String            // "pdf", "docx", "rtf", "csv", "md"
    let fileSize: Int64
    let createdAt: Date
    let sourceTool: String        // "export_pdf", etc.

    var fileURL: URL { URL(fileURLWithPath: filePath) }
    var exists: Bool { FileManager.default.fileExists(atPath: filePath) }

    var displaySize: String {
        if fileSize < 1024 { return "\(fileSize) B" }
        if fileSize < 1_048_576 { return "\(fileSize / 1024) KB" }
        return String(format: "%.1f MB", Double(fileSize) / 1_048_576)
    }

    var formatIcon: String {
        switch format {
        case "png", "jpg", "jpeg": return "🖼️"
        case "svg":                 return "◇"
        case "pdf":           return "📄"
        case "docx":          return "📝"
        case "rtf":           return "📝"
        case "csv", "xlsx":   return "📊"
        case "md", "markdown":return "📋"
        default:              return "📁"
        }
    }

    var shortPath: String {
        // Show relative: "Documents/Alakeya/Exports"
        let home = NSHomeDirectory()
        let rel = filePath.hasPrefix(home) ? String(filePath.dropFirst(home.count + 1)) : filePath
        return (rel as NSString).deletingLastPathComponent
    }

    init(id: UUID = UUID(), filename: String, filePath: String, format: String,
         fileSize: Int64, createdAt: Date = Date(), sourceTool: String = "") {
        self.id         = id
        self.filename   = filename
        self.filePath   = filePath
        self.format     = format
        self.fileSize   = fileSize
        self.createdAt  = createdAt
        self.sourceTool = sourceTool
    }

    init(from exportedFile: ExportedFile, sourceTool: String = "") {
        self.id         = UUID()
        self.filename   = exportedFile.path.lastPathComponent
        self.filePath   = exportedFile.path.path
        self.format     = exportedFile.format.rawValue
        self.fileSize   = exportedFile.sizeBytes
        self.createdAt  = Date()
        self.sourceTool = sourceTool
    }
}
