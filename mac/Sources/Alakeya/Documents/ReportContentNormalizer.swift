import Foundation

// ============================================================
// ReportContentNormalizer.swift — cleans raw markdown content
// before export to PDF/DOCX/RTF. Removes table separators,
// normalizes headings, strips trailing junk.
// ============================================================

enum ReportContentNormalizer {

    static func normalize(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")

        // Remove separator rows (|---|---|) left after table parsing
        lines = lines.filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return !isSeparatorOnly(t)
        }

        // Remove raw table row lines (| col | col |) — tables are exported separately
        lines = lines.filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return !isTableRow(t)
        }

        // Strip duplicate "Источники" headings (sources section added separately)
        var seenSources = false
        lines = lines.filter { line in
            let t = line.trimmingCharacters(in: .whitespaces).lowercased()
            if t == "## источники" || t == "# источники" || t == "источники:" {
                if seenSources { return false }
                seenSources = true
            }
            return true
        }

        // Collapse 3+ consecutive blank lines to 1
        var collapsed: [String] = []
        var blankCount = 0
        for line in lines {
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank { blankCount += 1 } else { blankCount = 0 }
            if blankCount <= 2 { collapsed.append(line) }
        }

        // Trim leading/trailing blank lines
        while collapsed.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            collapsed.removeFirst()
        }
        while collapsed.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            collapsed.removeLast()
        }

        return collapsed.joined(separator: "\n")
    }

    /// Convert markdown links to plain text for CSV/plain-text export
    static func stripLinks(_ text: String) -> String {
        var result = text
        if let re = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\([^)]+\)"#) {
            result = re.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result),
                withTemplate: "$1")
        }
        return result
    }

    private static func isSeparatorOnly(_ t: String) -> Bool {
        guard t.contains("|") else { return false }
        return t.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " || $0 == "\t" }
    }

    private static func isTableRow(_ t: String) -> Bool {
        let hasPipe = t.hasPrefix("|") || t.contains(" | ")
        let pipes = t.filter { $0 == "|" }.count
        return hasPipe && pipes >= 2 && !isSeparatorOnly(t)
    }
}
