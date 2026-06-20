import Foundation

// ============================================================
// ExportGuard.swift — prevents fake/empty exports.
// Returns non-nil error string when export should be blocked.
// ============================================================

enum ExportGuard {

    // Checks text-based export content (PDF, DOCX, Markdown).
    // Returns an error string if export should be denied, nil if allowed.
    static func checkText(_ content: String, label: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            print("[ExportGuard] allowed=false reason=empty_content format=\(label)")
            return """
            EXPORT_DENIED: Контент для \(label) пуст. \
            Сначала собери данные, потом вызови export.
            """
        }

        // Placeholder / in-progress text — not real collected data
        let placeholderSignals = [
            "начинаю поиск", "запускаю поиск", "начинаю сбор",
            "подождите", "ищу информацию", "выполняю поиск",
            "приступаю к", "в процессе", "загружаю",
        ]
        let lower = trimmed.lowercased()
        for signal in placeholderSignals {
            if lower.contains(signal) && trimmed.count < 200 {
                print("[ExportGuard] allowed=false reason=placeholder format=\(label) signal=\(signal)")
                return """
                EXPORT_DENIED: Контент выглядит как заглушка («\(signal)»). \
                Дождись реальных данных и снова вызови export.
                """
            }
        }

        // Content too short to be meaningful
        if trimmed.count < 30 {
            print("[ExportGuard] allowed=false reason=too_short chars=\(trimmed.count) format=\(label)")
            return """
            EXPORT_DENIED: Контент слишком короткий (\(trimmed.count) символов). \
            Сначала собери данные.
            """
        }

        print("[ExportGuard] allowed=true format=\(label) chars=\(trimmed.count)")
        return nil
    }

    // Checks table-based export (CSV).
    // Returns an error string if export should be denied, nil if allowed.
    static func checkTable(headers: [String], rows: [[String]], label: String) -> String? {
        if headers.isEmpty && rows.isEmpty {
            print("[ExportGuard] allowed=false reason=empty_table format=\(label)")
            return """
            EXPORT_DENIED: Таблица пуста — нет заголовков и строк. \
            Сначала собери данные (business_cards, contact_cards или другой extractor), \
            потом вызови export.
            """
        }

        if rows.isEmpty {
            print("[ExportGuard] allowed=false reason=no_rows format=\(label) headers=\(headers.count)")
            return """
            EXPORT_DENIED: В таблице есть заголовки (\(headers.joined(separator: ", "))), \
            но нет строк с данными. Сначала собери реальные данные.
            """
        }

        // Check for placeholder rows (all cells empty or contain placeholder text)
        let realRows = rows.filter { row in
            row.contains { cell in
                let t = cell.trimmingCharacters(in: .whitespacesAndNewlines)
                return !t.isEmpty && t != "-" && t != "—" && t != "N/A" && t != "н/д"
            }
        }
        if realRows.isEmpty {
            print("[ExportGuard] allowed=false reason=placeholder_rows format=\(label) rows=\(rows.count)")
            return """
            EXPORT_DENIED: Все строки таблицы — заглушки. \
            Нет реальных данных для экспорта.
            """
        }

        print("[ExportGuard] allowed=true format=\(label) rows=\(realRows.count)")
        return nil
    }
}
