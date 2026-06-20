import Foundation

// ============================================================
// Permissions.swift — policy engine: risk classification, the
// manual/auto confirm rule, and remembered rules (HANDOFF §6.2-6.3,
// DOC2 §"Правила подтверждений").
// ============================================================

enum ConfirmMode: String { case manual, auto }

enum Decision: String { case once, always, deny }

final class PolicyEngine {
    static let shared = PolicyEngine()

    private(set) var rememberedRules: Set<String>
    var mode: ConfirmMode = .manual

    private init() {
        rememberedRules = Store.shared.loadRules()
    }

    func classifyRisk(_ action: Action) -> RiskLevel { action.type.risk }

    /// HANDOFF §6.3 — hard limits always ask; safe browser actions always pass;
    /// remembered rules auto-pass; in auto mode low risk auto-confirms.
    func shouldAutoConfirm(_ action: Action) -> Bool {
        // ── Hard limits: always require confirmation ──────────
        switch action.type {
        case .sendEmail, .deleteFile, .makePayment, .browserSubmit,
             .browserClearCookies, .browserClearCache, .connectorSend:
            logDecision(action, auto: false, reason: "hard limit — always confirm")
            return false
        default:
            break
        }

        // ── Local file export: always auto-confirm (no external effect) ──
        switch action.type {
        case .exportPDF, .exportDocx, .exportCSV, .exportMarkdown:
            logDecision(action, auto: true, reason: "local file export — no external effect")
            return true
        default:
            break
        }

        // ── Research extraction: always auto-confirm (read-only) ─────
        switch action.type {
        case .researchPlan, .extractSearchResults, .extractBusinessCards,
             .extractHotelCards, .extractContactCards, .extractArticle,
             .qualityScoreResults:
            logDecision(action, auto: true, reason: "research read-only extraction")
            return true
        default:
            break
        }

        // ── Safe browser navigation/read: always auto-confirm ─
        switch action.type {
        case .browserOpen, .browserReadPage, .browserBack, .browserReload,
             .browserHardReload, .browserScroll, .browserWait,
             .browserScreenshot, .browserZoom, .connectorRead:
            logDecision(action, auto: true, reason: "safe browser read/navigation")
            return true
        default:
            break
        }

        // ── browserClick: auto unless target looks destructive ─
        if action.type == .browserClick {
            let label = (action.args["text"] ?? action.args["element_id"] ?? action.target).lowercased()
            if isDangerousClickTarget(label) {
                logDecision(action, auto: false, reason: "click target matches destructive action pattern")
                return false
            }
            logDecision(action, auto: true, reason: "safe browser click")
            return true
        }

        // ── browserType: auto unless field looks sensitive ────
        if action.type == .browserType {
            let field = (action.args["field"] ?? action.args["element_id"] ?? action.target).lowercased()
            if isSensitiveField(field) {
                logDecision(action, auto: false, reason: "field matches sensitive input pattern")
                return false
            }
            logDecision(action, auto: true, reason: "safe browser type")
            return true
        }

        // ── browserSelect: auto ───────────────────────────────
        if action.type == .browserSelect {
            logDecision(action, auto: true, reason: "safe browser select")
            return true
        }

        if rememberedRules.contains(ruleKey(action)) { return true }
        if mode == .manual {
            logDecision(action, auto: false, reason: "manual mode")
            return false
        }
        let auto = action.risk == .low
        logDecision(action, auto: auto, reason: auto ? "low risk in auto mode" : "medium/high risk")
        return auto
    }

    // ── Helpers ───────────────────────────────────────────────

    private func isDangerousClickTarget(_ label: String) -> Bool {
        let dangerous = [
            "submit", "send", "отправить", "buy", "купить", "pay", "оплатить",
            "delete", "удалить", "remove", "confirm", "подтвердить", "continue",
            "login", "войти", "sign in", "signin", "publish", "опубликовать",
            "checkout", "оформить", "charge", "списать",
        ]
        return dangerous.contains { label.contains($0) }
    }

    private func isSensitiveField(_ field: String) -> Bool {
        let sensitive = [
            "password", "пароль", "passwd", "pass",
            "2fa", "totp", "otp", "код подтверждения",
            "card", "карта", "credit", "debit", "cvv", "cvc",
            "seed", "mnemonic", "private key", "secret",
            "pin", "пин",
        ]
        return sensitive.contains { field.contains($0) }
    }

    private func logDecision(_ action: Action, auto: Bool, reason: String) {
        print("""
        [Permission] action=\(action.type.rawValue) \
        risk=\(action.risk.rawValue) \
        auto=\(auto) \
        reason=\(reason)
        """)
    }

    func remember(_ action: Action) {
        rememberedRules.insert(ruleKey(action))
        Store.shared.saveRules(rememberedRules)
    }

    func ruleKey(_ action: Action) -> String { "\(action.type.rawValue):\(action.target)" }
}
