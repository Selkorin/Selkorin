import Foundation

// ============================================================
// ExportInputResolver.swift — when user says "выгрузи это",
// finds the last meaningful content:
//   1. Prefers structured tables from ChatMessage.structuredTables
//   2. Falls back to last long assistant message body
// Injects clean markdown table into [КОНТЕНТ ДЛЯ ЭКСПОРТА].
// ============================================================

enum ExportInputResolver {

    static func resolve(userText: String, history: [ChatMessage]) -> String {
        // Long user message carries its own content.
        if userText.trimmingCharacters(in: .whitespacesAndNewlines).count > 200 {
            return userText
        }

        // ── Priority 1: structured tables from research coordinator ──
        if let tableBlock = lastStructuredTableBlock(from: history) {
            return """
            \(userText)

            [КОНТЕНТ ДЛЯ ЭКСПОРТА — структурированная таблица из исследования:]
            \(tableBlock)
            """
        }

        // ── Priority 2: last long assistant message (may contain markdown table) ──
        guard let lastContent = lastMeaningfulAssistantContent(from: history) else {
            return userText
        }

        let truncated = lastContent.count > 8000
            ? String(lastContent.prefix(8000)) + "\n...[усечено]"
            : lastContent

        return """
        \(userText)

        [КОНТЕНТ ДЛЯ ЭКСПОРТА — последнее содержательное сообщение ассистента:]
        \(truncated)
        """
    }

    // MARK: - Structured table search

    private static func lastStructuredTableBlock(from messages: [ChatMessage]) -> String? {
        for message in messages.reversed() {
            guard message.role == .assistant, !message.structuredTables.isEmpty else { continue }
            // Combine all tables as clean markdown
            let block = message.structuredTables
                .filter { !$0.rows.isEmpty }
                .map { $0.toMarkdown() }
                .joined(separator: "\n\n")
            if !block.isEmpty { return block }
        }
        return nil
    }

    // MARK: - Fallback: long text search

    private static func lastMeaningfulAssistantContent(from messages: [ChatMessage]) -> String? {
        for message in messages.reversed() {
            guard message.role == .assistant else { continue }
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard content.count > 150 else { continue }
            guard !content.hasPrefix("Не удалось") else { continue }
            guard !content.hasPrefix("✅ Файл создан") else { continue }
            guard !content.hasPrefix("Готово.") else { continue }
            guard !content.hasPrefix("В каком городе") else { continue }
            return content
        }
        return nil
    }
}
