import Foundation

// ============================================================
// ConnectorTool.swift — ToolHandler for all connector tools.
// Schemas describe capabilities; real API calls are TODO stubs.
// ============================================================

struct ConnectorTools: ToolHandler {

    var toolNames: [String] { Self.allToolNames }

    var toolSchemas: [[String: Any]] { Self.schemas }

    func makeAction(toolName: String, args: [String: String]) -> Action? {
        let (title, description, type) = Self.meta(for: toolName, args: args)
        return Action(
            type: type,
            title: title,
            description: description,
            target: args["connector_id"] ?? args["id"] ?? toolName,
            scope: "Коннекторы",
            reversible: type != .connectorSend,
            args: args
        )
    }

    // MARK: - All tool names

    private static let allToolNames: [String] = [
        // Gmail
        "gmail_search", "gmail_read", "gmail_create_draft", "gmail_send_draft", "gmail_send_email",
        // Drive
        "drive_search", "drive_read_file", "drive_upload_file", "drive_create_folder",
        // Docs
        "docs_create", "docs_read", "docs_update",
        // Sheets
        "sheets_read", "sheets_append_row", "sheets_update_range", "sheets_create", "sheets_export_csv",
        // Calendar
        "calendar_search_events", "calendar_create_event", "calendar_update_event", "calendar_delete_event",
        // Telegram
        "telegram_create_post_draft", "telegram_publish_post", "telegram_schedule_post",
        // VK
        "vk_create_post_draft", "vk_publish_post", "vk_schedule_post",
        // Instagram
        "instagram_create_post_draft", "instagram_publish_post", "instagram_schedule_post",
        // Local Spreadsheet
        "spreadsheet_import_file", "spreadsheet_read", "spreadsheet_detect_columns",
        "spreadsheet_clean_data", "spreadsheet_append_rows", "spreadsheet_export_csv",
        "spreadsheet_export_xlsx", "spreadsheet_create_client_leads_table",
    ]

    // MARK: - Action type + display metadata per tool

    private static func meta(for toolName: String, args: [String: String]) -> (String, String, ActionType) {
        switch toolName {
        // ── Gmail ──
        case "gmail_search":
            return ("Поиск писем", "Gmail: поиск «\(args["query"] ?? "")»", .connectorRead)
        case "gmail_read":
            return ("Читать письмо", "Gmail: читаю письмо \(args["id"] ?? "")", .connectorRead)
        case "gmail_create_draft":
            let to = args["to"] ?? ""; let subj = args["subject"] ?? ""
            return ("Черновик письма", "Gmail: черновик для \(to) — «\(subj)»", .connectorWrite)
        case "gmail_send_draft":
            return ("Отправить письмо", "Gmail: отправляю черновик \(args["draft_id"] ?? "").", .connectorSend)
        case "gmail_send_email":
            let to = args["to"] ?? ""
            return ("Отправить письмо", "Gmail: отправляю письмо → \(to). Подтвердите!", .connectorSend)

        // ── Google Drive ──
        case "drive_search":
            return ("Поиск на Drive", "Drive: ищу «\(args["query"] ?? "")»", .connectorRead)
        case "drive_read_file":
            return ("Читать файл", "Drive: читаю \(args["file_id"] ?? "")", .connectorRead)
        case "drive_upload_file":
            return ("Загрузить файл", "Drive: загружаю \(args["name"] ?? "")", .connectorWrite)
        case "drive_create_folder":
            return ("Создать папку", "Drive: создаю папку «\(args["name"] ?? "")»", .connectorWrite)

        // ── Google Docs ──
        case "docs_read":
            return ("Читать документ", "Docs: читаю \(args["doc_id"] ?? "")", .connectorRead)
        case "docs_create":
            return ("Создать документ", "Docs: создаю «\(args["title"] ?? "")»", .connectorWrite)
        case "docs_update":
            return ("Обновить документ", "Docs: изменяю \(args["doc_id"] ?? ""). Подтвердите!", .connectorSend)

        // ── Google Sheets ──
        case "sheets_read":
            return ("Читать таблицу", "Sheets: читаю \(args["spreadsheet_id"] ?? "") [\(args["range"] ?? "")]", .connectorRead)
        case "sheets_append_row":
            return ("Добавить строку", "Sheets: добавляю строку в \(args["spreadsheet_id"] ?? ""). Подтвердите!", .connectorSend)
        case "sheets_update_range":
            return ("Обновить диапазон", "Sheets: обновляю \(args["range"] ?? "") в \(args["spreadsheet_id"] ?? ""). Подтвердите!", .connectorSend)
        case "sheets_create":
            return ("Создать таблицу", "Sheets: создаю «\(args["title"] ?? "")»", .connectorWrite)
        case "sheets_export_csv":
            return ("Экспорт в CSV", "Sheets: экспортирую \(args["spreadsheet_id"] ?? "") в CSV", .connectorRead)

        // ── Google Calendar ──
        case "calendar_search_events":
            return ("Поиск событий", "Calendar: ищу события \(args["date_from"] ?? "") – \(args["date_to"] ?? "")", .connectorRead)
        case "calendar_create_event":
            return ("Создать событие", "Calendar: создаю «\(args["title"] ?? "")» \(args["start"] ?? ""). Подтвердите!", .connectorSend)
        case "calendar_update_event":
            return ("Изменить событие", "Calendar: изменяю \(args["event_id"] ?? ""). Подтвердите!", .connectorSend)
        case "calendar_delete_event":
            return ("Удалить событие", "Calendar: удаляю \(args["event_id"] ?? ""). Подтвердите!", .connectorSend)

        // ── Telegram ──
        case "telegram_create_post_draft":
            return ("Черновик поста", "Telegram: создаю черновик для @\(args["channel"] ?? "")", .connectorWrite)
        case "telegram_publish_post":
            return ("Опубликовать пост", "Telegram: публикую в @\(args["channel"] ?? ""). Подтвердите!", .connectorSend)
        case "telegram_schedule_post":
            return ("Запланировать пост", "Telegram: планирую в @\(args["channel"] ?? "") на \(args["scheduled_at"] ?? "")", .connectorWrite)

        // ── VK ──
        case "vk_create_post_draft":
            return ("Черновик ВК", "VK: создаю черновик для \(args["owner_id"] ?? "")", .connectorWrite)
        case "vk_publish_post":
            return ("Опубликовать ВК", "VK: публикую пост. Подтвердите!", .connectorSend)
        case "vk_schedule_post":
            return ("Запланировать ВК", "VK: планирую пост на \(args["scheduled_at"] ?? "")", .connectorWrite)

        // ── Instagram ──
        case "instagram_create_post_draft":
            return ("Черновик Instagram", "Instagram: создаю черновик публикации", .connectorWrite)
        case "instagram_publish_post":
            return ("Опубликовать Instagram", "Instagram: публикую пост. Подтвердите!", .connectorSend)
        case "instagram_schedule_post":
            return ("Запланировать Instagram", "Instagram: планирую пост на \(args["scheduled_at"] ?? "")", .connectorWrite)

        // ── Local Spreadsheet ──
        case "spreadsheet_import_file":
            return ("Импортировать файл", "Таблица: импортирую \(args["path"] ?? "")", .connectorRead)
        case "spreadsheet_read":
            return ("Читать таблицу", "Таблица: читаю \(args["path"] ?? "") [\(args["range"] ?? "все")]", .connectorRead)
        case "spreadsheet_detect_columns":
            return ("Определить колонки", "Таблица: анализирую структуру \(args["path"] ?? "")", .connectorRead)
        case "spreadsheet_clean_data":
            return ("Очистить данные", "Таблица: очищаю данные в \(args["path"] ?? "")", .connectorWrite)
        case "spreadsheet_append_rows":
            return ("Добавить строки", "Таблица: добавляю строки в \(args["path"] ?? "")", .connectorWrite)
        case "spreadsheet_export_csv":
            return ("Экспорт CSV", "Таблица: экспортирую в CSV → \(args["output_path"] ?? "")", .connectorWrite)
        case "spreadsheet_export_xlsx":
            return ("Экспорт XLSX", "Таблица: экспортирую в Excel → \(args["output_path"] ?? "")", .connectorWrite)
        case "spreadsheet_create_client_leads_table":
            return ("Таблица лидов", "Таблица: создаю таблицу клиентов → \(args["output_path"] ?? "")", .connectorWrite)

        default:
            return (toolName, toolName, .connectorRead)
        }
    }

    // MARK: - Schemas

    private static let schemas: [[String: Any]] = [
        // ── Gmail ──────────────────────────────────────────────
        fn("gmail_search",
           "Поиск писем в Gmail. Перед отправкой письма всегда создай черновик.",
           ["query": str("Поисковый запрос Gmail (from:, to:, subject:, after:, etc.)"),
            "max_results": int("Максимум результатов, по умолчанию 10")],
           ["query"]),
        fn("gmail_read",
           "Прочитать письмо по ID (из gmail_search).",
           ["id": str("ID письма"), "format": str("full / summary / body_only")],
           ["id"]),
        fn("gmail_create_draft",
           "Создать черновик письма. ВСЕГДА создавай черновик перед отправкой — не вызывай send_email напрямую.",
           ["to": str("Email получателя"),
            "subject": str("Тема письма"),
            "body": str("Текст письма (plain text или HTML)"),
            "cc": str("Копия (необязательно)"),
            "reply_to_id": str("ID письма для ответа (необязательно)")],
           ["to", "subject", "body"]),
        fn("gmail_send_draft",
           "Отправить черновик. ТРЕБУЕТ подтверждения пользователя. Перед вызовом покажи черновик.",
           ["draft_id": str("ID черновика из gmail_create_draft")],
           ["draft_id"]),
        fn("gmail_send_email",
           "Отправить письмо напрямую. ТРЕБУЕТ подтверждения. Предпочти create_draft + send_draft.",
           ["to": str("Email получателя"),
            "subject": str("Тема"),
            "body": str("Текст письма")],
           ["to", "subject", "body"]),

        // ── Google Drive ────────────────────────────────────────
        fn("drive_search",
           "Поиск файлов на Google Drive.",
           ["query": str("Поисковый запрос (имя, MIME-тип, папка)"),
            "max_results": int("Максимум, по умолчанию 10")],
           ["query"]),
        fn("drive_read_file",
           "Прочитать содержимое файла с Drive (документы, таблицы, TXT, PDF).",
           ["file_id": str("ID файла"), "format": str("text / json / markdown")],
           ["file_id"]),
        fn("drive_upload_file",
           "Загрузить файл на Drive. ТРЕБУЕТ подтверждения.",
           ["name": str("Имя файла"),
            "content": str("Содержимое файла (текст)"),
            "folder_id": str("ID папки (необязательно)"),
            "mime_type": str("MIME-тип, например text/plain")],
           ["name", "content"]),
        fn("drive_create_folder",
           "Создать папку на Drive.",
           ["name": str("Имя папки"),
            "parent_id": str("ID родительской папки (необязательно)")],
           ["name"]),

        // ── Google Docs ─────────────────────────────────────────
        fn("docs_create",
           "Создать новый документ Google Docs.",
           ["title": str("Заголовок документа"),
            "content": str("Начальный текст или Markdown")],
           ["title"]),
        fn("docs_read",
           "Прочитать документ Google Docs по ID.",
           ["doc_id": str("ID документа")],
           ["doc_id"]),
        fn("docs_update",
           "Обновить документ. ТРЕБУЕТ подтверждения — данные будут изменены.",
           ["doc_id": str("ID документа"),
            "content": str("Новый полный текст"),
            "append": bool("true = добавить в конец, false = перезаписать")],
           ["doc_id", "content"]),

        // ── Google Sheets ───────────────────────────────────────
        fn("sheets_read",
           "Прочитать данные из Google Sheets.",
           ["spreadsheet_id": str("ID таблицы"),
            "range": str("Диапазон A1-нотация, например Sheet1!A1:Z100"),
            "format": str("json / csv")],
           ["spreadsheet_id"]),
        fn("sheets_append_row",
           "Добавить строку в таблицу. ТРЕБУЕТ подтверждения.",
           ["spreadsheet_id": str("ID таблицы"),
            "sheet": str("Имя листа, по умолчанию Sheet1"),
            "values": str("JSON массив значений строки")],
           ["spreadsheet_id", "values"]),
        fn("sheets_update_range",
           "Обновить диапазон ячеек. ТРЕБУЕТ подтверждения — данные будут изменены.",
           ["spreadsheet_id": str("ID таблицы"),
            "range": str("Диапазон A1-нотация"),
            "values": str("JSON двумерный массив")],
           ["spreadsheet_id", "range", "values"]),
        fn("sheets_create",
           "Создать новую Google-таблицу.",
           ["title": str("Название таблицы"),
            "headers": str("JSON массив заголовков столбцов (необязательно)")],
           ["title"]),
        fn("sheets_export_csv",
           "Экспортировать лист в CSV текст.",
           ["spreadsheet_id": str("ID таблицы"),
            "sheet": str("Имя листа")],
           ["spreadsheet_id"]),

        // ── Google Calendar ─────────────────────────────────────
        fn("calendar_search_events",
           "Поиск событий в Google Calendar.",
           ["date_from": str("ISO-8601, например 2025-01-01"),
            "date_to": str("ISO-8601"),
            "query": str("Поисковый запрос по названию"),
            "calendar_id": str("ID календаря, по умолчанию primary")],
           []),
        fn("calendar_create_event",
           "Создать событие. ТРЕБУЕТ подтверждения.",
           ["title": str("Название"),
            "start": str("ISO-8601 дата-время"),
            "end": str("ISO-8601 дата-время"),
            "description": str("Описание"),
            "location": str("Место"),
            "attendees": str("JSON массив email участников"),
            "calendar_id": str("ID календаря")],
           ["title", "start", "end"]),
        fn("calendar_update_event",
           "Изменить событие. ТРЕБУЕТ подтверждения.",
           ["event_id": str("ID события"),
            "title": str("Новое название"),
            "start": str("Новое начало ISO-8601"),
            "end": str("Новый конец ISO-8601"),
            "description": str("Новое описание"),
            "calendar_id": str("ID календаря")],
           ["event_id"]),
        fn("calendar_delete_event",
           "Удалить событие. ТРЕБУЕТ подтверждения — действие необратимо.",
           ["event_id": str("ID события"),
            "calendar_id": str("ID календаря")],
           ["event_id"]),

        // ── Telegram ────────────────────────────────────────────
        fn("telegram_create_post_draft",
           "Создать черновик поста для Telegram-канала. ВСЕГДА создавай черновик перед публикацией.",
           ["channel": str("Username канала без @ или chat_id"),
            "text": str("Текст поста, поддерживается Markdown"),
            "image_url": str("URL изображения (необязательно)"),
            "parse_mode": str("MarkdownV2 / HTML / none")],
           ["channel", "text"]),
        fn("telegram_publish_post",
           "Опубликовать пост в Telegram-канале. ТРЕБУЕТ подтверждения. Сначала покажи черновик.",
           ["channel": str("Username или chat_id"),
            "text": str("Текст поста"),
            "image_url": str("URL изображения (необязательно)"),
            "parse_mode": str("MarkdownV2 / HTML")],
           ["channel", "text"]),
        fn("telegram_schedule_post",
           "Запланировать пост в Telegram (Telegram Premium / сторонний сервис).",
           ["channel": str("Username или chat_id"),
            "text": str("Текст поста"),
            "scheduled_at": str("ISO-8601 дата-время"),
            "image_url": str("URL изображения")],
           ["channel", "text", "scheduled_at"]),

        // ── VK ──────────────────────────────────────────────────
        fn("vk_create_post_draft",
           "Создать черновик поста ВКонтакте. Всегда показывай до публикации.",
           ["owner_id": str("ID группы или пользователя (отрицательный для группы)"),
            "text": str("Текст записи"),
            "attachments": str("URL или media-объекты через запятую")],
           ["owner_id", "text"]),
        fn("vk_publish_post",
           "Опубликовать запись ВКонтакте. ТРЕБУЕТ подтверждения.",
           ["owner_id": str("ID владельца"),
            "text": str("Текст записи"),
            "attachments": str("Вложения"),
            "from_group": bool("true = от имени группы")],
           ["owner_id", "text"]),
        fn("vk_schedule_post",
           "Запланировать публикацию ВКонтакте.",
           ["owner_id": str("ID владельца"),
            "text": str("Текст"),
            "scheduled_at": str("ISO-8601 дата-время")],
           ["owner_id", "text", "scheduled_at"]),

        // ── Instagram ───────────────────────────────────────────
        fn("instagram_create_post_draft",
           "Создать черновик поста Instagram Business. Всегда показывай до публикации.",
           ["caption": str("Текст поста с хэштегами"),
            "image_url": str("URL изображения (обязательно для Instagram)"),
            "media_type": str("IMAGE / VIDEO / CAROUSEL")],
           ["caption", "image_url"]),
        fn("instagram_publish_post",
           "Опубликовать пост Instagram. ТРЕБУЕТ подтверждения.",
           ["caption": str("Текст поста"),
            "image_url": str("URL изображения"),
            "media_type": str("IMAGE / VIDEO")],
           ["caption", "image_url"]),
        fn("instagram_schedule_post",
           "Запланировать публикацию Instagram.",
           ["caption": str("Текст"),
            "image_url": str("URL изображения"),
            "scheduled_at": str("ISO-8601 дата-время")],
           ["caption", "image_url", "scheduled_at"]),

        // ── Local Spreadsheet ────────────────────────────────────
        fn("spreadsheet_import_file",
           "Импортировать локальный файл Excel (.xlsx) или CSV для анализа.",
           ["path": str("Абсолютный путь к файлу"),
            "encoding": str("Кодировка, по умолчанию utf-8"),
            "delimiter": str("Разделитель CSV, по умолчанию ,")],
           ["path"]),
        fn("spreadsheet_read",
           "Прочитать данные из импортированного файла.",
           ["path": str("Путь к файлу"),
            "range": str("Диапазон строк/колонок, например 1:100 или A:E"),
            "sheet": str("Имя листа для XLSX")],
           ["path"]),
        fn("spreadsheet_detect_columns",
           "Определить структуру колонок: типы данных, заполненность, уникальность.",
           ["path": str("Путь к файлу")],
           ["path"]),
        fn("spreadsheet_clean_data",
           "Очистить данные: убрать дубликаты, пустые строки, исправить форматы.",
           ["path": str("Путь к файлу"),
            "rules": str("JSON список правил очистки (необязательно)")],
           ["path"]),
        fn("spreadsheet_append_rows",
           "Добавить строки в конец файла.",
           ["path": str("Путь к файлу"),
            "rows": str("JSON массив строк для добавления")],
           ["path", "rows"]),
        fn("spreadsheet_export_csv",
           "Сохранить данные как CSV-файл.",
           ["path": str("Путь к исходному файлу"),
            "output_path": str("Путь для сохранения CSV"),
            "sheet": str("Имя листа для XLSX"),
            "encoding": str("Кодировка, по умолчанию utf-8")],
           ["path", "output_path"]),
        fn("spreadsheet_export_xlsx",
           "Сохранить данные как Excel (.xlsx).",
           ["path": str("Путь к исходному файлу"),
            "output_path": str("Путь для сохранения XLSX")],
           ["path", "output_path"]),
        fn("spreadsheet_create_client_leads_table",
           "Создать структурированную таблицу лидов/клиентов из неструктурированных данных.",
           ["path": str("Путь к исходному файлу"),
            "output_path": str("Путь для сохранения итоговой таблицы"),
            "columns": str("JSON список нужных колонок, например ['Имя','Телефон','Email']")],
           ["path", "output_path"]),
    ]

    // MARK: - Schema builders

    private static func fn(
        _ name: String, _ description: String,
        _ properties: [String: Any], _ required: [String]
    ) -> [String: Any] {
        ["type": "function",
         "function": ["name": name, "description": description,
                      "parameters": ["type": "object", "properties": properties,
                                     "required": required, "additionalProperties": false]]]
    }
    private static func str(_ d: String) -> [String: Any] { ["type": "string", "description": d] }
    private static func int(_ d: String) -> [String: Any] { ["type": "integer", "description": d] }
    private static func bool(_ d: String) -> [String: Any] { ["type": "boolean", "description": d] }
}
