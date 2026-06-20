import Foundation

// ============================================================
// MarkdownLinkExtractor.swift
// Strips markdown links from table cell text so cells show
// only the visible label; URLs go to sources.
// ============================================================

struct ExtractedLink: Equatable {
    let label: String
    let url: URL
}

enum MarkdownLinkExtractor {

    /// Returns the display text for a cell (labels only, no URLs or markdown syntax).
    static func displayText(from raw: String) -> String {
        var result = raw
        // [Label](URL) → Label
        result = result.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^\)]+\)"#,
            with: "$1",
            options: .regularExpression
        )
        // Bare https?://... → domain (iterate in reverse so index arithmetic stays valid)
        let bareRE = try! NSRegularExpression(pattern: #"https?://[^\s\)\]>]+"#)
        let nsResult = result as NSString
        var output = result
        var offsetDelta = 0
        for m in bareRE.matches(in: result, range: NSRange(result.startIndex..., in: result)) {
            if let r = Range(m.range, in: result) {
                let urlStr = String(result[r])
                let domain = URL(string: urlStr)?.host?.replacingOccurrences(of: "www.", with: "") ?? ""
                let adjLoc = m.range.location + offsetDelta
                let adjRange = NSRange(location: adjLoc, length: m.range.length)
                output = (output as NSString).replacingCharacters(in: adjRange, with: domain)
                offsetDelta += domain.count - nsResult.substring(with: m.range).count
            }
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extracts all links from the cell text (label + URL pairs).
    static func extractLinks(from raw: String) -> [ExtractedLink] {
        var links: [ExtractedLink] = []

        // [Label](URL)
        let mdPattern = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^\)]+)\)"#)
        let range = NSRange(raw.startIndex..., in: raw)
        for m in mdPattern.matches(in: raw, range: range) {
            if let lr = Range(m.range(at: 1), in: raw),
               let ur = Range(m.range(at: 2), in: raw),
               let url = URL(string: String(raw[ur])) {
                links.append(ExtractedLink(label: String(raw[lr]), url: url))
            }
        }

        // Bare URLs (not already inside [...](...))
        let barePattern = try! NSRegularExpression(pattern: #"(?<!\]\()https?://[^\s\)\]>]+"#)
        for m in barePattern.matches(in: raw, range: range) {
            if let r = Range(m.range, in: raw),
               let url = URL(string: String(raw[r])) {
                let domain = url.host?.replacingOccurrences(of: "www.", with: "") ?? String(raw[r])
                links.append(ExtractedLink(label: domain, url: url))
            }
        }

        return links
    }

    /// True if the cell contains only a single link and no other meaningful text.
    static func isSingleLink(_ raw: String) -> Bool {
        let links = extractLinks(from: raw)
        guard links.count == 1 else { return false }
        let stripped = displayText(from: raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped == links[0].label
    }
}

