import Foundation

// ============================================================
// LocalBusinessSearchCoordinator.swift
// Deterministic local business research pipeline.
// Does NOT rely on free-form LLM orchestration for the search
// loop — this code controls source selection, fallback, and
// validation directly.
//
// Entry: LocalBusinessSearchCoordinator.run(query:, store:)
// Returns: LocalBusinessResult with validated leads + formatted text.
// ============================================================

struct LocalBusinessResult {
    let query: LocalBusinessQuery
    let leads: [LocalBusinessLead]
    let table: ParsedMarkdownTable?
    let formattedText: String
    let sourcesAttempted: [String]
    let partial: Bool
    let partialNote: String?
    let fileAttachments: [ExportedFileAttachment]
}

private struct LocalBusinessSourceDiagnostic {
    let name: String
    var found: Int = 0
    var status: String = "checked"
}

private struct LocalBusinessHeadlessFallback {
    let attempted: Bool
    let sourceName: String
    let status: String
    let leads: [LocalBusinessLead]
}

@MainActor
final class LocalBusinessSearchCoordinator {

    static let maxScrollsPerSource = 6
    static let maxSources = 4

    // MARK: - Entry Point

    static func run(query: LocalBusinessQuery, store: AgentStore) async -> LocalBusinessResult {
        // City required for meaningful local search
        guard let city = query.city, !city.isEmpty else {
            let ask = "В каком городе искать \(query.category)? Укажите город или регион."
            return LocalBusinessResult(
                query: query, leads: [], table: nil,
                formattedText: ask, sourcesAttempted: [],
                partial: false, partialNote: nil, fileAttachments: []
            )
        }

        print("[ResearchFlow] intent=localBusiness city=\(city) category=\(query.category) targetCount=\(query.targetCount)")
        store.setToolStatus("Готовлю поиск: \(query.category) — \(city)")

        var allLeads: [LocalBusinessLead] = []
        var sourcesAttempted: [String] = []
        var blockedSources: [String] = []
        var diagnostics: [LocalBusinessSourceDiagnostic] = []
        let browser = AlakeyaBrowser.shared

        // ── Source loop ───────────────────────────────────────
        let sources = query.requestedSources.prefix(Self.maxSources)

        for source in sources {
            guard allLeads.count < query.targetCount else { break }

            guard let url = source.url(category: query.category, city: city) else { continue }
            let urlStr = url.absoluteString
            print("[LocalBusiness] source=\(source.rawValue) url=\(urlStr)")
            sourcesAttempted.append(source.rawValue)
            var diagnostic = LocalBusinessSourceDiagnostic(name: source.rawValue)

            store.setStatus(.acting)
            store.setToolStatus("Открываю источник: \(source.rawValue)")

            // ── 1. Open page ──────────────────────────────────
            browser.open(urlStr)
            _ = try? await AlakeyaBrowser.shared.wait(milliseconds: 2000)

            // ── 2. Read + extract loop ────────────────────────
            let leadsBeforeSource = allLeads.count
            let maxScrolls = min(Self.maxScrollsPerSource, source.maxScrollAttempts)
            for scrollAttempt in 0..<maxScrolls {
                store.setToolStatus("Извлекаю карточки из \(source.rawValue)… найдено \(allLeads.count)")
                let pageText = (try? await browser.readPage()) ?? ""
                if LocalBusinessExtractionNormalizer.looksLikeBotChallenge(pageText) {
                    print("[LocalBusiness] source=\(source.rawValue) blocked=bot_challenge")
                    blockedSources.append(source.rawValue)
                    diagnostic.status = "manual_verification"
                    _ = try? await browser.prepareManualVerificationAccessibilityMode()
                    store.setToolStatus("Источник \(source.rawValue) попросил ручную проверку. Оставляю страницу открытой и перехожу дальше.")
                    store.showError(
                        "Источник \(source.rawValue) запросил проверку. Я включил режим доступности: увеличил страницу и подсветил область. Пройдите проверку вручную, если хотите продолжить с этим источником.",
                        blocked: false
                    )
                    break
                }

                let remaining = max(1, query.targetCount - allLeads.count)
                let cards    = (try? await browser.extractBusinessCards(maxCards: remaining)) ?? ""
                let contacts = (try? await browser.extractContactCards()) ?? ""

                let fromCards = LocalBusinessExtractionNormalizer
                    .parseBusinessCards(cards, source: source.rawValue, sourceURL: urlStr, city: city)
                let fromContacts = LocalBusinessExtractionNormalizer
                    .parseContactCards(contacts, source: source.rawValue, sourceURL: urlStr, city: city)
                let fromText = fromCards.isEmpty && fromContacts.isEmpty
                    ? LocalBusinessExtractionNormalizer.parsePageText(pageText, source: source.rawValue, sourceURL: urlStr, city: city)
                    : []

                let batch = LocalBusinessExtractionNormalizer
                    .deduplicate(fromCards + fromContacts + fromText)
                    .filter { LocalBusinessLeadValidator.isActionable($0, requirePhone: query.requirePhone) }
                let beforeCount = allLeads.count
                for lead in batch {
                    let key = LocalBusinessLeadValidator.deduplicateKey(lead)
                    if !allLeads.contains(where: { LocalBusinessLeadValidator.deduplicateKey($0) == key }) {
                        allLeads.append(lead)
                    }
                }
                let newLeadsThisPass = allLeads.count - beforeCount

                print("[Extract] businessCards count=\(fromCards.count) contactCards count=\(fromContacts.count) text count=\(fromText.count)")
                print("[LocalBusiness] source=\(source.rawValue) scroll=\(scrollAttempt) new=\(newLeadsThisPass) leadsAfter=\(allLeads.count)")

                if allLeads.count >= query.targetCount { break }
                if scrollAttempt < maxScrolls - 1 {
                    _ = try? await browser.scrollResultsContainer()
                    _ = try? await AlakeyaBrowser.shared.wait(milliseconds: 1400)
                }
            }

            let newLeadsThisSource = allLeads.count - leadsBeforeSource
            diagnostic.found = newLeadsThisSource
            if diagnostic.status == "checked" {
                diagnostic.status = newLeadsThisSource > 0 ? "usable" : "no_valid_rows"
            }
            diagnostics.append(diagnostic)
            if newLeadsThisSource == 0 && sourcesAttempted.count < sources.count {
                let nextSource = sources.dropFirst(sourcesAttempted.count).first
                if let next = nextSource {
                    print("[LocalBusiness] fallback=\(next.rawValue) reason=no_new_valid_leads")
                }
            }
        }

        // ── Headless web fallback ────────────────────────────
        // This does not open the UI browser and does not use Google/Yandex by
        // default. It gives the local pipeline a second chance when directory
        // cards are unavailable, blocked, or too thin.
        if allLeads.count < query.targetCount {
            store.setToolStatus("Проверяю веб-источники без открытия браузера… найдено \(allLeads.count)")
            let fallback = runHeadlessWebFallback(query: query, city: city)
            if fallback.attempted {
                sourcesAttempted.append(fallback.sourceName)
                let beforeFallback = allLeads.count
                let candidates = fallback.leads
                    .filter { LocalBusinessLeadValidator.isActionable($0, requirePhone: query.requirePhone) }
                for lead in candidates {
                    let key = LocalBusinessLeadValidator.deduplicateKey(lead)
                    if !allLeads.contains(where: { LocalBusinessLeadValidator.deduplicateKey($0) == key }) {
                        allLeads.append(lead)
                    }
                    if allLeads.count >= query.targetCount { break }
                }
                let added = allLeads.count - beforeFallback
                diagnostics.append(
                    LocalBusinessSourceDiagnostic(
                        name: fallback.sourceName,
                        found: added,
                        status: added > 0 ? "usable_web_fallback" : fallback.status
                    )
                )
            }
        }

        // ── Structured search API source (Google CSE / Yandex API) ──
        // Captcha-free lead generation through official search APIs with
        // targeted queries and contact (phone/email) extraction.
        if allLeads.count < query.targetCount && LocalBusinessAPILeadSource.isConfigured {
            store.setToolStatus("Ищу контакты через поисковые API… найдено \(allLeads.count)")
            let outcome = await LocalBusinessAPILeadSource.collect(query: query, city: city)
            if outcome.attempted {
                let sourceLabel = outcome.providerNames.isEmpty
                    ? "Search API" : outcome.providerNames.joined(separator: "+")
                sourcesAttempted.append(sourceLabel)
                let beforeAPI = allLeads.count
                let candidates = outcome.leads
                    .filter { LocalBusinessLeadValidator.isActionable($0, requirePhone: query.requirePhone) }
                for lead in candidates {
                    let key = LocalBusinessLeadValidator.deduplicateKey(lead)
                    if !allLeads.contains(where: { LocalBusinessLeadValidator.deduplicateKey($0) == key }) {
                        allLeads.append(lead)
                    }
                    if allLeads.count >= query.targetCount { break }
                }
                let added = allLeads.count - beforeAPI
                diagnostics.append(
                    LocalBusinessSourceDiagnostic(
                        name: sourceLabel,
                        found: added,
                        status: added > 0 ? "usable_api" : outcome.status
                    )
                )
                print("[LocalBusiness] apiSource=\(sourceLabel) added=\(added)")
            }
        }

        // ── Filter by noWebsite ───────────────────────────────
        var filteredLeads = allLeads
        if query.requireNoWebsite {
            filteredLeads = allLeads.filter { $0.websiteStatus.passesFreeFilter }
            print("[LocalBusiness] noWebsiteFilter applied: \(allLeads.count) → \(filteredLeads.count)")
        }

        // Trim to target
        let finalLeads = Array(
            filteredLeads
                .filter { LocalBusinessLeadValidator.isActionable($0, requirePhone: query.requirePhone) }
                .sorted { lhs, rhs in
                    if lhs.phone.isEmpty != rhs.phone.isEmpty { return !lhs.phone.isEmpty }
                    if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                .prefix(query.targetCount)
        )
        print("[ResearchResult] rows=\(finalLeads.count) targetCount=\(query.targetCount)")

        // ── Build table + text ────────────────────────────────
        let table = LocalBusinessLead.toTable(finalLeads, noWebsiteFilter: query.requireNoWebsite)
        let formattedText = buildFormattedResponse(
            leads: finalLeads, table: table, query: query, city: city,
            sourcesAttempted: sourcesAttempted, blockedSources: blockedSources,
            diagnostics: diagnostics,
            totalFound: allLeads.count
        )

        // ── Export if requested ────────────────────────────────
        var fileAttachments: [ExportedFileAttachment] = []
        if query.shouldExport, let format = query.exportFormat, !finalLeads.isEmpty {
            let title = "\(query.category.capitalized) — \(city) (\(finalLeads.count))"
            if let attachment = await exportLeads(finalLeads, table: table, title: title, format: format) {
                fileAttachments.append(attachment)
                print("[Export] format=\(format) path=\(attachment.filename)")
            }
        }

        let partial = finalLeads.count < query.targetCount
        let partialNote: String? = partial
            ? "Нашла \(finalLeads.count) из \(query.targetCount) подходящих контактов."
            : nil

        return LocalBusinessResult(
            query: query,
            leads: finalLeads,
            table: table.rows.isEmpty ? nil : table,
            formattedText: formattedText,
            sourcesAttempted: sourcesAttempted,
            partial: partial,
            partialNote: partialNote,
            fileAttachments: fileAttachments
        )
    }

    // MARK: - Formatted Response

    private static func buildFormattedResponse(
        leads: [LocalBusinessLead],
        table: ParsedMarkdownTable,
        query: LocalBusinessQuery,
        city: String,
        sourcesAttempted: [String],
        blockedSources: [String],
        diagnostics: [LocalBusinessSourceDiagnostic],
        totalFound: Int
    ) -> String {
        var lines: [String] = []

        if leads.isEmpty {
            lines.append("Не удалось собрать контакты для **\(query.category)** в **\(city)**.")
            lines.append("")
            lines.append("Проверены источники: \(sourcesAttempted.joined(separator: ", ")).")
            if !diagnostics.isEmpty {
                let summary = diagnostics.map { item in
                    "\(item.name): \(item.found) / \(item.status)"
                }.joined(separator: "; ")
                lines.append("Статус источников: \(summary).")
            }
            if !blockedSources.isEmpty {
                lines.append("Проверка вручную потребовалась на: \(blockedSources.joined(separator: ", ")).")
            }
            lines.append("Страницы могут требовать авторизацию или не отдали структурированные карточки.")
            lines.append("Попробуйте уточнить запрос, указать официальный сайт/каталог или явно выбрать источник.")
            return lines.joined(separator: "\n")
        }

        let countNote = leads.count < query.targetCount
            ? "Нашла **\(leads.count)** из **\(query.targetCount)** подходящих"
            : "Нашла **\(leads.count)** контактов"
        let filterNote = query.requireNoWebsite ? " (без сайта)" : ""
        lines.append("\(countNote) — **\(query.category)** в **\(city)**\(filterNote):")
        lines.append("")
        lines.append(table.toMarkdown())
        lines.append("")
        lines.append("Источники: \(sourcesAttempted.joined(separator: ", "))")

        if !diagnostics.isEmpty {
            let summary = diagnostics.map { item in
                "\(item.name): \(item.found) / \(item.status)"
            }.joined(separator: "; ")
            lines.append("Статус источников: \(summary)")
        }

        if !blockedSources.isEmpty {
            lines.append("")
            lines.append("Проверка вручную потребовалась на: \(blockedSources.joined(separator: ", ")). Я не обходил её автоматически; источник пропущен, страница оставлена в браузере для ручного прохождения.")
        }

        if query.shouldExport {
            lines.append("")
            if !leads.isEmpty {
                lines.append("Готово — файл создан.")
            } else {
                lines.append("Не экспортирую: нет собранных строк.")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Headless Web Fallback

    private static func runHeadlessWebFallback(
        query: LocalBusinessQuery,
        city: String
    ) -> LocalBusinessHeadlessFallback {
        guard let scriptPath = browserAgentScriptPath() else {
            return LocalBusinessHeadlessFallback(
                attempted: false,
                sourceName: "Web search",
                status: "runner_missing",
                leads: []
            )
        }

        let searchText = headlessFallbackQuery(query: query, city: city)
        print("[LocalBusiness] fallback=Web search query=\(searchText)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            scriptPath,
            "--mode", "search_extract",
            "--query", searchText,
            "--goal", "найти официальные контакты организаций: название, телефон, сайт",
            "--max-results", "4",
            "--max-links", "48",
            "--max-text-chars", "3500",
            "--timeout", "8",
        ]

        var environment = ProcessInfo.processInfo.environment
        environment["ALAKEYA_POLITE_FETCH_DELAY"] = environment["ALAKEYA_POLITE_FETCH_DELAY"] ?? "0.8"
        environment["ALAKEYA_ALLOW_GOOGLE_SEARCH"] = "0"
        process.environment = environment

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return LocalBusinessHeadlessFallback(
                attempted: true,
                sourceName: "Web search",
                status: "process_error",
                leads: []
            )
        }

        let data = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            print("[LocalBusiness] fallback=Web search failed status=\(process.terminationStatus) stderr=\(stderr.prefix(300))")
            return LocalBusinessHeadlessFallback(
                attempted: true,
                sourceName: "Web search",
                status: "process_failed",
                leads: []
            )
        }

        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = object["rows"] as? [[Any]]
        else {
            return LocalBusinessHeadlessFallback(
                attempted: true,
                sourceName: "Web search",
                status: "bad_json",
                leads: []
            )
        }

        let leads = rows.compactMap { row in
            leadFromHeadlessRow(row, query: query, city: city)
        }
        let status = leads.isEmpty ? "no_valid_rows" : "usable"
        return LocalBusinessHeadlessFallback(
            attempted: true,
            sourceName: "Web search",
            status: status,
            leads: leads
        )
    }

    private static func browserAgentScriptPath() -> String? {
        let devScriptPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts/browser_agent_extract.py").path
        let bundledScriptPath = Bundle.main.resourceURL?
            .appendingPathComponent("scripts/browser_agent_extract.py").path
        return [devScriptPath, bundledScriptPath]
            .compactMap { $0 }
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    private static func headlessFallbackQuery(query: LocalBusinessQuery, city: String) -> String {
        let lowerCategory = query.category.lowercased()
        if lowerCategory.contains("отел") || lowerCategory.contains("гостиниц") ||
            lowerCategory.contains("санатор") || lowerCategory.contains("курорт") {
            return "\(query.category) \(city) телефон контакты официальный сайт"
        }
        return "\(query.category) \(city) телефон адрес контакты официальный сайт"
    }

    private static func leadFromHeadlessRow(
        _ row: [Any],
        query: LocalBusinessQuery,
        city: String
    ) -> LocalBusinessLead? {
        let title = stringValue(row, 0)
        let url = stringValue(row, 1)
        let h1 = stringValue(row, 3)
        let phones = stringValue(row, 5)
        let quality = Double(stringValue(row, 7)) ?? 0
        let error = stringValue(row, 8).lowercased()

        guard !url.isEmpty, !error.contains("bot_challenge") else { return nil }

        let name = cleanHeadlessName(h1.isEmpty ? title : h1, url: url)
        guard LocalBusinessLeadValidator.hasUsableName(name),
              !isGenericHeadlessTitle(name, url: url)
        else { return nil }

        let phone = firstValidPhone(from: phones)
        let website = domain(from: url)
        var lead = LocalBusinessLead(
            name: name,
            category: query.category,
            city: city,
            address: "",
            phone: phone,
            website: website,
            websiteStatus: LocalBusinessLeadValidator.classifyWebsite(website),
            sourceName: website.isEmpty ? "Web search" : "Web: \(website)",
            sourceURL: url,
            notes: quality > 0 ? "Веб-поиск, качество \(Int(quality))" : "Веб-поиск",
            confidence: min(0.86, 0.55 + quality / 250.0)
        )
        lead = LocalBusinessLeadValidator.validate(lead)
        return lead
    }

    private static func stringValue(_ row: [Any], _ index: Int) -> String {
        guard row.indices.contains(index) else { return "" }
        if let value = row[index] as? String { return value.trimmingCharacters(in: .whitespacesAndNewlines) }
        return "\(row[index])".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstValidPhone(from raw: String) -> String {
        let pieces = raw
            .split { char in char == "," || char == ";" || char.isNewline }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        return pieces.first(where: { LocalBusinessLeadValidator.isValidPhone($0) }) ?? ""
    }

    private static func cleanHeadlessName(_ raw: String, url: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = [" | ", " — ", " – ", " - ", " :: "]
        for separator in separators {
            if let range = value.range(of: separator), range.lowerBound > value.startIndex {
                value = String(value[..<range.lowerBound])
                break
            }
        }
        value = value.replacingOccurrences(
            of: #"(?i)\s*(официальный\s+сайт|официальная\s+страница|контакты)\s*$"#,
            with: "",
            options: .regularExpression
        )
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return domain(from: url)
        }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: " \n\t.,;:|—-"))
    }

    private static func isGenericHeadlessTitle(_ name: String, url: String) -> Bool {
        let lower = name.lowercased()
        let genericPatterns = [
            #"(^|\s)(топ|top)(\s|\-|\d|$)"#,
            #"лучш|рейтинг|подборк|каталог|список|цены|отзывы|забронировать|бронирование"#,
        ]
        if genericPatterns.contains(where: {
            lower.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
        }) {
            return true
        }

        let host = domain(from: url)
        let directoryHosts = ["101hotels", "tripadvisor", "booking", "ostrovok", "travelask", "tvil", "edem-v-gosti"]
        return directoryHosts.contains { host.contains($0) }
    }

    private static func domain(from url: String) -> String {
        guard let host = URL(string: url)?.host else { return "" }
        return host.replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
    }

    // MARK: - Export

    private static func exportLeads(
        _ leads: [LocalBusinessLead],
        table: ParsedMarkdownTable,
        title: String,
        format: String
    ) async -> ExportedFileAttachment? {
        guard !leads.isEmpty else {
            print("[ExportGuard] allowed=false reason=no_leads")
            return nil
        }

        do {
            let file: ExportedFile
            switch format {
            case "csv":
                file = try await DocumentExportManager.shared.exportTable(
                    title: title,
                    headers: table.headers,
                    rows: table.rows,
                    as: .csv
                )
            case "pdf":
                let sections = [ReportSection(heading: "", table: ReportTable(headers: table.headers, rows: table.rows))]
                let doc = ReportDocument(title: title, sections: sections)
                file = try await DocumentExportManager.shared.export(doc, as: .pdf)
            case "docx":
                let sections = [ReportSection(heading: "", table: ReportTable(headers: table.headers, rows: table.rows))]
                let doc = ReportDocument(title: title, sections: sections)
                file = try await DocumentExportManager.shared.export(doc, as: .docx)
            default:
                file = try await DocumentExportManager.shared.exportTable(
                    title: title, headers: table.headers, rows: table.rows, as: .csv)
            }
            return ExportedFileAttachment(from: file, sourceTool: "local_business_export")
        } catch {
            print("[LocalBusiness] export failed: \(error)")
            return nil
        }
    }
}
