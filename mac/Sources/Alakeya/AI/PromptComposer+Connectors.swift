import Foundation

// ============================================================
// PromptComposer+Connectors.swift
// Injects active connector context into the system prompt.
// ============================================================

extension PromptComposer {
    @MainActor
    static func connectorsSystemBlock() -> String {
        ConnectorRegistry.shared.connectorSystemPrompt()
    }
}
