import Foundation

enum DocumentFormat: String, Codable, CaseIterable {
    case pdf   = "pdf"
    case docx  = "docx"
    case csv   = "csv"
    case markdown = "md"
    case rtf   = "rtf"

    var fileExtension: String { rawValue }
    var mimeType: String {
        switch self {
        case .pdf:      return "application/pdf"
        case .docx:     return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case .csv:      return "text/csv"
        case .markdown: return "text/markdown"
        case .rtf:      return "application/rtf"
        }
    }
    var displayName: String {
        switch self {
        case .pdf:      return "PDF"
        case .docx:     return "Word (DOCX)"
        case .csv:      return "CSV"
        case .markdown: return "Markdown"
        case .rtf:      return "RTF"
        }
    }
}
