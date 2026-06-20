import Foundation

// ============================================================
// SourceReference.swift — a source that backs an assistant reply.
// Sources are data, not text — they render as chips below the message.
// ============================================================

struct SourceReference: Identifiable, Codable {
    let id: UUID
    var title: String
    var url: String
    var domain: String
    var snippet: String?
    var sourceType: SourceType
    var toolName: String?
    var retrievedAt: Date

    enum SourceType: String, Codable {
        case web, browser, document, email, drive, sheet, academic, localFile
        var icon: String {
            switch self {
            case .web:       return "globe"
            case .browser:   return "safari"
            case .document:  return "doc.text"
            case .email:     return "envelope"
            case .drive:     return "externaldrive"
            case .sheet:     return "tablecells"
            case .academic:  return "graduationcap"
            case .localFile: return "folder"
            }
        }
    }

    init(title: String, url: String,
         snippet: String? = nil,
         sourceType: SourceType = .web,
         toolName: String? = nil) {
        self.id          = UUID()
        self.title       = title
        self.url         = url
        self.domain      = URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? url
        self.snippet     = snippet
        self.sourceType  = sourceType
        self.toolName    = toolName
        self.retrievedAt = Date()
    }
}

// MARK: - Extraction from markdown text

enum SourceExtractor {
    /// Extract [Title](URL) links from markdown text as SourceReferences.
    /// Only keeps unique domains. Max 8 sources.
    static func extractLinks(from text: String, toolName: String? = nil) -> [SourceReference] {
        var refs: [SourceReference] = []
        var seenDomains = Set<String>()

        // Skip code blocks before searching
        let stripped = stripCodeBlocks(text)

        // Pattern: [Title](URL)
        let pattern = #"\[([^\]]{1,120})\]\((https?://[^\s)]{5,})\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: stripped, range: NSRange(stripped.startIndex..., in: stripped))
        for m in matches {
            guard m.numberOfRanges == 3,
                  let titleRange = Range(m.range(at: 1), in: stripped),
                  let urlRange   = Range(m.range(at: 2), in: stripped) else { continue }
            let title = String(stripped[titleRange]).trimmingCharacters(in: .whitespaces)
            let url   = String(stripped[urlRange])
            let ref   = SourceReference(title: title, url: url, sourceType: .web, toolName: toolName)
            guard !seenDomains.contains(ref.domain) else { continue }
            seenDomains.insert(ref.domain)
            refs.append(ref)
            if refs.count >= 8 { break }
        }
        return refs
    }

    private static func stripCodeBlocks(_ text: String) -> String {
        // Replace fenced code blocks with empty strings to avoid matching links inside code
        guard let regex = try? NSRegularExpression(pattern: "```[\\s\\S]*?```") else { return text }
        let mutable = NSMutableString(string: text)
        let range = NSRange(text.startIndex..., in: text)
        regex.replaceMatches(in: mutable, range: range, withTemplate: "")
        return String(mutable)
    }
}
