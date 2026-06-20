import SwiftUI

// ============================================================
// MarkdownRenderer.swift
// Custom block + inline markdown renderer.
//
// Blocks: # H1-H3  **bold**  *italic*  `code`  ```fences```
//         > blockquote  - / * / 1. lists  ---  [Title](URL)
//
// Typography:
//   Base:       15.5pt  lineSpacing 5
//   Code:       13pt monospaced
//   Heading 1:  22pt   Heading 2: 18pt   Heading 3: 15.5pt bold
//   List gap:   7pt between items
//   Para gap:   10pt between paragraphs
// ============================================================

private let kBaseSize: CGFloat = 15.5
private let kCodeSize: CGFloat = 13
private let kLineSpacing: CGFloat = 5

// ── Block AST ─────────────────────────────────────────────────

private enum MDBlock {
    case heading(Int, String)
    case paragraph(String)
    case blockquote(String)
    case codeBlock(lang: String?, code: String)
    case unorderedList([String])
    case orderedList([String])
    case divider
    case table([String], [[String]])   // headers, rows
}

// ── Block parser ──────────────────────────────────────────────

private enum MDParser {
    static func parse(_ source: String) -> [MDBlock] {
        var out: [MDBlock] = []
        let lines = source.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trim = line.trimmingCharacters(in: .whitespaces)

            // Code fence
            if line.hasPrefix("```") {
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                if i < lines.count { i += 1 }
                out.append(.codeBlock(lang: lang.isEmpty ? nil : lang,
                                      code: code.joined(separator: "\n")))
                continue
            }

            // Horizontal rule
            if trim.count >= 3,
               trim.allSatisfy({ $0 == "-" }) ||
               trim.allSatisfy({ $0 == "*" }) ||
               trim.allSatisfy({ $0 == "_" }) {
                out.append(.divider); i += 1; continue
            }

            // Headings
            if line.hasPrefix("### ") { out.append(.heading(3, String(line.dropFirst(4)))); i += 1; continue }
            if line.hasPrefix("## ")  { out.append(.heading(2, String(line.dropFirst(3)))); i += 1; continue }
            if line.hasPrefix("# ")   { out.append(.heading(1, String(line.dropFirst(2)))); i += 1; continue }

            // Blockquote
            if line.hasPrefix("> ") || line == ">" {
                var ql: [String] = []
                while i < lines.count && (lines[i].hasPrefix("> ") || lines[i] == ">") {
                    ql.append(lines[i].hasPrefix("> ") ? String(lines[i].dropFirst(2)) : "")
                    i += 1
                }
                out.append(.blockquote(ql.joined(separator: "\n")))
                continue
            }

            // Unordered list
            if isUL(line) {
                var items: [String] = []
                while i < lines.count && isUL(lines[i]) {
                    let item = String(lines[i].dropFirst(lines[i].hasPrefix("• ") ? 2 : 2))
                    items.append(item); i += 1
                }
                out.append(.unorderedList(items))
                continue
            }

            // Ordered list
            if isOL(line) {
                var items: [String] = []
                while i < lines.count && isOL(lines[i]) {
                    if let r = lines[i].range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                        items.append(String(lines[i][r.upperBound...]))
                    }
                    i += 1
                }
                out.append(.orderedList(items))
                continue
            }

            // Markdown table: | col | col | ...
            if isTableRow(trim) {
                var headers: [String] = []
                var rows: [[String]] = []
                headers = parseTableCells(trim)
                i += 1
                // Skip separator row
                if i < lines.count && isTableSeparator(lines[i].trimmingCharacters(in: .whitespaces)) {
                    i += 1
                }
                while i < lines.count {
                    let tl = lines[i].trimmingCharacters(in: .whitespaces)
                    if !isTableRow(tl) { break }
                    rows.append(parseTableCells(tl))
                    i += 1
                }
                if !headers.isEmpty && !rows.isEmpty {
                    out.append(.table(headers, rows))
                }
                continue
            }

            // Empty line
            if trim.isEmpty { i += 1; continue }

            // Paragraph
            var para: [String] = []
            while i < lines.count {
                let l = lines[i]; let t = l.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { break }
                if l.hasPrefix("```") || l.hasPrefix("> ") || l == ">" { break }
                if l.hasPrefix("# ") || l.hasPrefix("## ") || l.hasPrefix("### ") { break }
                if t.count >= 3 && (t.allSatisfy { $0 == "-" } ||
                                    t.allSatisfy { $0 == "*" } ||
                                    t.allSatisfy { $0 == "_" }) { break }
                if isUL(l) || isOL(l) { break }
                para.append(l); i += 1
            }
            if !para.isEmpty { out.append(.paragraph(para.joined(separator: "\n"))) }
        }
        return out
    }

    private static func isUL(_ l: String) -> Bool {
        l.hasPrefix("- ") || l.hasPrefix("• ") || l.hasPrefix("* ")
    }
    private static func isOL(_ l: String) -> Bool {
        l.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
    }

    private static func isTableRow(_ t: String) -> Bool {
        let pipes = t.filter { $0 == "|" }.count
        return (t.hasPrefix("|") || t.contains(" | ")) && pipes >= 2 && !isTableSeparator(t)
    }

    private static func isTableSeparator(_ t: String) -> Bool {
        t.contains("|") && t.contains("-") &&
        t.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " || $0 == "\t" }
    }

    private static func parseTableCells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t = String(t.dropFirst()) }
        if t.hasSuffix("|") { t = String(t.dropLast()) }
        return t.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
    }
}

// ── Inline token ──────────────────────────────────────────────

private enum InlineToken {
    case plain(String)
    case bold(String)
    case italic(String)
    case boldItalic(String)
    case code(String)
    case link(title: String, url: String)
}

// ── Inline parser + AttributedString builder ──────────────────

private enum MDInline {

    // MARK: - Public entry

    static func render(_ raw: String, size: CGFloat = kBaseSize) -> Text {
        Text(buildAttributed(raw, size: size))
    }

    // MARK: - AttributedString builder

    static func buildAttributed(_ raw: String, size: CGFloat) -> AttributedString {
        let tokens = parse(raw)
        var result = AttributedString()
        for token in tokens {
            result.append(attributed(token, size: size))
        }
        return result
    }

    private static func attributed(_ token: InlineToken, size: CGFloat) -> AttributedString {
        switch token {
        case .plain(let t):
            var a = AttributedString(t)
            a.font = .system(size: size)
            a.foregroundColor = WAI.text
            return a

        case .bold(let t):
            var a = AttributedString(t)
            a.font = .system(size: size, weight: .semibold)
            a.foregroundColor = WAI.text
            return a

        case .italic(let t):
            var a = AttributedString(t)
            a.font = Font.system(size: size).italic()
            a.foregroundColor = WAI.text
            return a

        case .boldItalic(let t):
            var a = AttributedString(t)
            a.font = Font.system(size: size, weight: .semibold).italic()
            a.foregroundColor = WAI.text
            return a

        case .code(let t):
            var a = AttributedString(t)
            a.font = .system(size: max(12, size - 2.5), design: .monospaced)
            a.foregroundColor = WAI.accentBright
            a.backgroundColor = Color(hex: 0x1A1A2E)
            return a

        case .link(let title, let url):
            var a = AttributedString(title.isEmpty ? url : title)
            a.font = .system(size: size)
            a.foregroundColor = WAI.accentBright
            a.underlineStyle = .single
            if let u = URL(string: url) {
                a.link = u
            }
            return a
        }
    }

    // MARK: - Inline tokenizer

    private static func parse(_ text: String) -> [InlineToken] {
        var tokens: [InlineToken] = []
        var s = text[text.startIndex...]

        while !s.isEmpty {
            // Markdown link: [Title](URL)
            // Scan for the delimiter "]( " to handle nested brackets correctly.
            if s.hasPrefix("[") {
                let inner = s.dropFirst()
                if let delimRange = inner.range(of: "](") {
                    let title = String(inner[..<delimRange.lowerBound])
                    let afterParen = inner.index(after: delimRange.upperBound)
                    let rest = inner[afterParen...]
                    if let closeUrl = rest.firstIndex(of: ")") {
                        let url = String(rest[..<closeUrl])
                        tokens.append(.link(title: title, url: url))
                        s = rest[rest.index(after: closeUrl)...]
                        continue
                    }
                }
            }

            // Bare URL: https://... or http://...
            if s.hasPrefix("https://") || s.hasPrefix("http://") {
                var j = s.startIndex
                while j < s.endIndex && !s[j].isWhitespace && s[j] != ")" && s[j] != ">" {
                    j = s.index(after: j)
                }
                let url = String(s[..<j])
                let domain = URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? url
                tokens.append(.link(title: domain, url: url))
                s = s[j...]; continue
            }

            // Inline code: `...`
            if s.hasPrefix("`") {
                let rest = s.dropFirst()
                if let end = rest.firstIndex(of: "`") {
                    tokens.append(.code(String(rest[..<end])))
                    s = rest[rest.index(after: end)...]; continue
                }
            }

            // Bold-italic: ***...***
            if s.hasPrefix("***") {
                let inner = s.dropFirst(3)
                if let end = inner.range(of: "***") {
                    tokens.append(.boldItalic(String(inner[..<end.lowerBound])))
                    s = inner[end.upperBound...]; continue
                }
            }

            // Bold: **...**
            if s.hasPrefix("**") {
                let inner = s.dropFirst(2)
                if let end = inner.range(of: "**") {
                    tokens.append(.bold(String(inner[..<end.lowerBound])))
                    s = inner[end.upperBound...]; continue
                }
            }

            // Italic: *...*  (not **)
            if s.hasPrefix("*"), !s.hasPrefix("**") {
                let rest = s.dropFirst()
                if let end = rest.firstIndex(of: "*") {
                    tokens.append(.italic(String(rest[..<end])))
                    s = rest[rest.index(after: end)...]; continue
                }
            }

            // Plain text: scan to next marker
            var j = s.startIndex
            while j < s.endIndex {
                let c = s[j]
                if c == "`" || c == "*" || c == "[" { break }
                if s[j...].hasPrefix("https://") || s[j...].hasPrefix("http://") { break }
                j = s.index(after: j)
            }
            if j > s.startIndex {
                tokens.append(.plain(String(s[..<j])))
                s = s[j...]
            } else {
                tokens.append(.plain(String(s.first!)))
                s = s.dropFirst()
            }
        }
        return tokens
    }
}

// ── Renderer view ─────────────────────────────────────────────

struct MarkdownRenderer: View {
    let source: String
    /// openURL callback — called when user taps a link in the rendered text.
    var onOpenURL: ((URL) -> Void)? = nil

    private var normalizedSource: String {
        MessageLinkNormalizer.normalize(source)
    }
    private var blocks: [MDBlock] {
        MDParser.parse(normalizedSource)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                render(block)
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            if let handler = onOpenURL {
                handler(url)
                return .handled
            }
            // Default: open in AlakeyaBrowser
            AlakeyaBrowser.shared.open(url.absoluteString)
            return .handled
        })
    }

    // MARK: - Block renderer

    @ViewBuilder
    private func render(_ block: MDBlock) -> some View {
        switch block {

        case .heading(let lvl, let text):
            MDInline.render(text, size: headingPt(lvl))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(kLineSpacing)
                .padding(.top,    lvl == 1 ? 14 : lvl == 2 ? 10 : 8)
                .padding(.bottom, lvl == 1 ? 6  : 4)

        case .paragraph(let text):
            MDInline.render(text)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(kLineSpacing)
                .padding(.vertical, 5)

        case .blockquote(let text):
            quoteView(text)

        case .codeBlock(let lang, let code):
            codeView(lang: lang, code: code)
                .padding(.vertical, 8)

        case .unorderedList(let items):
            listView(items, ordered: false)
                .padding(.vertical, 4)

        case .orderedList(let items):
            listView(items, ordered: true)
                .padding(.vertical, 4)

        case .divider:
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)
                .padding(.vertical, 14)

        case .table(let headers, let rows):
            MessageTableView(headers: headers, rows: rows)
        }
    }

    private func headingPt(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 22
        case 2: return 19
        default: return 16.5
        }
    }

    // MARK: - Blockquote

    private func quoteView(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(WAI.accentBright)
                .frame(width: 3)
                .padding(.top, 2)
            MDInline.render(text)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(kLineSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Code block

    private func codeView(lang: String?, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let lang, !lang.isEmpty {
                HStack {
                    Text(lang)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(WAI.textDim)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9))
                            Text("Копировать")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(WAI.textDim)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: kCodeSize, design: .monospaced))
                    .foregroundStyle(WAI.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.top,    lang == nil ? 12 : 4)
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: 0x111119))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1))
        )
    }

    // MARK: - List

    private func listView(_ items: [String], ordered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if ordered {
                        Text("\(idx + 1).")
                            .font(.system(size: kBaseSize, weight: .regular))
                            .foregroundStyle(WAI.textMuted)
                            .frame(minWidth: 22, alignment: .trailing)
                            .monospacedDigit()
                    } else {
                        Text("•")
                            .font(.system(size: kBaseSize))
                            .foregroundStyle(WAI.textMuted)
                            .frame(minWidth: 14, alignment: .center)
                    }
                    MDInline.render(item)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(kLineSpacing)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
