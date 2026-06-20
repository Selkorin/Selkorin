import Foundation
import AppKit

// ============================================================
// DocumentExportManager.swift — coordinates all document exports.
// Saves to ~/Documents/Alakeya/Exports/ by default.
// Calls PDFReportRenderer, CSVWriter, RTFWriter.
// Falls back gracefully. No force unwrap, no fatalError.
// ============================================================

@MainActor
final class DocumentExportManager {
    static let shared = DocumentExportManager()
    private init() {}

    // MARK: - Export folder

    private var exportDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = docs.appendingPathComponent("Alakeya/Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Export from ReportDocument

    func export(_ doc: ReportDocument, as format: DocumentFormat) async throws -> ExportedFile {
        let filename = sanitize(doc.title) + "_\(timestamp()).\(format.fileExtension)"
        let dest     = exportDir.appendingPathComponent(filename)

        guard !FileManager.default.fileExists(atPath: dest.path) else {
            let dest2 = exportDir.appendingPathComponent(
                sanitize(doc.title) + "_\(timestamp())_2.\(format.fileExtension)")
            return try await exportTo(doc: doc, format: format, dest: dest2)
        }
        return try await exportTo(doc: doc, format: format, dest: dest)
    }

    private func exportTo(doc: ReportDocument, format: DocumentFormat, dest: URL) async throws -> ExportedFile {
        switch format {
        case .pdf:
            try PDFReportRenderer.render(doc, to: dest)
        case .docx:
            let success = await exportViaScript(doc: doc, dest: dest)
            if !success {
                let rtfDest = dest.deletingPathExtension().appendingPathExtension("rtf")
                try RTFWriter.write(doc, to: rtfDest)
                let file = ExportedFile(path: rtfDest, format: .rtf, sizeBytes: fileSize(rtfDest))
                revealInFinder(rtfDest)
                return file
            }
        case .rtf:
            try RTFWriter.write(doc, to: dest)
        case .csv:
            guard let firstTable = doc.sections.compactMap({ $0.table }).first else {
                throw ExportError.renderFailed("Нет таблицы для экспорта в CSV. Добавьте таблицу в секцию отчёта.")
            }
            try CSVWriter.write(headers: firstTable.headers, rows: firstTable.rows, to: dest)
        case .markdown:
            try markdownWrite(doc, to: dest)
        }

        let file = ExportedFile(path: dest, format: format, sizeBytes: fileSize(dest))
        revealInFinder(dest)
        return file
    }

    // MARK: - Export from raw content string + title

    func exportText(_ content: String, title: String, as format: DocumentFormat) async throws -> ExportedFile {
        let doc = ReportDocument(
            title: title,
            sections: [ReportSection(heading: "", body: content)]
        )
        return try await export(doc, as: format)
    }

    // MARK: - Export table (headers + rows arrays)

    func exportTable(title: String, headers: [String], rows: [[String]], as format: DocumentFormat) async throws -> ExportedFile {
        switch format {
        case .csv:
            let filename = sanitize(title) + "_\(timestamp()).csv"
            let dest = exportDir.appendingPathComponent(filename)
            try CSVWriter.write(headers: headers, rows: rows, to: dest)
            let file = ExportedFile(path: dest, format: .csv, sizeBytes: fileSize(dest))
            revealInFinder(dest)
            return file
        default:
            let table   = ReportTable(headers: headers, rows: rows)
            let section = ReportSection(heading: title, table: table)
            let doc     = ReportDocument(title: title, sections: [section])
            return try await export(doc, as: format)
        }
    }

    // MARK: - Markdown writer

    private func markdownWrite(_ doc: ReportDocument, to url: URL) throws {
        var lines = ["# \(doc.title)"]
        if !doc.subtitle.isEmpty { lines.append("## \(doc.subtitle)") }
        lines.append("")
        for section in doc.sections {
            if !section.heading.isEmpty { lines.append("### \(section.heading)") }
            if !section.body.isEmpty    { lines.append(section.body) }
            for b in section.bullets    { lines.append("- \(b)") }
            if let t = section.table {
                lines.append("| " + t.headers.joined(separator: " | ") + " |")
                lines.append("| " + t.headers.map { _ in "---" }.joined(separator: " | ") + " |")
                for row in t.rows {
                    lines.append("| " + row.joined(separator: " | ") + " |")
                }
            }
            lines.append("")
        }
        if !doc.sources.isEmpty {
            lines.append("## Источники")
            for (i, s) in doc.sources.enumerated() {
                lines.append("[\(i+1)] [\(s.title)](\(s.url))")
            }
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Python DOCX helper (crash-proof)

    private func pythonHelperPath() -> String? {
        let candidates = [
            Bundle.main.bundlePath + "/Contents/Resources/scripts/export_docx.py",
            "/Users/werni/Selkorin/mac/scripts/export_docx.py",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    private func exportViaScript(doc: ReportDocument, dest: URL) async -> Bool {
        guard let pyPath = pythonHelperPath() else {
            print("[DocumentExport] python script not found, falling back to RTF")
            return false
        }

        guard let jsonData = try? JSONEncoder().encode(doc) else {
            print("[DocumentExport] failed to encode document JSON")
            return false
        }
        let base64 = jsonData.base64EncodedString()

        // Find python3 binary
        let python3Paths = ["/usr/bin/python3", "/usr/local/bin/python3",
                            "/opt/homebrew/bin/python3", "/opt/local/bin/python3"]
        guard let pythonBin = python3Paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            print("[DocumentExport] python3 not found")
            return false
        }

        return await withCheckedContinuation { continuation in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: pythonBin)
            proc.arguments = [pyPath, "--output", dest.path, "--data", base64]

            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError  = errPipe

            // Timeout: kill after 15 seconds
            let workItem = DispatchWorkItem {
                if proc.isRunning {
                    proc.terminate()
                    print("[DocumentExport] python script timed out after 15s")
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: workItem)

            do {
                try proc.run()
            } catch {
                workItem.cancel()
                print("[DocumentExport] failed to launch python: \(error.localizedDescription)")
                continuation.resume(returning: false)
                return
            }

            proc.terminationHandler = { p in
                workItem.cancel()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errText = String(data: errData, encoding: .utf8) ?? ""
                if p.terminationStatus != 0 {
                    print("[DocumentExport] python exited \(p.terminationStatus): \(errText)")
                    continuation.resume(returning: false)
                } else {
                    print("[DocumentExport] python DOCX created: \(dest.lastPathComponent)")
                    continuation.resume(returning: true)
                }
            }
        }
    }

    // MARK: - Helpers

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func fileSize(_ url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init)) ?? 0
    }

    private func sanitize(_ name: String) -> String {
        name.components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: " _-")).inverted)
            .joined()
            .replacingOccurrences(of: " ", with: "_")
            .prefix(40)
            .description
    }

    private func timestamp() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmm"
        return df.string(from: Date())
    }
}
