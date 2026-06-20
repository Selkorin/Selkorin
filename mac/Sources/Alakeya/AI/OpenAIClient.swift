import Foundation

final class OpenAIClient: AIProviderClient {
    private let configuration: AIProviderConfiguration
    private let apiKey: String

    init(configuration: AIProviderConfiguration, apiKey: String) throws {
        guard URL(string: configuration.baseURL) != nil else { throw AIClientError.invalidBaseURL }
        self.configuration = configuration
        self.apiKey = apiKey
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
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": configuration.modelName,
            "messages": apiMessages,
        ])
        let data = try await AIHTTP.data(for: request)
        return try AIHTTP.openAICompatibleText(from: data)
    }

    // ── Vision (image input) ──────────────────────────────

    func sendMessageWithImages(userText: String, images: [Data], history: [ChatMessage]) async throws -> String {
        var apiMessages: [[String: Any]] = [
            ["role": "system", "content": PromptComposer.composeWithSkillAndKnowledge()]
        ]
        if !history.isEmpty {
            apiMessages += history.map { ["role": $0.role == .user ? "user" : "assistant", "content": $0.content] }
        }
        var contentParts: [[String: Any]] = images.map { data in
            ["type": "image_url",
             "image_url": ["url": "data:image/jpeg;base64,\(data.base64EncodedString())"]]
        }
        if !userText.isEmpty {
            contentParts.append(["type": "text", "text": userText])
        }
        apiMessages.append(["role": "user", "content": contentParts])

        var request = URLRequest(
            url: try AIHTTP.endpoint(baseURL: configuration.baseURL, path: "chat/completions")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": configuration.modelName,
            "messages": apiMessages,
        ])
        let data = try await AIHTTP.data(for: request)
        return try AIHTTP.openAICompatibleText(from: data)
    }

    // ── Tool calling ──────────────────────────────────────

    func sendWithTools(
        userText: String, history: [ChatMessage], tools: [[String: Any]]
    ) async throws -> AIProviderResponse {
        var messages: [[String: Any]] = [
            ["role": "system", "content": PromptComposer.composeWithSkillAndKnowledge()]
        ]
        if !history.isEmpty {
            messages += history.map { ["role": $0.role == .user ? "user" : "assistant", "content": $0.content] }
        } else {
            messages.append(["role": "user", "content": userText])
        }
        return try await callOpenAI(messages: messages, tools: tools)
    }

    func sendWithToolResults(
        context: Any, results: [ToolCallResult], tools: [[String: Any]]
    ) async throws -> AIProviderResponse {
        guard var messages = context as? [[String: Any]] else {
            throw AIClientError.invalidResponse
        }
        for r in results {
            messages.append(["role": "tool", "tool_call_id": r.callID, "content": r.output])
        }
        return try await callOpenAI(messages: messages, tools: tools)
    }

    private func callOpenAI(messages: [[String: Any]], tools: [[String: Any]]) async throws -> AIProviderResponse {
        var body: [String: Any] = ["model": configuration.modelName, "messages": messages]
        if !tools.isEmpty { body["tools"] = tools; body["tool_choice"] = "auto" }

        var request = URLRequest(
            url: try AIHTTP.endpoint(baseURL: configuration.baseURL, path: "chat/completions")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await AIHTTP.data(for: request)
        return try AIHTTP.openAICompatibleResponse(data: data, priorMessages: messages)
    }
}
