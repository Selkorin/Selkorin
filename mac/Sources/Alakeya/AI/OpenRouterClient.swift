import Foundation

final class OpenRouterClient: AIProviderClient {
    private let compatibleClient: CustomOpenAICompatibleClient

    init(configuration: AIProviderConfiguration, apiKey: String) throws {
        compatibleClient = try CustomOpenAICompatibleClient(
            configuration: configuration,
            apiKey: apiKey,
            additionalHeaders: ["X-Title": "Alakeya"]
        )
    }

    func sendMessage(userText: String, history: [ChatMessage]) async throws -> String {
        try await compatibleClient.sendMessage(userText: userText, history: history)
    }

    func sendWithTools(
        userText: String,
        history: [ChatMessage],
        tools: [[String: Any]]
    ) async throws -> AIProviderResponse {
        try await compatibleClient.sendWithTools(
            userText: userText,
            history: history,
            tools: tools
        )
    }

    func sendWithToolResults(
        context: Any,
        results: [ToolCallResult],
        tools: [[String: Any]]
    ) async throws -> AIProviderResponse {
        try await compatibleClient.sendWithToolResults(
            context: context,
            results: results,
            tools: tools
        )
    }
}
