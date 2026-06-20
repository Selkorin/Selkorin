import Foundation

// ============================================================
// Action.swift — strictly typed action plan (DOC2: model proposes
// typed tool calls, the app executes them through the policy gate).
// ============================================================

enum RiskLevel: String { case low, medium, high }

enum ActionType: String, Codable {
    // low
    case readScreen    = "read_screen"
    case screenshot
    case search
    case listDirectory = "list_directory"
    case readTextFile  = "read_text_file"
    case browserOpen   = "browser_open"
    case browserReadPage = "browser_read_page"
    case browserBack   = "browser_back"
    case browserReload = "browser_reload"
    case browserScroll      = "browser_scroll"
    case browserWait        = "browser_wait"
    case browserScreenshot  = "browser_screenshot"
    case browserHardReload  = "browser_hard_reload"
    case browserZoom        = "browser_zoom"
    // medium
    case openApp       = "open_app"
    case navigateURL   = "navigate_url"
    case typeText      = "type_text"
    case clickElement  = "click_element"
    case appleScript   = "apple_script"
    case openFile      = "open_file"
    case createFolder  = "create_folder"
    case browserClick  = "browser_click"
    case browserType   = "browser_type"
    case browserSelect = "browser_select"
    // browser extras (low risk)
    case searchInternet = "search_internet"
    // -- research
    case browserHighlightElement = "browser_highlight_element"
    case browserExtractData      = "browser_extract_data"
    case browserSeoAudit         = "browser_seo_audit"
    // connectors (read=low, write=medium, send=high)
    case connectorRead  = "connector_read"
    case connectorWrite = "connector_write"
    case connectorSend  = "connector_send"
    // research (all low risk — read-only extraction)
    case researchPlan          = "research_plan"
    case extractSearchResults  = "extract_search_results"
    case extractBusinessCards  = "extract_business_cards"
    case extractHotelCards     = "extract_hotel_cards"
    case extractContactCards   = "extract_contact_cards"
    case extractArticle        = "extract_article"
    case qualityScoreResults   = "quality_score_results"
    // document export (low risk — local file creation)
    case exportPDF      = "export_pdf"
    case exportDocx     = "export_docx"
    case exportCSV      = "export_csv"
    case exportMarkdown = "export_markdown"
    // high
    case sendMessage   = "send_message"
    case sendEmail     = "send_email"
    case deleteFile    = "delete_file"
    case runShell      = "run_shell"
    case makePayment   = "make_payment"
    case browserSubmit       = "browser_submit"
    case browserClearCookies = "browser_clear_cookies"
    case browserClearCache   = "browser_clear_cache"

    var risk: RiskLevel {
        switch self {
        case .sendMessage, .sendEmail, .deleteFile, .runShell, .makePayment,
             .browserSubmit, .browserClearCookies, .browserClearCache,
             .connectorSend:
            return .high
        case .openApp, .navigateURL, .typeText, .clickElement, .appleScript,
             .openFile, .createFolder, .browserClick, .browserType, .browserSelect,
             .connectorWrite:
            return .medium
        default:
            return .low
        }
    }
}

/// A single typed action, ready for execution and for the PermissionCard.
struct Action: Identifiable {
    let id: String
    let type: ActionType
    var title: String
    var description: String
    var target: String
    var scope: String
    var reversible: Bool
    var code: String?            // shell preview, etc.
    var args: [String: String]   // executor parameters (text, app, url, query…)

    var risk: RiskLevel { type.risk }

    init(id: String = UUID().uuidString,
         type: ActionType,
         title: String,
         description: String,
         target: String,
         scope: String,
         reversible: Bool = true,
         code: String? = nil,
         args: [String: String] = [:]) {
        self.id = id
        self.type = type
        self.title = title
        self.description = description
        self.target = target
        self.scope = scope
        self.reversible = reversible
        self.code = code
        self.args = args
    }
}

/// A raw tool call produced by the orchestrator before UI enrichment.
struct ToolCall {
    let name: ActionType
    let args: [String: String]
}

/// A planned task: visible steps, the typed calls, and a spoken reply.
struct Plan {
    var steps: [TaskStep]
    var toolCalls: [ToolCall]
    var reply: String
}

struct TaskStep: Identifiable {
    let id = UUID()
    var label: String
    var status: StepStatus = .pending
}

enum StepStatus: String { case pending, active, done, blocked }
