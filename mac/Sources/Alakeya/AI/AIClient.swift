import Foundation

final class AIClient {
    private let client: AIProviderClient

    init(configuration: AIProviderConfiguration, apiKey: String) throws {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIClientError.apiKeyMissing }
        guard !configuration.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIClientError.modelMissing
        }

        switch configuration.kind {
        case .openAI:
            client = try OpenAIClient(configuration: configuration, apiKey: key)
        case .anthropic:
            client = try AnthropicClient(configuration: configuration, apiKey: key)
        case .openRouter:
            client = try OpenRouterClient(configuration: configuration, apiKey: key)
        case .custom:
            client = try CustomOpenAICompatibleClient(configuration: configuration, apiKey: key)
        }
    }

    convenience init(settings: Settings) throws {
        let store = AIProviderStore.shared
        let configuration = try store.activeConfiguration(in: settings)
        guard let apiKey = try store.apiKey(for: configuration.id) else {
            throw AIClientError.apiKeyMissing
        }
        try self.init(configuration: configuration, apiKey: apiKey)
    }

    func sendMessage(
        userText: String,
        history: [ChatMessage] = [],
        memoryContext: String = ""
    ) async throws -> String {
        guard !memoryContext.isEmpty else {
            return try await client.sendMessage(userText: userText, history: history)
        }
        let primer: [ChatMessage] = [
            ChatMessage(role: .user,      content: "[Контекст о пользователе]\n\(memoryContext)"),
            ChatMessage(role: .assistant, content: "Понял, учту этот контекст."),
        ]
        return try await client.sendMessage(userText: userText, history: primer + history)
    }

    func sendMessageWithImages(
        userText: String,
        images: [Data],
        history: [ChatMessage] = [],
        memoryContext: String = ""
    ) async throws -> String {
        let h: [ChatMessage]
        if memoryContext.isEmpty {
            h = history
        } else {
            let primer: [ChatMessage] = [
                ChatMessage(role: .user,      content: "[Контекст о пользователе]\n\(memoryContext)"),
                ChatMessage(role: .assistant, content: "Понял, учту этот контекст."),
            ]
            h = primer + history
        }
        return try await client.sendMessageWithImages(userText: userText, images: images, history: h)
    }

    func sendWithTools(
        userText: String,
        history: [ChatMessage] = [],
        memoryContext: String = "",
        tools: [[String: Any]]
    ) async throws -> AIProviderResponse {
        let h: [ChatMessage]
        if memoryContext.isEmpty {
            h = history
        } else {
            let primer: [ChatMessage] = [
                ChatMessage(role: .user,      content: "[Контекст о пользователе]\n\(memoryContext)"),
                ChatMessage(role: .assistant, content: "Понял, учту этот контекст."),
            ]
            h = primer + history
        }
        return try await client.sendWithTools(userText: userText, history: h, tools: tools)
    }

    func sendWithToolResults(
        context: Any,
        results: [ToolCallResult],
        tools: [[String: Any]]
    ) async throws -> AIProviderResponse {
        try await client.sendWithToolResults(context: context, results: results, tools: tools)
    }
}

enum AIHTTP {
    static func endpoint(baseURL: String, path: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmed)/\(path)") else {
            throw AIClientError.invalidBaseURL
        }
        return url
    }

    static func data(for request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AIClientError.invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                throw mapError(status: http.statusCode, data: data)
            }
            return data
        } catch let error as AIClientError {
            throw error
        } catch {
            throw AIClientError.network(error.localizedDescription)
        }
    }

    static func mapError(status: Int, data: Data) -> AIClientError {
        if status == 401 || status == 403 { return .invalidAPIKey }
        if status == 429 { return .rateLimited }

        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let error = json?["error"] as? [String: Any]
        let message = error?["message"] as? String ?? ""
        return .server(status: status, message: message)
    }

    static func openAICompatibleText(from data: Data) throws -> String {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        if let text = message?["content"] as? String, !text.isEmpty { return text }

        if let parts = message?["content"] as? [[String: Any]] {
            let text = parts.compactMap { part -> String? in
                if let value = part["text"] as? String { return value }
                if let value = part["content"] as? String { return value }
                return nil
            }.joined()
            if !text.isEmpty { return text }
        }
        throw AIClientError.invalidResponse
    }

    static func openAICompatibleResponse(
        data: Data,
        priorMessages: [[String: Any]]
    ) throws -> AIProviderResponse {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any]
        else { throw AIClientError.invalidResponse }

        if let rawCalls = message["tool_calls"] as? [[String: Any]], !rawCalls.isEmpty {
            let parsed = rawCalls.compactMap { call -> AIToolCall? in
                guard let id = call["id"] as? String,
                      let function = call["function"] as? [String: Any],
                      let name = function["name"] as? String
                else { return nil }
                let rawArguments = function["arguments"] as? String ?? "{}"
                let arguments = (
                    try? JSONSerialization.jsonObject(with: Data(rawArguments.utf8))
                        as? [String: Any]
                ) ?? [:]
                return AIToolCall(
                    id: id,
                    name: name,
                    args: arguments.compactMapValues { "\($0)" }
                )
            }
            if !parsed.isEmpty {
                var assistantMessage: [String: Any] = [
                    "role": "assistant",
                    "tool_calls": rawCalls,
                ]
                if let content = message["content"] as? String {
                    assistantMessage["content"] = content
                }
                return .toolCalls(parsed, context: priorMessages + [assistantMessage])
            }
        }

        return try .text(openAICompatibleText(from: data))
    }
}
