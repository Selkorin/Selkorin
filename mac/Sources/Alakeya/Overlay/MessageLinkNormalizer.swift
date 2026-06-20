import Foundation

// ============================================================
// MessageLinkNormalizer.swift
// Pre-processes markdown text before rendering to fix malformed links.
//
// Fixes:
//   Title(https://url) → [Title](https://url)
//   bare https://url   → [domain](https://url)
//
// Does NOT touch:
//   [Title](url)         — already correct
//   code blocks          — skipped entirely
//   very long URLs in body — left as domain label only
// ============================================================

enum MessageLinkNormalizer {

    /// Normalize all link patterns in raw assistant text.
    static func normalize(_ text: String) -> String {
        var out = ""
        // Process line by line; skip code fences wholesale.
        var inCode = false
        let lines = text.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            if line.hasPrefix("```") { inCode.toggle() }
            if inCode {
                out += line
            } else {
                out += fixLine(line)
            }
            if i < lines.count - 1 { out += "\n" }
        }
        return out
    }

    // MARK: - Per-line fixes

    private static func fixLine(_ line: String) -> String {
        var s = fixMalformedLinks(line)   // Title(url) → [Title](url)
        s = fixBareURLs(s)                // https://url → [domain](url)
        return s
    }

    // MARK: - Fix Title(URL) → [Title](URL)

    private static func fixMalformedLinks(_ s: String) -> String {
        // Match: non-bracket text (1-80 chars) immediately followed by (https://...)
        // Negative lookbehind for `[` so we don't double-wrap existing links.
        let pattern = #"(?<!\[)([^\[\](`\n]{1,80}?)\((https?://[^\s)]{5,})\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        let range = NSRange(location: 0, length: ns.length)
        var result = s
        // Process right-to-left to preserve string indices.
        let matches = regex.matches(in: s, range: range).reversed()
        for m in matches {
            guard m.numberOfRanges == 3,
                  let r0 = Range(m.range, in: s),
                  let r1 = Range(m.range(at: 1), in: s),
                  let r2 = Range(m.range(at: 2), in: s) else { continue }
            let title = String(s[r1]).trimmingCharacters(in: .whitespaces)
            let url   = String(s[r2])
            // Skip if title looks like code (contains backticks or is empty)
            if title.contains("`") || title.isEmpty { continue }
            let replacement = "[\(title)](\(url))"
            result.replaceSubrange(r0, with: replacement)
        }
        return result
    }

    // MARK: - Fix bare URLs → [domain](URL)

    private static func fixBareURLs(_ s: String) -> String {
        // Only match bare URLs not already inside [...](...)
        // Negative lookbehind for `](`  and negative lookahead for `)` to avoid double-wrapping
        let pattern = #"(?<!\()(?<!\]\()https?://([^\s)\]>'"]{5,})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let range = NSRange(s.startIndex..., in: s)
        var result = s
        let matches = regex.matches(in: s, range: range).reversed()
        for m in matches {
            guard m.numberOfRanges == 2,
                  let r0 = Range(m.range, in: s),
                  let r1 = Range(m.range(at: 1), in: s) else { continue }
            let fullURL = String(s[r0])
            let path    = String(s[r1])
            // Extract domain for display label
            let domain  = path.components(separatedBy: "/").first ?? path
            // Don't shrink already-short URLs
            let label   = domain.count < fullURL.count ? domain : fullURL
            result.replaceSubrange(r0, with: "[\(label)](\(fullURL))")
        }
        return result
    }
}
