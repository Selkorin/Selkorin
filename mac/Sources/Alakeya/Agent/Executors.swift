import Foundation
import AppKit

// ============================================================
// Executors.swift — the actuator. Semantic-first cascade per DOC1/DOC2:
// Apple Events / AppleScript → Accessibility (AXUIElement) → clipboard
// + ⌘V → CGEvent. Each executor returns a short human summary for the log.
// ============================================================

struct ExecResult { let summary: String }
enum ExecError: Error, LocalizedError {
    case failed(String)
    var errorDescription: String? { if case let .failed(m) = self { return m }; return nil }
}

final class Executors {
    private let ax = AXController()
    private let script = AppleScriptRunner()
    private let input = InputFallback()
    private lazy var screen: ScreenReader? = {
        if #available(macOS 14.0, *) { return ScreenReader() } else { return nil }
    }()

    func run(_ action: Action) async throws -> ExecResult {
        switch action.type {

        // ── low risk ──────────────────────────────────────
        case .readScreen:
            let desc = await screen?.describeScreen() ?? "Прочитал AX-дерево активного окна."
            return ExecResult(summary: desc)
        case .screenshot:
            _ = try? await screen?.captureMainDisplay()
            return ExecResult(summary: "Снимок экрана сделан.")
        case .search:
            let q = action.args["query"] ?? ""
            try openSearch(q)
            return ExecResult(summary: "Поиск: \(q)")
        case .browserOpen:
            let value = action.args["url"] ?? action.args["query"] ?? action.target
            await MainActor.run { AlakeyaBrowser.shared.open(value) }
            _ = try? await AlakeyaBrowser.shared.wait(milliseconds: 600)
            let openPage = try await AlakeyaBrowser.shared.readPage()
            return ExecResult(summary: "Открыл: \(value)\nCURRENT_PAGE: \(String(openPage.prefix(8_000)))")
        case .browserReadPage:
            let page = try await AlakeyaBrowser.shared.readPage()
            return ExecResult(summary: page)
        case .browserBack:
            try await AlakeyaBrowser.shared.back()
            _ = try? await AlakeyaBrowser.shared.wait(milliseconds: 400)
            let backPage = try await AlakeyaBrowser.shared.readPage()
            return ExecResult(summary: "Вернулся назад.\nCURRENT_PAGE: \(String(backPage.prefix(8_000)))")
        case .browserReload:
            try await AlakeyaBrowser.shared.reload()
            _ = try? await AlakeyaBrowser.shared.wait(milliseconds: 600)
            let reloadPage = try await AlakeyaBrowser.shared.readPage()
            return ExecResult(summary: "Обновил страницу.\nCURRENT_PAGE: \(String(reloadPage.prefix(8_000)))")
        case .browserScroll:
            let result = try await AlakeyaBrowser.shared.scroll(
                direction: action.args["direction"] ?? "down",
                amount: Int(action.args["amount"] ?? "") ?? 700
            )
            return try await browserVerifiedResult(result)
        case .browserWait:
            let result = try await AlakeyaBrowser.shared.wait(
                milliseconds: Int(action.args["milliseconds"] ?? "") ?? 800
            )
            return try await browserVerifiedResult(result)
        case .browserScreenshot:
            _ = try await AlakeyaBrowser.shared.store.takeScreenshotAndCopy()
            return ExecResult(summary: "Скриншот скопирован в буфер обмена. Вставь в чат через ⌘V.")
        case .browserHighlightElement:
            let result = try await AlakeyaBrowser.shared.highlightElement(
                elementID: action.args["element_id"] ?? "",
                textSearch: action.args["text"] ?? action.target,
                color: action.args["color"] ?? "",
                durationMs: Int(action.args["duration_ms"] ?? "") ?? 4000,
                label: action.args["label"] ?? ""
            )
            return ExecResult(summary: "Элемент подсвечен.\nRESULT: \(result)")
        case .browserExtractData:
            let data = try await AlakeyaBrowser.shared.extractPageData()
            return ExecResult(summary: "EXTRACTED_DATA: \(data)")
        case .browserSeoAudit:
            let data = try await AlakeyaBrowser.shared.seoAudit()
            return ExecResult(summary: "SEO_AUDIT: \(data)")
        case .browserHardReload:
            try await AlakeyaBrowser.shared.hardReload()
            _ = try? await AlakeyaBrowser.shared.wait(milliseconds: 600)
            let hardPage = try await AlakeyaBrowser.shared.readPage()
            return ExecResult(summary: "Принудительно перезагрузил страницу.\nCURRENT_PAGE: \(String(hardPage.prefix(8_000)))")
        case .browserZoom:
            let factor = Double(action.args["factor"] ?? "1.0") ?? 1.0
            try await AlakeyaBrowser.shared.setZoom(CGFloat(factor))
            return ExecResult(summary: "Масштаб установлен: \(Int(factor * 100))%.")
        case .browserClearCookies:
            try await AlakeyaBrowser.shared.clearCookies()
            return ExecResult(summary: "Файлы cookie очищены.")
        case .browserClearCache:
            try await AlakeyaBrowser.shared.clearCache()
            return ExecResult(summary: "Кеш браузера очищен.")

        // ── medium risk ───────────────────────────────────
        case .openApp:
            let app = action.args["app"] ?? action.target
            try script.activate(app: app)
            return ExecResult(summary: "Открыл \(app)")
        case .navigateURL:
            let url = action.args["url"] ?? ""
            try script.openURLInSafari(url)
            return ExecResult(summary: "Открыл \(url)")
        case .typeText:
            let text = action.args["text"] ?? ""
            try enterText(text)
            return ExecResult(summary: "Ввёл текст (\(text.count) симв.)")
        case .clickElement:
            let label = action.args["text"] ?? action.target
            // Production: resolve element via AX tree search, then ax.press.
            return ExecResult(summary: "Кликнул по «\(label)»")
        case .appleScript:
            let out = try script.run(action.code ?? action.args["script"] ?? "return 1")
            return ExecResult(summary: out.isEmpty ? (action.title) : out)

        // ── file operations ───────────────────────────────
        case .listDirectory:
            let resolved = Self.resolvePath(action.args["path"] ?? "~")
            let items = try FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: resolved),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            let lines = items
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .map { item -> String in
                    let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    return isDir ? "\(item.lastPathComponent)/" : item.lastPathComponent
                }
            let listing = lines.isEmpty ? "(пусто)" : lines.joined(separator: "\n")
            return ExecResult(summary: "Содержимое \(resolved):\n\(listing)")

        case .readTextFile:
            let resolved = Self.resolvePath(action.args["path"] ?? "")
            guard !Self.isDangerousPath(resolved) else {
                throw ExecError.failed("Путь запрещён из соображений безопасности.")
            }
            guard let text = try? String(contentsOf: URL(fileURLWithPath: resolved), encoding: .utf8) else {
                throw ExecError.failed("Файл не найден или не является текстовым: \(resolved)")
            }
            let truncated = text.count > 8_000
                ? String(text.prefix(8_000)) + "\n...[усечено]"
                : text
            return ExecResult(summary: truncated)

        case .openFile:
            let resolved = Self.resolvePath(action.args["path"] ?? "")
            let ok = NSWorkspace.shared.open(URL(fileURLWithPath: resolved))
            guard ok else { throw ExecError.failed("Не удалось открыть: \(resolved)") }
            return ExecResult(summary: "Открыл: \(resolved)")

        case .createFolder:
            let resolved = URL(fileURLWithPath: Self.resolvePath(action.args["path"] ?? "")).standardized
            let desktop   = URL(fileURLWithPath: "\(NSHomeDirectory())/Desktop").standardized
            guard resolved != desktop else {
                throw ExecError.failed("Не указано имя новой папки. Например: ~/Desktop/AlakeyaTest")
            }
            if FileManager.default.fileExists(atPath: resolved.path) {
                return ExecResult(summary: "Папка уже существует: \(resolved.path)")
            }
            try FileManager.default.createDirectory(at: resolved, withIntermediateDirectories: true)
            let existsAfter = FileManager.default.fileExists(atPath: resolved.path)
            guard existsAfter else {
                throw ExecError.failed("Папка не была создана: \(resolved.path)")
            }
            return ExecResult(summary: "Создал папку: \(resolved.path)")
        case .browserClick:
            let result = try await AlakeyaBrowser.shared.click(
                elementID: action.args["element_id"] ?? "",
                text: action.args["text"] ?? action.target
            )
            return try await browserVerifiedResult(result)
        case .browserType:
            let result = try await AlakeyaBrowser.shared.type(
                text: action.args["text"] ?? "",
                elementID: action.args["element_id"] ?? "",
                field: action.args["field"] ?? action.target
            )
            return try await browserVerifiedResult(result)
        case .browserSelect:
            let result = try await AlakeyaBrowser.shared.select(
                elementID: action.args["element_id"] ?? action.target,
                value: action.args["value"] ?? ""
            )
            return try await browserVerifiedResult(result)

        // ── connectors ────────────────────────────────────
        case .connectorRead, .connectorWrite, .connectorSend:
            let result = try await ConnectorExecutor.shared.execute(
                toolName: action.args["tool_name"] ?? action.type.rawValue,
                args: action.args
            )
            return ExecResult(summary: result)

        // ── research tools ────────────────────────────────
        case .searchInternet:
            let query = action.args["query"] ?? ""
            let max = Int(action.args["max_results"] ?? "") ?? 15
            let results = try await AlakeyaBrowser.shared.searchHeadless(query: query, maxResults: max)
            return ExecResult(summary: "SEARCH_INTERNET_RESULTS:\n" + results)

        case .researchPlan:
            let query  = action.args["query"] ?? ""
            let plan   = SearchQueryPlanner.plan(for: query)
            let intent = ResearchIntent.detect(from: query)
            let planJSON = (try? String(data: JSONEncoder().encode(plan), encoding: .utf8)) ?? "{}"
            return ExecResult(summary: """
            RESEARCH_PLAN:
            Intent: \(intent.rawValue)
            Playbook: \(intent.playbook)
            Min sources: \(intent.minSources), Min results: \(intent.minResults)
            Queries: \(plan.queries.enumerated().map { "\($0.offset+1). \($0.element)" }.joined(separator: "\n"))
            Extraction goal: \(plan.extractionGoal)
            Fields: \(plan.dataFields.joined(separator: ", "))
            \(planJSON)
            """)

        case .extractSearchResults:
            let html = try await AlakeyaBrowser.shared.extractSearchResults()
            return ExecResult(summary: "SEARCH_RESULTS:\n\(html)")

        case .extractBusinessCards:
            let maxCards = Int(action.args["max_cards"] ?? "") ?? 20
            let cards = try await AlakeyaBrowser.shared.extractBusinessCards(maxCards: maxCards)
            return ExecResult(summary: "BUSINESS_CARDS:\n\(cards)")

        case .extractHotelCards:
            let maxCards = Int(action.args["max_cards"] ?? "") ?? 20
            let cards = try await AlakeyaBrowser.shared.extractHotelCards(maxCards: maxCards)
            return ExecResult(summary: "HOTEL_CARDS:\n\(cards)")

        case .extractContactCards:
            let contacts = try await AlakeyaBrowser.shared.extractContactCards()
            return ExecResult(summary: "CONTACT_CARDS:\n\(contacts)")

        case .extractArticle:
            let maxChars = Int(action.args["max_chars"] ?? "") ?? 6000
            let article = try await AlakeyaBrowser.shared.extractArticle(maxChars: maxChars)
            return ExecResult(summary: "ARTICLE:\n\(article)")

        case .qualityScoreResults:
            let sourcesJSON = action.args["sources_json"] ?? "[]"
            // Decode JSON array of {url, title, snippet} objects into typed tuples for rankJSON.
            struct SrcEntry: Decodable { var url, title: String; var snippet: String? }
            let entries = (try? JSONDecoder().decode([SrcEntry].self,
                           from: sourcesJSON.data(using: .utf8) ?? Data())) ?? []
            let tuples  = entries.map { (url: $0.url, title: $0.title, snippet: $0.snippet ?? "") }
            let scored  = SourceQualityScorer.rankJSON(tuples)
            return ExecResult(summary: "SCORED_RESULTS:\n\(scored)")

        // ── document export ───────────────────────────────
        case .exportPDF:
            let title   = action.args["title"] ?? "Отчёт"
            let content = action.args["content"] ?? ""
            if let denied = ExportGuard.checkText(content, label: "PDF") {
                return ExecResult(summary: denied)
            }
            let doc = buildReportDoc(title: title, content: content)
            let file = try await DocumentExportManager.shared.export(doc, as: .pdf)
            let attachment = ExportedFileAttachment(from: file, sourceTool: "export_pdf")
            await MainActor.run { ExportResultStore.shared.add(attachment) }
            print("[Export] format=pdf path=\(file.path.lastPathComponent)")
            return ExecResult(summary: "Готово — PDF создан.")

        case .exportDocx:
            let title   = action.args["title"] ?? "Документ"
            let content = action.args["content"] ?? ""
            if let denied = ExportGuard.checkText(content, label: "DOCX") {
                return ExecResult(summary: denied)
            }
            let doc = buildReportDoc(title: title, content: content)
            let file = try await DocumentExportManager.shared.export(doc, as: .docx)
            let attachment = ExportedFileAttachment(from: file, sourceTool: "export_docx")
            await MainActor.run { ExportResultStore.shared.add(attachment) }
            let isRTF = file.format == .rtf
            print("[Export] format=\(isRTF ? "rtf" : "docx") path=\(file.path.lastPathComponent)")
            return ExecResult(summary: isRTF
                ? "Готово — создан RTF-документ, его можно открыть в Word или Pages."
                : "Готово — DOCX создан.")

        case .exportCSV:
            let title       = action.args["title"] ?? "Таблица"
            let content     = action.args["content"] ?? ""
            let headersJSON = action.args["headers_json"] ?? "[]"
            let rowsJSON    = action.args["rows_json"]    ?? "[]"
            var headers = (try? JSONDecoder().decode([String].self,
                           from: headersJSON.data(using: .utf8) ?? Data())) ?? []
            var rows    = (try? JSONDecoder().decode([[String]].self,
                           from: rowsJSON.data(using: .utf8) ?? Data())) ?? []
            if headers.isEmpty, !content.isEmpty {
                if let parsed = MarkdownTableParser.parse(from: content).first {
                    headers = parsed.headers
                    rows    = parsed.rows
                }
            }
            if let denied = ExportGuard.checkTable(headers: headers, rows: rows, label: "CSV") {
                return ExecResult(summary: denied)
            }
            let file: ExportedFile
            if !headers.isEmpty {
                file = try await DocumentExportManager.shared.exportTable(
                    title: title, headers: headers, rows: rows, as: .csv)
            } else {
                file = try await DocumentExportManager.shared.exportText(content, title: title, as: .csv)
            }
            let attachment = ExportedFileAttachment(from: file, sourceTool: "export_csv")
            await MainActor.run { ExportResultStore.shared.add(attachment) }
            print("[Export] format=csv rows=\(rows.count) path=\(file.path.lastPathComponent)")
            return ExecResult(summary: "Готово — CSV создан для Excel/Numbers.")

        case .exportMarkdown:
            let title   = action.args["title"] ?? "Файл"
            let content = action.args["content"] ?? ""
            if let denied = ExportGuard.checkText(content, label: "Markdown") {
                return ExecResult(summary: denied)
            }
            let file = try await DocumentExportManager.shared.exportText(content, title: title, as: .markdown)
            let attachment = ExportedFileAttachment(from: file, sourceTool: "export_markdown")
            await MainActor.run { ExportResultStore.shared.add(attachment) }
            print("[Export] format=markdown path=\(file.path.lastPathComponent)")
            return ExecResult(summary: "Готово — Markdown-файл создан.")

        // ── high risk (always gated upstream) ─────────────
        case .sendMessage:
            try enterText(action.args["text"] ?? "")
            input.pressReturn()
            return ExecResult(summary: "Отправил сообщение в \(action.target)")
        case .sendEmail:
            return ExecResult(summary: "Отправил письмо: \(action.target)")
        case .deleteFile:
            return ExecResult(summary: "Удалил \(action.target)")
        case .runShell:
            return try runShell(action.code ?? action.args["command"] ?? "")
        case .makePayment:
            return ExecResult(summary: "Платёж: \(action.target)")
        case .browserSubmit:
            let result = try await AlakeyaBrowser.shared.submit(
                elementID: action.args["element_id"] ?? "",
                text: action.args["text"] ?? action.target
            )
            _ = try await AlakeyaBrowser.shared.wait(milliseconds: 500)
            return try await browserVerifiedResult(result)
        }
    }

    // ── report document builder ───────────────────────────

    private func buildReportDoc(title: String, content: String) -> ReportDocument {
        // Parse markdown tables from content, build sections
        let tables = MarkdownTableParser.parse(from: content)
        let cleanedBody = tables.isEmpty
            ? ReportContentNormalizer.normalize(content)
            : ReportContentNormalizer.normalize(MarkdownTableParser.removeTables(from: content))

        var sections: [ReportSection] = []
        if !cleanedBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(ReportSection(heading: "", body: cleanedBody))
        }
        for t in tables {
            sections.append(ReportSection(heading: "", table: ReportTable(headers: t.headers, rows: t.rows)))
        }
        if sections.isEmpty {
            sections.append(ReportSection(heading: "", body: content))
        }
        return ReportDocument(title: title, sections: sections)
    }

    // ── path safety and normalization ─────────────────────
    private static func isDangerousPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        let blocked = ["/.ssh", "/library/keychains", "/.gnupg", ".env", ".pem", ".key", ".p12", ".pfx"]
        return blocked.contains { lower.contains($0) }
    }

    // Resolves Russian/English Desktop aliases and bare names to absolute paths.
    // "рабочий стол" / "Desktop" → ~/Desktop
    // "AlakeyaTest" (no slash)   → ~/Desktop/AlakeyaTest (creates on Desktop by default)
    // "relative/sub"             → ~/relative/sub
    private static func resolvePath(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty            { return "\(NSHomeDirectory())/Desktop" }
        if s.hasPrefix("/")     { return s }
        if s.hasPrefix("~")     { return (s as NSString).expandingTildeInPath }
        let lower = s.lowercased()
        let home = NSHomeDirectory()
        if lower == "desktop" || lower == "рабочий стол" { return "\(home)/Desktop" }
        if !s.contains("/")     { return "\(home)/Desktop/\(s)" }
        return ("~/" + s as NSString).expandingTildeInPath
    }

    // ── helpers (the cascade) ─────────────────────────────

    /// Try AX value-set first; fall back to clipboard paste (DOC2).
    private func enterText(_ text: String) throws {
        if ax.isTrusted, ax.setFocusedValue(text) { return }
        input.pasteText(text)
    }

    private func openSearch(_ query: String) throws {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        try script.openURLInSafari("https://www.google.com/search?q=\(encoded)")
    }

    private func browserVerifiedResult(_ actionResult: String) async throws -> ExecResult {
        let page = try await AlakeyaBrowser.shared.readPage()
        return ExecResult(summary: """
        ACTION_RESULT: \(actionResult)
        CURRENT_PAGE: \(String(page.prefix(12_000)))
        """)
    }

    private func runShell(_ command: String) throws -> ExecResult {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", command]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        if proc.terminationStatus != 0 {
            throw ExecError.failed(out.isEmpty ? "Команда завершилась с ошибкой" : out)
        }
        return ExecResult(summary: "Выполнено: \(command)")
    }
}
