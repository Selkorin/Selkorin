import Foundation
import AppKit

// ============================================================
// PDFReportRenderer.swift — renders ReportDocument to PDF
// using Core Graphics + NSAttributedString. No external deps.
// ============================================================

enum PDFReportRenderer {

    // A4 in points (72 pt = 1 inch)
    private static let pageWidth:  CGFloat = 595
    private static let pageHeight: CGFloat = 842
    private static let margin:     CGFloat = 56
    private static var contentWidth: CGFloat { pageWidth - margin * 2 }

    // MARK: - Public

    // Mixed draw items: attributed text OR native-drawn table
    private enum DrawItem {
        case text(NSAttributedString)
        case table(ReportTable)
    }

    static func render(_ doc: ReportDocument, to url: URL) throws {
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else {
            throw ExportError.renderFailed("Не удалось создать PDF consumer")
        }
        var pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &pageRect, nil) else {
            throw ExportError.renderFailed("Не удалось создать PDF context")
        }

        // Build mixed draw item list
        var items: [DrawItem] = []
        items.append(.text(titleBlock(doc.title)))
        if !doc.subtitle.isEmpty { items.append(.text(subtitleBlock(doc.subtitle))) }
        items.append(.text(dateBlock(doc.createdAt)))
        items.append(.text(spacerBlock(18)))

        for section in doc.sections {
            if !section.heading.isEmpty { items.append(.text(headingBlock(section.heading))) }
            if !section.body.isEmpty    { items.append(.text(bodyBlock(section.body))) }
            for bullet in section.bullets { items.append(.text(bulletBlock(bullet))) }
            if let table = section.table  { items.append(.table(table)) }
            items.append(.text(spacerBlock(10)))
        }

        if !doc.sources.isEmpty {
            items.append(.text(headingBlock("Источники")))
            for (i, src) in doc.sources.enumerated() {
                items.append(.text(sourceBlock(index: i + 1, source: src)))
            }
        }

        // Paginate and draw
        var yOffset: CGFloat = pageHeight - margin
        ctx.beginPDFPage(nil)

        for item in items {
            switch item {

            case .text(let attrStr):
                let size = attrStr.boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading]
                ).size
                let blockHeight = ceil(size.height) + 4
                if yOffset - blockHeight < margin + 20 {
                    ctx.endPDFPage(); ctx.beginPDFPage(nil)
                    yOffset = pageHeight - margin
                }
                let drawRect = CGRect(x: margin, y: yOffset - blockHeight,
                                      width: contentWidth, height: blockHeight)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                attrStr.draw(in: drawRect)
                NSGraphicsContext.restoreGraphicsState()
                yOffset -= blockHeight

            case .table(let table):
                yOffset = drawTable(table, ctx: ctx, yStart: yOffset,
                                    pageHeight: pageHeight, margin: margin,
                                    contentWidth: contentWidth)
            }
        }

        ctx.endPDFPage()
        ctx.closePDF()

        try pdfData.write(to: url, options: .atomic)
    }

    // MARK: - Block builders

    private static func titleBlock(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 22, weight: .bold),
            .foregroundColor: NSColor.black,
        ])
    }

    private static func subtitleBlock(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.darkGray,
        ])
    }

    private static func dateBlock(_ date: Date) -> NSAttributedString {
        let df = DateFormatter(); df.locale = Locale(identifier: "ru_RU")
        df.dateStyle = .long; df.timeStyle = .short
        return NSAttributedString(string: "Создан: \(df.string(from: date))\n", attributes: [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.gray,
        ])
    }

    private static func spacerBlock(_ height: CGFloat) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.minimumLineHeight = height
        para.maximumLineHeight = height
        return NSAttributedString(string: "\n", attributes: [
            .paragraphStyle: para,
            .font: NSFont.systemFont(ofSize: 4),
        ])
    }

    private static func headingBlock(_ text: String) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.paragraphSpacingBefore = 12
        return NSAttributedString(string: text + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.black,
            .paragraphStyle: para,
        ])
    }

    private static func bodyBlock(_ text: String) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        para.paragraphSpacing = 6
        return NSAttributedString(string: text + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor(white: 0.15, alpha: 1),
            .paragraphStyle: para,
        ])
    }

    private static func bulletBlock(_ text: String) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.firstLineHeadIndent = 0
        para.headIndent = 16
        para.lineSpacing = 2
        return NSAttributedString(string: "• \(text)\n", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor(white: 0.15, alpha: 1),
            .paragraphStyle: para,
        ])
    }

    // Returns the Y offset after drawing the table
    private static func drawTable(_ table: ReportTable, ctx: CGContext,
                                   yStart: CGFloat, pageHeight: CGFloat,
                                   margin: CGFloat, contentWidth: CGFloat) -> CGFloat {
        let colCount   = table.headers.count
        guard colCount > 0 else { return yStart }
        let colWidth   = contentWidth / CGFloat(colCount)
        let headerH: CGFloat = 22
        let rowH: CGFloat    = 20
        let textInset: CGFloat = 6

        func drawPageBreakIfNeeded(_ y: CGFloat, needed: CGFloat) -> (CGFloat, Bool) {
            if y - needed < margin + 20 {
                ctx.endPDFPage()
                ctx.beginPDFPage(nil)
                return (pageHeight - margin, true)
            }
            return (y, false)
        }

        var y = yStart

        // ── Header row ──
        let (y1, _) = drawPageBreakIfNeeded(y, needed: headerH + 4)
        y = y1

        // Background fill
        ctx.setFillColor(NSColor(white: 0.93, alpha: 1).cgColor)
        ctx.fill(CGRect(x: margin, y: y - headerH, width: contentWidth, height: headerH))

        for (ci, header) in table.headers.enumerated() {
            let cellRect = CGRect(x: margin + CGFloat(ci) * colWidth, y: y - headerH,
                                  width: colWidth, height: headerH)
            // Cell border
            ctx.setStrokeColor(NSColor(white: 0.7, alpha: 1).cgColor)
            ctx.setLineWidth(0.5)
            ctx.stroke(cellRect)
            // Text
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: NSColor.black,
            ]
            let textRect = cellRect.insetBy(dx: textInset, dy: 4)
            let cleanHeader = MarkdownTableParser.stripMarkdown(header)
            (cleanHeader as NSString).draw(in: textRect, withAttributes: attrs)
        }
        y -= headerH

        // ── Data rows ──
        for (ri, row) in table.rows.enumerated() {
            let (y2, _) = drawPageBreakIfNeeded(y, needed: rowH + 2)
            y = y2

            let bgColor: CGColor = ri % 2 == 0
                ? NSColor(white: 1.0, alpha: 1).cgColor
                : NSColor(white: 0.97, alpha: 1).cgColor

            for ci in 0..<colCount {
                let cellRect = CGRect(x: margin + CGFloat(ci) * colWidth, y: y - rowH,
                                      width: colWidth, height: rowH)
                ctx.setFillColor(bgColor)
                ctx.fill(cellRect)
                ctx.setStrokeColor(NSColor(white: 0.8, alpha: 1).cgColor)
                ctx.setLineWidth(0.5)
                ctx.stroke(cellRect)

                let text = ci < row.count ? MarkdownTableParser.stripMarkdown(row[ci]) : ""
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 9),
                    .foregroundColor: NSColor(white: 0.15, alpha: 1),
                ]
                let textRect = cellRect.insetBy(dx: textInset, dy: 4)
                (text as NSString).draw(in: textRect, withAttributes: attrs)
            }
            y -= rowH
        }

        return y - 6   // 6pt spacing after table
    }

    private static func tableBlocks(_ table: ReportTable) -> [NSAttributedString] {
        // Fallback path (not used when drawTable is available, kept for compatibility)
        var blocks: [NSAttributedString] = []
        let headerLine = table.headers.map { MarkdownTableParser.stripMarkdown($0) }.joined(separator: "   ")
        blocks.append(NSAttributedString(string: headerLine + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.black,
        ]))
        for row in table.rows {
            let line = row.map { MarkdownTableParser.stripMarkdown($0) }.joined(separator: "   ")
            blocks.append(NSAttributedString(string: line + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor(white: 0.2, alpha: 1),
            ]))
        }
        return blocks
    }

    private static func sourceBlock(index: Int, source: SourceReference) -> NSAttributedString {
        NSAttributedString(string: "[\(index)] \(source.title) — \(source.domain)\n", attributes: [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.gray,
        ])
    }
}

// MARK: - CSV Writer

enum CSVWriter {
    static func write(headers: [String], rows: [[String]], to url: URL) throws {
        var lines: [String] = [csvRow(headers.map { MarkdownTableParser.stripMarkdown($0) })]
        for row in rows {
            let cleanRow = row.map { MarkdownTableParser.stripMarkdown($0) }
            lines.append(csvRow(cleanRow))
        }
        let content = lines.joined(separator: "\r\n")
        // UTF-8 BOM for Excel/Numbers compatibility
        var bom = Data([0xEF, 0xBB, 0xBF])
        bom.append(content.data(using: .utf8) ?? Data())
        try bom.write(to: url, options: .atomic)
    }

    private static func csvRow(_ cells: [String]) -> String {
        cells.map { cell in
            let escaped = cell.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }.joined(separator: ",")
    }
}

// MARK: - RTF Writer (DOCX fallback)

enum RTFWriter {
    static func write(_ doc: ReportDocument, to url: URL) throws {
        var lines: [String] = []
        lines.append(doc.title)
        if !doc.subtitle.isEmpty { lines.append(doc.subtitle) }
        lines.append("")
        for section in doc.sections {
            if !section.heading.isEmpty { lines.append(section.heading + ":") }
            if !section.body.isEmpty    { lines.append(section.body) }
            for bullet in section.bullets { lines.append("• \(bullet)") }
            if let table = section.table {
                let cleanHeaders = table.headers.map { MarkdownTableParser.stripMarkdown($0) }
                lines.append(cleanHeaders.joined(separator: "\t"))
                for row in table.rows {
                    let cleanCells = (0..<table.headers.count).map { i in
                        i < row.count ? MarkdownTableParser.stripMarkdown(row[i]) : ""
                    }
                    lines.append(cleanCells.joined(separator: "\t"))
                }
            }
            lines.append("")
        }
        if !doc.sources.isEmpty {
            lines.append("Источники:")
            for (i, src) in doc.sources.enumerated() {
                lines.append("[\(i+1)] \(src.title) — \(src.url)")
            }
        }
        let attrStr = NSAttributedString(string: lines.joined(separator: "\n"), attributes: [
            .font: NSFont.systemFont(ofSize: 12),
        ])
        let data = try attrStr.data(from: NSRange(location: 0, length: attrStr.length),
                                     documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        try data.write(to: url, options: .atomic)
    }
}

enum ExportError: Error, LocalizedError {
    case renderFailed(String)
    var errorDescription: String? {
        if case .renderFailed(let m) = self { return m }; return nil
    }
}
