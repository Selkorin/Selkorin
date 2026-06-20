import Foundation

// ============================================================
// DocumentTools.swift — ToolHandler for document export tools.
// export_pdf, export_docx, export_csv, export_markdown.
// ============================================================

struct DocumentTools: ToolHandler {
    var toolNames: [String] { Self.allNames }
    var toolSchemas: [[String: Any]] { Self.schemas }

    func makeAction(toolName: String, args: [String: String]) -> Action? {
        switch toolName {
        case "export_pdf":
            let title = args["title"] ?? "Отчёт"
            return Action(type: .exportPDF,
                          title: "Создать PDF",
                          description: "Генерирую PDF-документ «\(title)» и сохраняю в Downloads.",
                          target: title, scope: "Документы", reversible: true, args: args)
        case "export_docx":
            let title = args["title"] ?? "Документ"
            return Action(type: .exportDocx,
                          title: "Создать Word (DOCX)",
                          description: "Генерирую DOCX-документ «\(title)».",
                          target: title, scope: "Документы", reversible: true, args: args)
        case "export_csv":
            let title = args["title"] ?? "Таблица"
            return Action(type: .exportCSV,
                          title: "Создать CSV",
                          description: "Сохраняю «\(title)» в CSV.",
                          target: title, scope: "Документы", reversible: true, args: args)
        case "export_markdown":
            let title = args["title"] ?? "Файл"
            return Action(type: .exportMarkdown,
                          title: "Создать Markdown",
                          description: "Сохраняю «\(title)» как .md файл.",
                          target: title, scope: "Документы", reversible: true, args: args)
        default:
            return nil
        }
    }

    private static let allNames = ["export_pdf", "export_docx", "export_csv", "export_markdown"]

    // MARK: - Schemas

    private static let schemas: [[String: Any]] = [
        fn("export_pdf",
           "Создать PDF-файл и сохранить в ~/Downloads/. Можно передать готовый текст или структуру отчёта. Файл откроется в Finder. НЕ требует подтверждения.",
           [
               "title":    str("Заголовок документа"),
               "content":  str("Основной текст или Markdown-контент для PDF"),
               "sections_json": str("JSON-массив [{heading, body, bullets[], table?}] (необязательно)"),
               "sources_json":  str("JSON-массив [{title, url, domain}] для раздела источников (необязательно)"),
           ],
           ["title", "content"]),
        fn("export_docx",
           "Создать Word DOCX или RTF-файл. Если python3 + python-docx недоступен, создаётся RTF (открывается в Word/Pages). Сохраняет в ~/Downloads/.",
           [
               "title":    str("Заголовок документа"),
               "content":  str("Основной текст"),
               "sections_json": str("JSON-массив секций (необязательно)"),
           ],
           ["title", "content"]),
        fn("export_csv",
           "Создать CSV-файл из табличных данных. Сохраняет в ~/Downloads/.",
           [
               "title":    str("Название файла/таблицы"),
               "headers_json": str("JSON-массив заголовков столбцов, например [\"Название\",\"Телефон\",\"Адрес\"]"),
               "rows_json":    str("JSON двумерный массив строк [[\"...\",\"...\"],[...]]"),
           ],
           ["title", "headers_json", "rows_json"]),
        fn("export_markdown",
           "Сохранить текст как .md файл в ~/Downloads/.",
           [
               "title":   str("Имя файла (без расширения)"),
               "content": str("Markdown-контент"),
           ],
           ["title", "content"]),
    ]

    private static func fn(_ name: String, _ description: String,
                            _ props: [String: Any], _ required: [String]) -> [String: Any] {
        ["type": "function",
         "function": ["name": name, "description": description,
                      "parameters": ["type": "object", "properties": props,
                                     "required": required, "additionalProperties": false]]]
    }
    private static func str(_ d: String) -> [String: Any] { ["type": "string", "description": d] }
}
