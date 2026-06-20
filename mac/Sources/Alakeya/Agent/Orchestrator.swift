import Foundation

// ============================================================
// Orchestrator.swift — task → plan (typed tool calls) + spoken reply.
// Mirrors the documented agent loop. Uses OpenAI (strict tool schemas,
// DOC2) when OPENAI_API_KEY is set, else a deterministic offline planner.
// ============================================================

final class Orchestrator {

    private let appAliases: [String: String] = [
        "телеграм": "Telegram", "telegram": "Telegram", "тг": "Telegram",
        "сафари": "Safari", "safari": "Safari", "браузер": "Safari",
        "хром": "Chrome", "chrome": "Chrome",
        "почта": "Mail", "mail": "Mail",
        "заметки": "Notes", "notes": "Notes",
        "finder": "Finder", "файлы": "Finder",
    ]

    func plan(_ text: String) async -> Plan {
        if ProcessInfo.processInfo.environment["OPENAI_API_KEY"] != nil {
            if let p = try? await openAIPlan(text) { return p }
        }
        return mockPlan(text)
    }

    // ── Offline intent parser ─────────────────────────────
    private func detectApp(_ text: String) -> String? {
        let low = text.lowercased()
        for (k, v) in appAliases where low.contains(k) { return v }
        return nil
    }

    func mockPlan(_ text: String) -> Plan {
        let low = text.lowercased()
        let app = detectApp(text)
        var calls: [ToolCall] = []
        var steps: [TaskStep] = []
        func push(_ name: ActionType, _ args: [String: String], _ label: String) {
            calls.append(ToolCall(name: name, args: args))
            steps.append(TaskStep(label: label))
        }

        if low.range(of: #"(открой|открыть|запусти|open|launch)"#, options: .regularExpression) != nil,
           let app { push(.openApp, ["app": app], "Открыть \(app)") }

        if let m = firstGroup(text, #"(?:найди|найти|поиск|search)[:\s]+(.+)$"#) {
            if app == nil { push(.openApp, ["app": "Safari"], "Открыть Safari") }
            push(.search, ["query": m], "Найти: \(String(m.prefix(30)))")
        }

        if let rest = firstGroup(text, #"(?:напиши|написать|отправь|send)\s+(.+)$"#),
           let app, low.range(of: #"(telegram|mail|почт|сообщ|message)"#, options: .regularExpression) != nil
                     || ["Telegram", "Mail"].contains(app) {
            let parts = rest.split(separator: " ", maxSplits: 1).map(String.init)
            let recipient = parts.first ?? rest
            let message = parts.count > 1 ? parts[1] : "Привет!"
            push(.typeText, ["text": recipient, "app": app], "Найти чат: \(recipient)")
            push(.typeText, ["text": message, "app": app], "Ввести сообщение")
            push(.sendMessage, ["text": message, "target": "\(app)·\(recipient)", "app": app], "Отправить сообщение")
        }

        if let m = firstGroup(text, #"(?:удали|удалить|delete)\s+(.+)$"#) {
            push(.deleteFile, ["target": m], "Удалить \(m)")
        }

        if low.range(of: #"(что на экране|опиши экран|what.*screen)"#, options: .regularExpression) != nil {
            push(.readScreen, [:], "Прочитать экран")
        }

        if calls.isEmpty { push(.readScreen, [:], "Осмотреть экран") }

        return Plan(steps: steps, toolCalls: calls, reply: buildReply(calls))
    }

    private func buildReply(_ calls: [ToolCall]) -> String {
        if calls.contains(where: { $0.name == .sendMessage }) { return "Готово, сообщение отправлено." }
        if calls.contains(where: { $0.name == .openApp }) { return "Открыл, что просил." }
        if calls.contains(where: { $0.name == .search }) { return "Вот результаты поиска." }
        return "Готово."
    }

    private func firstGroup(_ text: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return text[r].trimmingCharacters(in: .whitespaces)
    }

    // ── OpenAI provider (strict tool schemas) ─────────────
    private func openAIPlan(_ text: String) async throws -> Plan {
        let env = ProcessInfo.processInfo.environment
        let key = env["OPENAI_API_KEY"]!
        let model = env["ALAKEYA_MODEL"] ?? "gpt-4o"

        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": text],
            ],
            "tools": Self.toolSchemas,
            "tool_choice": "auto",
        ])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw ExecError.failed("OpenAI HTTP error")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let rawCalls = (message?["tool_calls"] as? [[String: Any]]) ?? []

        var calls: [ToolCall] = []
        var steps: [TaskStep] = []
        for tc in rawCalls {
            guard let fn = tc["function"] as? [String: Any],
                  let name = fn["name"] as? String,
                  let type = ActionType(rawValue: name) else { continue }
            let argStr = (fn["arguments"] as? String) ?? "{}"
            let parsed = (try? JSONSerialization.jsonObject(with: Data(argStr.utf8))) as? [String: Any] ?? [:]
            let strArgs = parsed.mapValues { "\($0)" }
            calls.append(ToolCall(name: type, args: strArgs))
            steps.append(TaskStep(label: name))
        }
        let reply = (message?["content"] as? String) ?? "Готово."
        return Plan(steps: steps, toolCalls: calls, reply: reply)
    }

    private static let systemPrompt =
        "Ты — Alakeya, локальный macOS-ассистент. Преобразуй задачу пользователя в " +
        "строго типизированные tool calls. Рискованные действия приложение подтвердит " +
        "у пользователя. Отвечай кратко по-русски."

    private static func fn(_ name: String, _ desc: String,
                           _ props: [String: Any], _ required: [String]) -> [String: Any] {
        ["type": "function", "function": [
            "name": name, "description": desc, "strict": true,
            "parameters": ["type": "object", "additionalProperties": false,
                           "properties": props, "required": required],
        ]]
    }

    private static let toolSchemas: [[String: Any]] = [
        fn("open_app", "Открыть/активировать приложение macOS.", ["app": ["type": "string"]], ["app"]),
        fn("navigate_url", "Открыть URL в браузере.", ["url": ["type": "string"]], ["url"]),
        fn("search", "Найти что-то в браузере.", ["query": ["type": "string"]], ["query"]),
        fn("type_text", "Ввести текст в активное поле.",
           ["text": ["type": "string"], "app": ["type": "string"]], ["text"]),
        fn("click_element", "Кликнуть по элементу UI по тексту.",
           ["text": ["type": "string"], "app": ["type": "string"]], ["text"]),
        fn("send_message", "Отправить сообщение в мессенджер.",
           ["text": ["type": "string"], "target": ["type": "string"], "app": ["type": "string"]],
           ["text", "target"]),
        fn("delete_file", "Удалить файл (необратимо).", ["target": ["type": "string"]], ["target"]),
        fn("run_shell", "Выполнить shell-команду.", ["command": ["type": "string"]], ["command"]),
        fn("read_screen", "Прочитать активное окно через Accessibility.", [:], []),
    ]
}
