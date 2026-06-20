import SwiftUI

// ============================================================
// MessageTableView.swift — unified styled table for chat.
// AlakeyaTableStyle v1: dark glass, bold headers, alternating
// rows, link-stripped cells, horizontal scroll.
// ============================================================

struct MessageTableView: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            tableContent
                .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(Color(hex: 0x0C0C18))
                .overlay(
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(Color.white.opacity(0.09), lineWidth: 1)
                )
        )
        .padding(.vertical, 6)
    }

    private var tableContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header row ──────────────────────────────────
            HStack(spacing: 0) {
                ForEach(Array(headers.enumerated()), id: \.offset) { idx, header in
                    headerCell(text: header, colIdx: idx)
                }
            }
            .frame(minHeight: 42)
            .background(Color.white.opacity(0.055))

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)

            // ── Data rows ───────────────────────────────────
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                HStack(spacing: 0) {
                    ForEach(0..<max(headers.count, 1), id: \.self) { colIdx in
                        let raw = colIdx < row.count ? row[colIdx] : ""
                        dataCell(text: raw, colIdx: colIdx, isEven: rowIdx % 2 == 0)
                    }
                }
                .frame(minHeight: 42)

                if rowIdx < rows.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.05))
                        .frame(height: 1)
                }
            }
        }
    }

    // MARK: - Cells

    private func headerCell(text: String, colIdx: Int) -> some View {
        let clean = MarkdownLinkExtractor.displayText(from: text)
        return Text(clean.isEmpty ? text : clean)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(WAI.text)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .frame(width: columnWidth(for: colIdx), alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .overlay(alignment: .trailing) {
                if colIdx < headers.count - 1 {
                    Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1)
                }
            }
    }

    private func dataCell(text: String, colIdx: Int, isEven: Bool) -> some View {
        TableCellView(raw: text, colWidth: columnWidth(for: colIdx))
            .background(isEven ? Color.clear : Color.white.opacity(0.022))
            .overlay(alignment: .trailing) {
                if colIdx < headers.count - 1 {
                    Rectangle().fill(Color.white.opacity(0.055)).frame(width: 1)
                }
            }
    }

    // MARK: - Column widths

    private func columnWidth(for idx: Int) -> CGFloat {
        let minW: CGFloat  = 90
        let maxW: CGFloat  = 240
        let charW: CGFloat = 8.5

        let headerLen = idx < headers.count
            ? MarkdownLinkExtractor.displayText(from: headers[idx]).count
            : 0
        let maxDataLen = rows.compactMap { row -> Int? in
            guard idx < row.count else { return nil }
            return MarkdownLinkExtractor.displayText(from: row[idx]).count
        }.max() ?? 0

        let maxLen = max(headerLen, maxDataLen)
        return min(maxW, max(minW, CGFloat(maxLen) * charW + 24))
    }
}

// ── Per-cell inline renderer with link extraction ──────────

private struct TableCellView: View {
    let raw: String
    let colWidth: CGFloat

    var body: some View {
        let links = MarkdownLinkExtractor.extractLinks(from: raw)
        let displayText = MarkdownLinkExtractor.displayText(from: raw)

        return Group {
            if links.isEmpty {
                // Plain text or bold
                InlineTextView(text: raw)
                    .frame(width: colWidth, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
            } else if links.count == 1 {
                // Single link — show label as accent tappable text
                Button {
                    AlakeyaBrowser.shared.open(links[0].url.absoluteString)
                } label: {
                    Text(displayText.isEmpty ? links[0].label : displayText)
                        .font(.system(size: 14))
                        .foregroundColor(WAI.accentBright)
                        .underline(true, color: WAI.accentBright.opacity(0.5))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(width: colWidth, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
            } else {
                // Multiple links — chips
                VStack(alignment: .leading, spacing: 3) {
                    if !displayText.isEmpty && displayText != links.map(\.label).joined() {
                        Text(displayText)
                            .font(.system(size: 14))
                            .foregroundColor(WAI.textDim)
                            .lineLimit(2)
                    }
                    HStack(spacing: 4) {
                        ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                            Button {
                                AlakeyaBrowser.shared.open(link.url.absoluteString)
                            } label: {
                                Text(link.label)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(WAI.accentBright)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(WAI.accentBright.opacity(0.12))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(width: colWidth, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
        }
    }
}

// Inline markdown: bold (**) support only, no links (they're already extracted)
private struct InlineTextView: View {
    let text: String
    var body: some View {
        Text(attributed)
            .font(.system(size: 14))
            .foregroundColor(WAI.textDim)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        var s = text[text.startIndex...]
        while !s.isEmpty {
            if s.hasPrefix("**"), let end = s.dropFirst(2).range(of: "**") {
                let bold = String(s.dropFirst(2)[..<end.lowerBound])
                var a = AttributedString(bold)
                a.font = .system(size: 14, weight: .semibold)
                a.foregroundColor = WAI.text
                result.append(a)
                s = s.dropFirst(2)[end.upperBound...]
                continue
            }
            var j = s.startIndex
            while j < s.endIndex && !s[j...].hasPrefix("**") { j = s.index(after: j) }
            let chunk = String(s[..<j])
            if !chunk.isEmpty {
                var a = AttributedString(chunk)
                a.font = .system(size: 14)
                a.foregroundColor = WAI.textDim
                result.append(a)
            }
            s = s[j...]
            if s.hasPrefix("**") && s.dropFirst(2).range(of: "**") == nil {
                // unclosed bold — treat as plain
                var a = AttributedString(String(s))
                a.font = .system(size: 14)
                a.foregroundColor = WAI.textDim
                result.append(a)
                break
            }
        }
        return result
    }
}
