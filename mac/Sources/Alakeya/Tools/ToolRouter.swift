import Foundation

// Tool scope controls which tools are sent to the model.
// Max 64 tools per API call — scopes keep the list focused.
enum ToolScope {
    case none                          // pure chat, no tools (tools.count = 0)
    case browser                       // browser control only (~15 tools)
    case research                      // browser + general research extract (~10 tools)
    case localBusinessResearch         // browser + business/contact extraction (~12 tools)
    case localBusinessResearchThenExport // research + export tools (~16 tools)
    case connectors                    // connector tools only
    case browserAndConnectors
    case documentExport                // export_pdf/docx/csv/markdown only (4 tools)
    case scraping                      // browser + aggressive extraction (no research_plan)
    case all                           // everything registered
}

final class ToolRouter {
    static let shared = ToolRouter()
    private var handlers: [String: ToolHandler] = [:]
    private init() {}

    func register(_ handler: ToolHandler) {
        for name in handler.toolNames { handlers[name] = handler }
    }

    // Returns deduplicated schemas filtered by scope.
    func toolSchemas(scope: ToolScope = .all) -> [[String: Any]] {
        var seen = Set<String>()
        let all = handlers.values.flatMap { $0.toolSchemas }.filter { schema in
            guard let fn = schema["function"] as? [String: Any],
                  let name = fn["name"] as? String else { return true }
            return seen.insert(name).inserted
        }

        func filter(_ predicate: (String) -> Bool) -> [[String: Any]] {
            all.filter { schemaName($0).map(predicate) == true }
        }

        switch scope {
        case .none:
            return []

        case .all:
            return all

        case .browser:
            // All browser control tools only
            return filter { isBrowserControlTool($0) }

        case .research:
            // General research: search + extract WITHOUT browser control
            // Browser tools are reserved for the .scraping scope
            return filter { isGeneralResearchTool($0) || isSearchTool($0) }

        case .scraping:
            // Browser + extraction for aggressive data scraping
            return filter { isBrowserControlTool($0) || isBusinessExtractionTool($0) || isSearchTool($0) }

        case .localBusinessResearch:
            // Browser subset + business/contact extraction + search tools
            return filter { isBrowserControlTool($0) || isBusinessExtractionTool($0) || isSearchTool($0) }

        case .localBusinessResearchThenExport:
            // Research tools + export tools (staged: research first, then export)
            return filter { isBrowserControlTool($0) || isBusinessExtractionTool($0) || isExportTool($0) }

        case .connectors:
            return filter { isConnectorTool($0) }

        case .browserAndConnectors:
            return filter { isBrowserControlTool($0) || isConnectorTool($0) }

        case .documentExport:
            return filter { isExportTool($0) }
        }
    }

    // MARK: - Tool classifiers

    // All browser_* tools (control + interaction + extraction)
    private func isBrowserControlTool(_ name: String) -> Bool {
        name.hasPrefix("browser_")
    }

    // General research: text extraction, SERP, articles, quality scoring
    private func isGeneralResearchTool(_ name: String) -> Bool {
        // Only tools that work WITHOUT the browser pane open
        let names: Set<String> = [
            "research_plan",
            "quality_score_results",
        ]
        return names.contains(name)
    }

    // Local business research: business cards, contacts, SERP
    private func isBusinessExtractionTool(_ name: String) -> Bool {
        let names: Set<String> = [
            "research_plan",
            "extract_search_results",
            "extract_business_cards",
            "extract_hotel_cards",
            "extract_contact_cards",
            "quality_score_results",
        ]
        return names.contains(name)
    }

    private func isConnectorTool(_ name: String) -> Bool {
        let prefixes = [
            "gmail_", "drive_", "docs_", "sheets_", "calendar_",
            "telegram_", "vk_", "instagram_", "spreadsheet_",
        ]
        return prefixes.contains { name.hasPrefix($0) }
    }

    // Headless search — research without opening browser
    private func isSearchTool(_ name: String) -> Bool {
        let names: Set<String> = [
            "search_internet",
            "research_plan",
            "quality_score_results",
        ]
        return names.contains(name)
    }

    private func isExportTool(_ name: String) -> Bool {
        let names: Set<String> = ["export_pdf", "export_docx", "export_csv", "export_markdown"]
        return names.contains(name)
    }

    private func schemaName(_ schema: [String: Any]) -> String? {
        (schema["function"] as? [String: Any])?["name"] as? String
    }

    func makeAction(toolName: String, args: [String: String]) -> Action? {
        handlers[toolName]?.makeAction(toolName: toolName, args: args)
    }

    var hasTools: Bool { !handlers.isEmpty }
}
