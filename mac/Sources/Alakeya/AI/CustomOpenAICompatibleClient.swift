import Foundation

final class CustomOpenAICompatibleClient: AIProviderClient {
    private let configuration: AIProviderConfiguration
    private let apiKey: String
    private let additionalHeaders: [String: String]

    init(
        configuration: AIProviderConfiguration,
        apiKey: String,
        additionalHeaders: [String: String] = [:]
    ) throws {
        guard URL(string: configuration.baseURL) != nil else { throw AIClientError.invalidBaseURL }
        self.configuration = configuration
        self.apiKey = apiKey
        self.additionalHeaders = additionalHeaders
    }

    func sendMessage(userText: String, history: [ChatMessage]) async throws -> String {
        var apiMessages: [[String: Any]] = [
            ["role": "system", "content": PromptComposer.composeWithSkillAndKnowledge()]
        ]
        if !history.isEmpty {
            apiMessages += history.map { msg in
                ["role": msg.role == .user ? "user" : "assistant", "content": msg.content]
            }
        } else {
            apiMessages.append(["role": "user", "content": userText])
        }

        var request = URLRequest(
            url: try AIHTTP.endpoint(baseURL: configuration.baseURL, path: "chat/completions")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        additionalHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": configuration.modelName,
            "messages": apiMessages,
        ])
        let data = try await AIHTTP.data(for: request)
        return try AIHTTP.openAICompatibleText(from: data)
    }

    func sendWithTools(
        userText: String,
        history: [ChatMessage],
        tools: [[String: Any]]
    ) async throws -> AIProviderResponse {
        var messages: [[String: Any]] = [
            ["role": "system", "content": PromptComposer.composeWithSkillAndKnowledge()]
        ]
        if history.isEmpty {
            messages.append(["role": "user", "content": userText])
        } else {
            messages += history.map {
                ["role": $0.role == .user ? "user" : "assistant", "content": $0.content]
            }
        }
        return try await callCompatible(messages: messages, tools: tools)
    }

    func sendWithToolResults(
        context: Any,
        results: [ToolCallResult],
        tools: [[String: Any]]
    ) async throws -> AIProviderResponse {
        guard var messages = context as? [[String: Any]] else {
            throw AIClientError.invalidResponse
        }
        results.forEach { result in
            messages.append([
                "role": "tool",
                "tool_call_id": result.callID,
                "content": result.output,
            ])
        }
        return try await callCompatible(messages: messages, tools: tools)
    }

    private func callCompatible(
        messages: [[String: Any]],
        tools: [[String: Any]]
    ) async throws -> AIProviderResponse {
        var body: [String: Any] = [
            "model": configuration.modelName,
            "messages": messages,
        ]
        if !tools.isEmpty {
            body["tools"] = tools
            body["tool_choice"] = "auto"
        }

        var request = URLRequest(
            url: try AIHTTP.endpoint(baseURL: configuration.baseURL, path: "chat/completions")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        additionalHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let data = try await AIHTTP.data(for: request)
            return try AIHTTP.openAICompatibleResponse(data: data, priorMessages: messages)
        } catch AIClientError.server(let status, _) where !tools.isEmpty && (status == 400 || status == 422) {
            throw AIClientError.server(
                status: status,
                message: "Эта модель или провайдер не поддерживает browser tools. Выберите OpenAI, OpenRouter или OpenAI-compatible модель с поддержкой tool-calling."
            )
        }
    }
}
