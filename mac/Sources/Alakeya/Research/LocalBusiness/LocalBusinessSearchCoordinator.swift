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

        var allLeads: [LocalBusinessLead] = []
        var sourcesAttempted: [String] = []
        let browser = AlakeyaBrowser.shared

        // ── Source loop ───────────────────────────────────────
        let sources = query.requestedSources.prefix(Self.maxSources)

        for source in sources {
            guard allLeads.count < query.targetCount else { break }

            guard let url = source.url(category: query.category, city: city) else { continue }
            let urlStr = url.absoluteString
            print("[LocalBusiness] source=\(source.rawValue) url=\(urlStr)")
            sourcesAttempted.append(source.rawValue)

            store.setStatus(.acting)

            // ── 1. Open page ──────────────────────────────────
            browser.open(urlStr)
            _ = try? await AlakeyaBrowser.shared.wait(milliseconds: 2000)

            // ── 2. Read + extract loop ────────────────────────
            let leadsBeforeSource = allLeads.count
            for scrollAttempt in 0..<Self.maxScrollsPerSource {
                let pageText = (try? await browser.readPage()) ?? ""
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

                let batch = LocalBusinessExtractionNormalizer.deduplicate(fromCards + fromContacts + fromText)
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
                if scrollAttempt < Self.maxScrollsPerSource - 1 {
                    _ = try? await browser.scrollResultsContainer()
                    _ = try? await AlakeyaBrowser.shared.wait(milliseconds: 1400)
                }
            }

            let newLeadsThisSource = allLeads.count - leadsBeforeSource
            if newLeadsThisSource == 0 && sourcesAttempted.count < sources.count {
                let nextSource = sources.dropFirst(sourcesAttempted.count).first
                if let next = nextSource {
                    print("[LocalBusiness] fallback=\(next.rawValue) reason=no_new_valid_leads")
                }
            }
        }

        // ── Filter by noWebsite ───────────────────────────────
        var filteredLeads = allLeads
        if query.requireNoWebsite {
            filteredLeads = allLeads.filter { $0.websiteStatus.passesFreeFilter }
            print("[LocalBusiness] noWebsiteFilter applied: \(allLeads.count) → \(filteredLeads.count)")
        }

        // Trim to target
        let finalLeads = Array(filteredLeads.prefix(query.targetCount))
        print("[ResearchResult] rows=\(finalLeads.count) targetCount=\(query.targetCount)")

        // ── Build table + text ────────────────────────────────
        let table = LocalBusinessLead.toTable(finalLeads, noWebsiteFilter: query.requireNoWebsite)
        let formattedText = buildFormattedResponse(
            leads: finalLeads, table: table, query: query, city: city,
            sourcesAttempted: sourcesAttempted, totalFound: allLeads.count
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
        totalFound: Int
    ) -> String {
        var lines: [String] = []

        if leads.isEmpty {
            lines.append("Не удалось собрать контакты для **\(query.category)** в **\(city)**.")
            lines.append("")
            lines.append("Проверены источники: \(sourcesAttempted.joined(separator: ", ")).")
            lines.append("Страницы могут требовать авторизацию или не отдали структурированные карточки.")
            lines.append("Попробуйте уточнить запрос или указать другой источник (2ГИС, Google).")
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
