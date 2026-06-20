import Foundation

// ============================================================
// MarkdownTableParser.swift — finds and parses markdown tables
// from raw text. Handles lax formatting: extra spaces, empty
// cells, links in cells, long separators.
// ============================================================

struct ParsedMarkdownTable: Equatable, Codable {
    var headers: [String]
    var rows: [[String]]
    var caption: String?

    /// Renders a clean markdown table string with separator row — parseable by MarkdownTableParser.
    func toMarkdown() -> String {
        guard !headers.isEmpty else { return "" }
        let head = "| " + headers.joined(separator: " | ") + " |"
        let sep  = "| " + headers.map { _ in "---" }.joined(separator: " | ") + " |"
        let body = rows.map { row in
            let cells = (0..<headers.count).map { i -> String in
                i < row.count ? row[i].replacingOccurrences(of: "|", with: "｜") : ""
            }
            return "| " + cells.joined(separator: " | ") + " |"
        }.joined(separator: "\n")
        return [head, sep, body].joined(separator: "\n")
    }
}

enum MarkdownTableParser {

    // MARK: - Public

    /// Parse all markdown tables from text. Returns empty array if none found.
    static func parse(from text: String) -> [ParsedMarkdownTable] {
        let lines = text.components(separatedBy: "\n")
        var tables: [ParsedMarkdownTable] = []
        var i = 0
        while i < lines.count {
            if isTableRow(lines[i]) {
                if let (table, newI) = readTable(lines: lines, from: i) {
                    tables.append(table)
                    i = newI
                    continue
                }
            }
            i += 1
        }
        return tables
    }

    /// Remove markdown table syntax from text, leaving only non-table content.
    static func removeTables(from text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var i = 0
        while i < lines.count {
            if isTableRow(lines[i]) {
                // Skip all consecutive table-related lines
                while i < lines.count && (isTableRow(lines[i]) || isSeparatorRow(lines[i])) {
                    i += 1
                }
                continue
            }
            result.append(lines[i])
            i += 1
        }
        // Collapse consecutive blank lines to single blank
        var collapsed: [String] = []
        var lastBlank = false
        for line in result {
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank && lastBlank { continue }
            collapsed.append(line)
            lastBlank = isBlank
        }
        return collapsed.joined(separator: "\n")
    }

    // MARK: - Private

    private static func readTable(lines: [String], from start: Int) -> (ParsedMarkdownTable, Int)? {
        var i = start
        // First line should be header row
        let headerLine = lines[i]
        guard isTableRow(headerLine) else { return nil }
        let headers = parseCells(headerLine)
        guard !headers.isEmpty else { return nil }
        i += 1

        // Separator row (optional but typical)
        if i < lines.count && isSeparatorRow(lines[i]) {
            i += 1
        }

        // Data rows
        var rows: [[String]] = []
        while i < lines.count && isTableRow(lines[i]) {
            let cells = parseCells(lines[i])
            if !cells.isEmpty {
                // Pad/trim to match header count
                var row = cells
                while row.count < headers.count { row.append("") }
                rows.append(Array(row.prefix(headers.count)))
            }
            i += 1
        }

        guard !rows.isEmpty else { return nil }
        return (ParsedMarkdownTable(headers: headers, rows: rows), i)
    }

    private static func isTableRow(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("|") || t.contains(" | ") else { return false }
        // Must have at least one | inside (not just separator)
        let pipes = t.filter { $0 == "|" }.count
        return pipes >= 2 && !isSeparatorRow(t)
    }

    private static func isSeparatorRow(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        // Row is separator if it only contains |, -, :, and whitespace
        return t.contains("|") &&
               t.allSatisfy({ $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " || $0 == "\t" }) &&
               t.contains("-")
    }

    static func parseCells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t = String(t.dropFirst()) }
        if t.hasSuffix("|") { t = String(t.dropLast()) }
        return t.components(separatedBy: "|").map {
            stripMarkdown($0.trimmingCharacters(in: .whitespaces))
        }
    }

    // Strip link syntax from cell text for plain display
    static func stripMarkdown(_ text: String) -> String {
        var result = text
        // [Title](URL) → Title
        if let re = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\([^)]+\)"#) {
            result = re.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result),
                withTemplate: "$1")
        }
        // **bold** → bold
        result = result.replacingOccurrences(of: "**", with: "")
        // *italic* → italic
        if result.hasPrefix("*") && result.hasSuffix("*") {
            result = String(result.dropFirst().dropLast())
        }
        return result
    }
}
