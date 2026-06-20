import Foundation

// Converts full assistant reply to a short spoken summary.
// Full text is always shown in chat; voice gets a condensed version.
struct SpeechOutputFormatter {

    static func format(_ text: String, mode: VoiceMode) -> String {
        guard mode != .off else { return "" }
        let limit = mode == .brief ? 220 : 600
        return condense(text, limit: limit)
    }

    private static func condense(_ text: String, limit: Int) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }

        // Browser/tool raw payloads — never read aloud
        let rawMarkers = ["CURRENT_PAGE:", "ACTION_RESULT:", "\"elements\":", "\"scrollY\":", "{\"ok\":", "\"tag\":"]
        if rawMarkers.contains(where: { t.contains($0) }) {
            return "Готово."
        }

        // API error long form
        if t.hasPrefix("Не удалось получить ответ:") {
            return "Ошибка запроса. Подробности в чате."
        }

        // Code blocks → short summary
        if t.contains("```") {
            let stripped = t
                .replacingOccurrences(of: #"```[\s\S]*?```"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if stripped.count < 80 {
                return stripped.isEmpty ? "Код в чате." : stripped
            }
            return "Я подготовила код. Он в чате."
        }

        // Replace URLs with neutral word
        t = t.replacingOccurrences(of: #"https?://\S+"#, with: "ссылка", options: .regularExpression)

        // Strip markdown formatting (bold, italic, headings, bullets)
        t = t.replacingOccurrences(of: #"\*\*([^*\n]+)\*\*"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\*([^*\n]+)\*"#,   with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?m)^#+\s+"#,       with: "",   options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?m)^[-*•]\s+"#,    with: "",   options: .regularExpression)

        // Long multi-line response — read only first meaningful sentence
        let lines = t.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.count > 4 {
            let first = String(lines[0].prefix(limit))
            return first + " Подробнее в чате."
        }

        t = lines.joined(separator: " ")

        // Hard length cap
        if t.count > limit {
            return String(t.prefix(limit)).trimmingCharacters(in: .whitespaces) + "… Подробнее в чате."
        }

        return t
    }
}
