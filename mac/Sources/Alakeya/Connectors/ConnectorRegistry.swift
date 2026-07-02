import Foundation
import AppKit
import SwiftUI

// ============================================================
// ConnectorRegistry.swift — singleton that owns all connectors
// and their connection state.
// ============================================================

@MainActor
final class ConnectorRegistry: ObservableObject {
    static let shared = ConnectorRegistry()

    @Published private(set) var connectors: [Connector]
    @Published private(set) var states: [String: ConnectorConnectionState]

    private let auth = ConnectorAuthStore.shared

    private init() {
        connectors = Self.builtInConnectors()
        states     = ConnectorAuthStore.shared.loadStates()
    }

    // MARK: - State queries

    func status(for id: String) -> ConnectorStatus {
        if let s = states[id]?.status { return s }
        return .disconnected
    }

    func hasAnyEnabled() -> Bool {
        connectors.contains { $0.isEnabled }
    }

    // MARK: - Connection actions

    func connect(connectorID: String) {
        guard let connector = connectors.first(where: { $0.id == connectorID }) else { return }
        switch connector.authType {
        case .none:
            setConnected(connectorID: connectorID, connectedEmail: "Локально")
        case .apiKey:
            connectWithAPIKey(connector: connector)
        case .oauth2:
            connectWithOAuth(connector: connector)
        }
    }

    func connectWithAPIKey(connector: Connector) {
        guard let token = Self.promptSecret(
            title: "Подключить \(connector.title)",
            message: connector.id == "telegram"
                ? "Вставьте Telegram Bot Token. Бот должен быть администратором канала, куда нужно публиковать."
                : "Вставьте API key для \(connector.title)."
        ) else { return }
        auth.saveToken(token, for: connector.id)

        // Search APIs need one extra non-secret identifier next to the key.
        if connector.id == "google_search" {
            if let cx = Self.promptSecret(
                title: "Google Search Engine ID",
                message: "Вставьте Search Engine ID (cx) из programmablesearchengine.google.com."
            ), !cx.isEmpty {
                UserDefaults.standard.set(cx.trimmingCharacters(in: .whitespacesAndNewlines),
                                          forKey: "alakeya.google_search.cx")
            }
        }
        if connector.id == "yandex_search" {
            if let folder = Self.promptSecret(
                title: "Yandex Cloud Folder ID",
                message: "Вставьте folder id каталога Yandex Cloud, в котором включён Search API."
            ), !folder.isEmpty {
                UserDefaults.standard.set(folder.trimmingCharacters(in: .whitespacesAndNewlines),
                                          forKey: "alakeya.yandex_search.folder")
            }
        }

        setConnected(
            connectorID: connector.id,
            connectedEmail: connector.id == "telegram" ? "Bot API" : "API key"
        )
    }

    func connectWithOAuth(connector: Connector) {
        let clientID = oauthClientID(for: connector.id)
        guard clientID != nil else {
            let state = ConnectorConnectionState(
                connectorID: connector.id,
                status: .needsAuth,
                connectedEmail: nil,
                errorMessage: """
                Для \(connector.title) нужен OAuth client id, настроенный разработчиком приложения. \
                Пользователь не должен вводить секреты вручную. Добавьте client id в UserDefaults или окружение, \
                затем повторите подключение.
                """
            )
            states[connector.id] = state
            auth.saveState(state)
            objectWillChange.send()
            return
        }

        // Full OAuth callback exchange is implemented in the next runtime layer.
        // Until the app has provider client IDs and redirect handling wired in,
        // keep the state explicit and non-stub so the UI explains the blocker.
        let state = ConnectorConnectionState(
            connectorID: connector.id,
            status: .needsAuth,
            connectedEmail: nil,
            errorMessage: "OAuth для \(connector.title) ожидает callback alakeya://oauth/callback. Client id найден, нужен обмен authorization code на token."
        )
        states[connector.id] = state
        auth.saveState(state)
        objectWillChange.send()
    }

    func disconnect(connectorID: String) {
        auth.deleteToken(for: connectorID)
        auth.removeState(for: connectorID)
        states.removeValue(forKey: connectorID)
        objectWillChange.send()
    }

    func testConnection(connectorID: String) async -> String {
        guard let connector = connectors.first(where: { $0.id == connectorID }) else {
            return "Коннектор не найден."
        }
        switch connector.authType {
        case .none:
            return "Локальный коннектор доступен."
        case .apiKey:
            return auth.hasToken(for: connectorID)
                ? "\(connector.title): ключ сохранён в Keychain."
                : "\(connector.title): ключ не найден."
        case .oauth2:
            return auth.hasToken(for: connectorID)
                ? "\(connector.title): токен сохранён в Keychain."
                : "\(connector.title): OAuth токен не найден."
        }
    }

    private func setConnected(connectorID: String, connectedEmail: String?) {
        let state = ConnectorConnectionState(
            connectorID: connectorID,
            status: .connected,
            connectedEmail: connectedEmail,
            errorMessage: nil,
            lastConnected: Date()
        )
        states[connectorID] = state
        auth.saveState(state)
        objectWillChange.send()
    }

    private func oauthClientID(for connectorID: String) -> String? {
        let key: String
        switch connectorID {
        case "vk": key = "alakeya.oauth.vk.client_id"
        case "instagram": key = "alakeya.oauth.meta.client_id"
        default:
            if connectorID.hasPrefix("google_") || connectorID == "gmail" {
                key = "alakeya.oauth.google.client_id"
            } else {
                key = "alakeya.oauth.\(connectorID).client_id"
            }
        }
        if let value = UserDefaults.standard.string(forKey: key), !value.isEmpty { return value }
        let envKey = key
            .replacingOccurrences(of: "alakeya.oauth.", with: "ALAKEYA_OAUTH_")
            .replacingOccurrences(of: ".client_id", with: "_CLIENT_ID")
            .replacingOccurrences(of: ".", with: "_")
            .uppercased()
        return ProcessInfo.processInfo.environment[envKey]
    }

    private static func promptSecret(title: String, message: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        input.placeholderString = "token"
        alert.accessoryView = input
        alert.addButton(withTitle: "Подключить")
        alert.addButton(withTitle: "Отмена")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        let value = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    // MARK: - System prompt snippet

    func connectorSystemPrompt() -> String {
        let enabled = connectors.filter { $0.isEnabled && status(for: $0.id) == .connected }
        guard !enabled.isEmpty else { return "" }
        let names = enabled.map { $0.title }.joined(separator: ", ")
        return """
        ## Активные коннекторы
        Подключено: \(names).
        Используй коннекторы только когда они нужны для выполнения задачи.
        Для email, постов и документов — всегда создавай черновик сначала, потом предлагай отправить/опубликовать.
        Всегда запрашивай подтверждение перед отправкой, публикацией, удалением, обновлением файлов и событий.
        Не изобретай подключённые аккаунты. Если коннектор не подключён, предложи ручной черновик.
        """
    }

    // MARK: - Built-in connectors

    private static func builtInConnectors() -> [Connector] {
        [
            // ── Google ──────────────────────────────────────────
            Connector(
                id: "gmail", title: "Gmail",
                description: "Поиск, чтение и отправка писем через Gmail API.",
                category: .google, iconName: "envelope.fill", authType: .oauth2,
                permissions: [
                    .init(id: "gmail.readonly", title: "Читать письма", description: "Поиск и чтение входящих.", oauthScope: "https://www.googleapis.com/auth/gmail.readonly", risk: .low, isRequired: false),
                    .init(id: "gmail.compose", title: "Создавать черновики", description: "Создание черновиков писем.", oauthScope: "https://www.googleapis.com/auth/gmail.compose", risk: .medium, isRequired: true),
                    .init(id: "gmail.send", title: "Отправлять письма", description: "Отправка писем от вашего имени. ⚠️ Высокий риск.", oauthScope: "https://www.googleapis.com/auth/gmail.send", risk: .high, isRequired: false),
                ],
                availableTools: ["gmail_search","gmail_read","gmail_create_draft","gmail_send_draft","gmail_send_email"],
                isEnabled: true
            ),
            Connector(
                id: "google_drive", title: "Google Drive",
                description: "Поиск, чтение и загрузка файлов на Google Drive.",
                category: .google, iconName: "externaldrive.fill", authType: .oauth2,
                permissions: [
                    .init(id: "drive.readonly", title: "Читать файлы", description: "Просмотр и скачивание файлов.", oauthScope: "https://www.googleapis.com/auth/drive.readonly", risk: .low, isRequired: true),
                    .init(id: "drive.file", title: "Управлять файлами", description: "Создание и загрузка файлов.", oauthScope: "https://www.googleapis.com/auth/drive.file", risk: .medium, isRequired: false),
                ],
                availableTools: ["drive_search","drive_read_file","drive_upload_file","drive_create_folder"],
                isEnabled: true
            ),
            Connector(
                id: "google_docs", title: "Google Docs",
                description: "Создание и редактирование документов Google.",
                category: .google, iconName: "doc.text.fill", authType: .oauth2,
                permissions: [
                    .init(id: "docs.readonly", title: "Читать документы", description: "Просмотр документов.", oauthScope: "https://www.googleapis.com/auth/documents.readonly", risk: .low, isRequired: true),
                    .init(id: "docs.edit", title: "Редактировать документы", description: "Изменение содержимого. ⚠️ Высокий риск.", oauthScope: "https://www.googleapis.com/auth/documents", risk: .high, isRequired: false),
                ],
                availableTools: ["docs_create","docs_read","docs_update"],
                isEnabled: true
            ),
            Connector(
                id: "google_sheets", title: "Google Sheets",
                description: "Чтение, добавление и экспорт данных из таблиц Google.",
                category: .spreadsheets, iconName: "tablecells.fill", authType: .oauth2,
                permissions: [
                    .init(id: "sheets.readonly", title: "Читать таблицы", description: "Чтение ячеек и диапазонов.", oauthScope: "https://www.googleapis.com/auth/spreadsheets.readonly", risk: .low, isRequired: true),
                    .init(id: "sheets.edit", title: "Изменять таблицы", description: "Запись данных в таблицы. ⚠️ Высокий риск.", oauthScope: "https://www.googleapis.com/auth/spreadsheets", risk: .high, isRequired: false),
                ],
                availableTools: ["sheets_read","sheets_append_row","sheets_update_range","sheets_create","sheets_export_csv"],
                isEnabled: true
            ),
            Connector(
                id: "google_calendar", title: "Google Calendar",
                description: "Просмотр, создание и управление событиями.",
                category: .calendar, iconName: "calendar", authType: .oauth2,
                permissions: [
                    .init(id: "calendar.readonly", title: "Читать события", description: "Просмотр событий и встреч.", oauthScope: "https://www.googleapis.com/auth/calendar.readonly", risk: .low, isRequired: true),
                    .init(id: "calendar.events", title: "Управлять событиями", description: "Создание, изменение, удаление. ⚠️ Высокий риск.", oauthScope: "https://www.googleapis.com/auth/calendar.events", risk: .high, isRequired: false),
                ],
                availableTools: ["calendar_search_events","calendar_create_event","calendar_update_event","calendar_delete_event"],
                isEnabled: true
            ),
            // ── Social ──────────────────────────────────────────
            Connector(
                id: "telegram", title: "Telegram",
                description: "Создание черновиков и публикация постов в Telegram-каналах через Bot API.",
                category: .social, iconName: "paperplane.fill", authType: .apiKey,
                permissions: [
                    .init(id: "telegram.post", title: "Публиковать посты", description: "Отправка сообщений в канал. ⚠️ Высокий риск.", oauthScope: "bot_token", risk: .high, isRequired: true),
                ],
                availableTools: ["telegram_create_post_draft","telegram_publish_post","telegram_schedule_post"],
                isEnabled: true
            ),
            Connector(
                id: "vk", title: "ВКонтакте",
                description: "Создание черновиков и публикация постов ВКонтакте.",
                category: .social, iconName: "person.2.fill", authType: .oauth2,
                permissions: [
                    .init(id: "vk.wall", title: "Записи на стене", description: "Публикация записей. ⚠️ Высокий риск.", oauthScope: "wall", risk: .high, isRequired: true),
                ],
                availableTools: ["vk_create_post_draft","vk_publish_post","vk_schedule_post"],
                isEnabled: true
            ),
            Connector(
                id: "instagram", title: "Instagram",
                description: "Создание черновиков и публикация постов в Instagram Business.",
                category: .social, iconName: "camera.fill", authType: .oauth2,
                permissions: [
                    .init(id: "instagram.content", title: "Публикации", description: "Создание и публикация постов. ⚠️ Высокий риск.", oauthScope: "instagram_content_publish", risk: .high, isRequired: true),
                ],
                availableTools: ["instagram_create_post_draft","instagram_publish_post","instagram_schedule_post"],
                isEnabled: true
            ),
            // ── Local files ─────────────────────────────────────
            Connector(
                id: "local_spreadsheet", title: "Excel / CSV (локальные)",
                description: "Импорт, анализ, очистка и экспорт файлов Excel и CSV без внешних API.",
                category: .files, iconName: "tablecells", authType: .none,
                permissions: [
                    .init(id: "files.read", title: "Читать файлы", description: "Открытие локальных файлов.", oauthScope: "", risk: .low, isRequired: true),
                    .init(id: "files.write", title: "Сохранять файлы", description: "Экспорт и сохранение таблиц.", oauthScope: "", risk: .medium, isRequired: false),
                ],
                availableTools: [
                    "spreadsheet_import_file","spreadsheet_read","spreadsheet_detect_columns",
                    "spreadsheet_clean_data","spreadsheet_append_rows","spreadsheet_export_csv",
                    "spreadsheet_export_xlsx","spreadsheet_create_client_leads_table",
                ],
                isEnabled: true
            ),
            // ── Search APIs (лид-парсер и исследования) ─────────
            Connector(
                id: "google_search", title: "Google Поиск (API)",
                description: "Google Custom Search API: поиск лидов и исследований без капчи. Нужны API key и Search Engine ID (cx) — cx сохраняется отдельно.",
                category: .custom, iconName: "magnifyingglass", authType: .apiKey,
                permissions: [
                    .init(id: "google_search.query", title: "Поисковые запросы", description: "Чтение результатов поиска Google.", oauthScope: "", risk: .low, isRequired: true),
                ],
                availableTools: ["search_internet", "find_business_leads"],
                isEnabled: true
            ),
            Connector(
                id: "yandex_search", title: "Яндекс Поиск (API)",
                description: "Yandex Search API (XML): официальный поиск Яндекса для парсера лидов. Нужны API key и folder id из Yandex Cloud.",
                category: .custom, iconName: "magnifyingglass.circle", authType: .apiKey,
                permissions: [
                    .init(id: "yandex_search.query", title: "Поисковые запросы", description: "Чтение результатов поиска Яндекса.", oauthScope: "", risk: .low, isRequired: true),
                ],
                availableTools: ["search_internet", "find_business_leads"],
                isEnabled: true
            ),
            // ── Custom API ──────────────────────────────────────
            Connector(
                id: "custom_api", title: "Кастомный API",
                description: "Подключение к собственному REST API с заголовком авторизации.",
                category: .custom, iconName: "link", authType: .apiKey,
                permissions: [
                    .init(id: "custom.read", title: "GET-запросы", description: "Чтение данных.", oauthScope: "", risk: .low, isRequired: false),
                    .init(id: "custom.write", title: "POST/PUT/DELETE", description: "Запись данных. ⚠️ Высокий риск.", oauthScope: "", risk: .high, isRequired: false),
                ],
                availableTools: [],
                isEnabled: false
            ),
        ]
    }
}
