import Foundation

final class AnthropicClient: AIProviderClient {
    private let configuration: AIProviderConfiguration
    private let apiKey: String

    init(configuration: AIProviderConfiguration, apiKey: String) throws {
        guard URL(string: configuration.baseURL) != nil else { throw AIClientError.invalidBaseURL }
        self.configuration = configuration
        self.apiKey = apiKey
    }

    func sendMessage(userText: String, history: [ChatMessage]) async throws -> String {
        let apiMessages: [[String: Any]]
        if !history.isEmpty {
            apiMessages = history.map { msg in
                ["role": msg.role == .user ? "user" : "assistant", "content": msg.content]
            }
        } else {
            apiMessages = [["role": "user", "content": userText]]
        }

        var request = URLRequest(
            url: try AIHTTP.endpoint(baseURL: configuration.baseURL, path: "messages")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": configuration.modelName,
            "max_tokens": 4096,
            "system": PromptComposer.composeWithSkillAndKnowledge(),
            "messages": apiMessages,
        ])

        let data = try await AIHTTP.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = json?["content"] as? [[String: Any]]
        let text = content?.compactMap { $0["text"] as? String }.joined()
        guard let text, !text.isEmpty else { throw AIClientError.invalidResponse }
        return text
    }

    // ── Tool calling ─────────────────────────────────────

    func sendWithTools(
        userText: String, history: [ChatMessage], tools: [[String: Any]]
    ) async throws -> AIProviderResponse {
        let apiMessages = buildMessages(userText: userText, history: history)
        let anthropicTools = tools.compactMap(Self.toAnthropicTool)
        return try await callAnthropic(messages: apiMessages, tools: anthropicTools)
    }

    func sendWithToolResults(
        context: Any, results: [ToolCallResult], tools: [[String: Any]]
    ) async throws -> AIProviderResponse {
        guard var messages = context as? [[String: Any]] else {
            throw AIClientError.invalidResponse
        }
        let toolResultBlocks: [[String: Any]] = results.map { r in
            ["type": "tool_result", "tool_use_id": r.callID, "content": r.output]
        }
        messages.append(["role": "user", "content": toolResultBlocks])
        let anthropicTools = tools.compactMap(Self.toAnthropicTool)
        return try await callAnthropic(messages: messages, tools: anthropicTools)
    }

    private func callAnthropic(
        messages: [[String: Any]], tools: [[String: Any]]
    ) async throws -> AIProviderResponse {
        var body: [String: Any] = [
            "model": configuration.modelName,
            "max_tokens": 4096,
            "system": PromptComposer.composeWithSkillAndKnowledge(),
            "messages": messages,
        ]
        if !tools.isEmpty { body["tools"] = tools }

        var request = URLRequest(
            url: try AIHTTP.endpoint(baseURL: configuration.baseURL, path: "messages")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await AIHTTP.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]]
        else { throw AIClientError.invalidResponse }

        let toolUseBlocks = content.filter { $0["type"] as? String == "tool_use" }
        if !toolUseBlocks.isEmpty {
            let calls: [AIToolCall] = toolUseBlocks.compactMap { block in
                guard let id = block["id"] as? String,
                      let name = block["name"] as? String,
                      let input = block["input"] as? [String: Any]
                else { return nil }
                return AIToolCall(id: id, name: name,
                                  args: input.compactMapValues { "\($0)" })
            }
            let assistantMessage: [String: Any] = ["role": "assistant", "content": content]
            return .toolCalls(calls, context: messages + [assistantMessage])
        }

        let text = content.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw AIClientError.invalidResponse }
        return .text(text)
    }

    private func buildMessages(userText: String, history: [ChatMessage]) -> [[String: Any]] {
        if !history.isEmpty {
            return history.map { ["role": $0.role == .user ? "user" : "assistant",
                                  "content": $0.content] }
        }
        return [["role": "user", "content": userText]]
    }

    private static func toAnthropicTool(_ openAITool: [String: Any]) -> [String: Any]? {
        guard let fn = openAITool["function"] as? [String: Any],
              let name = fn["name"] as? String,
              let description = fn["description"] as? String,
              let parameters = fn["parameters"] as? [String: Any]
        else { return nil }
        var schema = parameters
        schema.removeValue(forKey: "additionalProperties")
        return ["name": name, "description": description, "input_schema": schema]
    }

    // ── Vision (image input) ──────────────────────────────

    func sendMessageWithImages(userText: String, images: [Data], history: [ChatMessage]) async throws -> String {
        var apiMessages: [[String: Any]] = []
        if !history.isEmpty {
            apiMessages = history.map { ["role": $0.role == .user ? "user" : "assistant", "content": $0.content] }
        }
        var contentParts: [[String: Any]] = images.map { data in
            ["type": "image",
             "source": ["type": "base64", "media_type": "image/jpeg", "data": data.base64EncodedString()]]
        }
        if !userText.isEmpty {
            contentParts.append(["type": "text", "text": userText])
        }
        apiMessages.append(["role": "user", "content": contentParts])

        var request = URLRequest(
            url: try AIHTTP.endpoint(baseURL: configuration.baseURL, path: "messages")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": configuration.modelName,
            "max_tokens": 4096,
            "system": PromptComposer.composeWithSkillAndKnowledge(),
            "messages": apiMessages,
        ])
        let data = try await AIHTTP.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = json?["content"] as? [[String: Any]]
        let text = content?.compactMap { $0["text"] as? String }.joined()
        guard let text, !text.isEmpty else { throw AIClientError.invalidResponse }
        return text
    }
}

