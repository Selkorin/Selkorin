import Foundation

// ============================================================
// ConnectorExecutor.swift — stub executor for all connector tools.
// All real API calls are TODO. Returns formatted stub responses
// that let the AI know the connector isn't configured yet.
// ============================================================

final class ConnectorExecutor {
    static let shared = ConnectorExecutor()
    private init() {}

    func execute(toolName: String, args: [String: String]) async throws -> String {
        let connectorID = connectorIDForTool(toolName)

        let (status, connectorTitle) = await MainActor.run {
            let reg = ConnectorRegistry.shared
            let s = reg.states[connectorID]?.status ?? .disconnected
            let t = reg.connectors.first(where: { $0.id == connectorID })?.title ?? connectorID
            return (s, t)
        }

        guard status == .connected else {
            return stubNotConnected(connector: connectorTitle, tool: toolName)
        }

        // TODO: implement real API calls per tool
        return stubApiNotImplemented(tool: toolName, args: args)
    }

    // MARK: - Connector ID mapping

    private func connectorIDForTool(_ toolName: String) -> String {
        if toolName.hasPrefix("gmail_")         { return "gmail" }
        if toolName.hasPrefix("drive_")         { return "google_drive" }
        if toolName.hasPrefix("docs_")          { return "google_docs" }
        if toolName.hasPrefix("sheets_")        { return "google_sheets" }
        if toolName.hasPrefix("calendar_")      { return "google_calendar" }
        if toolName.hasPrefix("telegram_")      { return "telegram" }
        if toolName.hasPrefix("vk_")            { return "vk" }
        if toolName.hasPrefix("instagram_")     { return "instagram" }
        if toolName.hasPrefix("spreadsheet_")   { return "local_spreadsheet" }
        return "custom_api"
    }

    // MARK: - Stub responses

    private func stubNotConnected(connector: String, tool: String) -> String {
        """
        CONNECTOR_ERROR: коннектор «\(connector)» не подключён.
        Инструмент «\(tool)» недоступен.
        Попроси пользователя открыть Настройки → Коннекторы и подключить «\(connector)».
        Пока можешь помочь вручную: составь нужный текст / документ / список прямо в чате.
        """
    }

    private func stubApiNotImplemented(tool: String, args: [String: String]) -> String {
        let argsSummary = args.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        return """
        CONNECTOR_STUB: инструмент «\(tool)» вызван (args: \(argsSummary)).
        Реальный API-вызов ещё не реализован — это TODO-заглушка.
        Сообщи пользователю, что коннектор находится в разработке.
        """
    }
}
