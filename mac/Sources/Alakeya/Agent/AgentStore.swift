import SwiftUI
import Combine

// ============================================================
// AgentStore.swift — the renderer-facing ObservableObject.
// ============================================================

struct PendingApproval: Identifiable {
    let id: String
    let action: Action
    let resolve: (Decision) -> Void
}

struct ErrorMessage: Identifiable {
    let id = UUID()
    let message: String
    let blocked: Bool
}

struct CurrentTask {
    var title: String
    var steps: [TaskStep]
}

@MainActor
final class AgentStore: ObservableObject {
    @Published var status: AgentStatusLabel = .ready
    @Published var panelOpen = false
    @Published var transcript = ""
    @Published var task: CurrentTask?
    @Published var pending: PendingApproval?
    @Published var pendingLocalBusinessQuery: LocalBusinessQuery?
    @Published var error: ErrorMessage?
    @Published var activity: [ActivityEntry] = []
    @Published var showSettings = false
    @Published var showActivity = false
    @Published var settings = Settings.load()
    @Published var onboarded = UserDefaults.standard.bool(forKey: "alakeya.onboarded")

    // Active chat messages — source of truth for the visible conversation.
    @Published var messages: [ChatMessage] = []

    // Persistent sessions
    @Published var sessions: [ChatSession] = []
    @Published var activeSessionID: UUID?

    var assistantState: AssistantState { status.assistantState }
    var orbState: OrbState { assistantState }
    var orbEmotion: OrbEmotion { status.orbEmotion }

    init() {
        activity = Store.shared.loadActivity()
        PolicyEngine.shared.mode = settings.automation.autoSafe ? .auto : .manual

        let loaded = Store.shared.loadSessions()
        if loaded.isEmpty {
            let s = ChatSession()
            sessions = [s]
            activeSessionID = s.id
            messages = [.greeting]
            activateAgent("general")
        } else {
            sessions = loaded
            let launchSession = Self.preferredLaunchSession(in: loaded)
            if !sessions.contains(where: { $0.id == launchSession.id }) {
                sessions.append(launchSession)
                Store.shared.saveSessions(sessions)
            }
            activeSessionID = launchSession.id
            messages = launchSession.messages.isEmpty ? [.greeting] : launchSession.messages
            activateAgent("general")
        }
    }

    // ── mutations used by the agent runtime ───────────────
    func setStatus(_ s: AgentStatusLabel) { status = s }

    func log(_ entry: ActivityEntry) {
        activity.append(entry)
        Store.shared.saveActivity(activity)
    }

    func showError(_ message: String, blocked: Bool) {
        error = ErrorMessage(message: message, blocked: blocked)
    }

    func completeOnboarding(_ collected: OnboardingResult) {
        if let accent = collected.accent { settings.appearance.accentHex = accent }
        if let face = collected.faceStyle { settings.appearance.faceStyle = face }
        settings.save()
        UserDefaults.standard.set(true, forKey: "alakeya.onboarded")
        onboarded = true
    }

    func exportCSV() -> String {
        let header = "time,kind,title,subtitle,status\n"
        let df = ISO8601DateFormatter()
        let body = activity.map { e in
            [df.string(from: e.time), e.kind, e.title, e.subtitle, e.status]
                .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
                .joined(separator: ",")
        }.joined(separator: "\n")
        return header + body
    }

    // ── Session management ────────────────────────────────

    func appendMessage(_ message: ChatMessage) {
        messages.append(message)
        syncToActiveSession()
    }

    func appendMessage(_ message: ChatMessage, to sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }

        if activeSessionID == sessionID {
            messages.append(message)
            syncToActiveSession()
            return
        }

        sessions[index].messages.append(message)
        sessions[index].updatedAt = .now
        updateAutomaticTitle(at: index)
        Store.shared.saveSessions(sessions)
    }

    func messages(for sessionID: UUID) -> [ChatMessage] {
        if activeSessionID == sessionID { return messages }
        return sessions.first(where: { $0.id == sessionID })?.messages ?? []
    }

    func newChat(agentId: String = "general", title: String = "Новый чат") {
        persistActiveSession()
        pendingLocalBusinessQuery = nil
        activateAgent(agentId)
        let s = ChatSession(agentId: agentId, title: title)
        sessions.append(s)
        activeSessionID = s.id
        messages = [.greeting]
        if title != "Новый чат" {
            if let idx = sessions.firstIndex(where: { $0.id == s.id }) {
                sessions[idx].title = title
            }
        }
        Store.shared.saveSessions(sessions)
    }

    func openLatestChat(for agentID: String) {
        if let latest = sessions
            .filter({ $0.agentId == agentID })
            .max(by: { $0.updatedAt < $1.updatedAt }) {
            switchSession(id: latest.id)
        } else {
            newChat(agentId: agentID)
        }
    }

    func switchSession(id: UUID) {
        if id == activeSessionID {
            if let session = sessions.first(where: { $0.id == id }) {
                messages = session.messages.isEmpty ? [.greeting] : session.messages
                activateAgent(session.agentId)
            }
            return
        }
        persistActiveSession()
        pendingLocalBusinessQuery = nil
        activeSessionID = id
        if let session = sessions.first(where: { $0.id == id }) {
            messages = session.messages.isEmpty ? [.greeting] : session.messages
            activateAgent(session.agentId)
        }
    }

    func renameSession(id: UUID, title: String) {
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].title = title
            Store.shared.saveSessions(sessions)
        }
    }

    func togglePinnedSession(id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].isPinned.toggle()
        Store.shared.saveSessions(sessions)
    }

    func deleteSession(id: UUID) {
        persistActiveSession()  // save current messages before deletion
        pendingLocalBusinessQuery = nil
        sessions.removeAll { $0.id == id }
        if id == activeSessionID {
            if let next = sessions.max(by: { $0.updatedAt < $1.updatedAt }) {
                activeSessionID = next.id
                messages = next.messages.isEmpty ? [.greeting] : next.messages
            } else {
                let s = ChatSession()
                sessions = [s]
                activeSessionID = s.id
                messages = [.greeting]
            }
        }
        Store.shared.saveSessions(sessions)
    }

    // ── Private helpers ───────────────────────────────────

    private func syncToActiveSession() {
        guard let id = activeSessionID,
              let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].messages = messages
        sessions[idx].updatedAt = .now
        updateAutomaticTitle(at: idx)
        Store.shared.saveSessions(sessions)
    }

    private func updateAutomaticTitle(at index: Int) {
        let title = sessions[index].title
        guard title == "Новый чат" || title.hasPrefix("Новый чат с ") else { return }
        guard let first = sessions[index].messages.first(where: { $0.role == .user }),
              !first.content.isEmpty else { return }
        sessions[index].title = String(first.content.prefix(40))
    }

    private func persistActiveSession() {
        guard let id = activeSessionID,
              let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].messages = messages
        sessions[idx].updatedAt = .now
    }

    private func activateAgent(_ id: String) {
        guard settings.models.activeSkillID != id else {
            SkillStore.shared.setActive(id)
            return
        }
        settings.models.activeSkillID = id
        settings.save()
        SkillStore.shared.setActive(id)
    }

    static func preferredLaunchSession(in sessions: [ChatSession]) -> ChatSession {
        sessions
            .filter { $0.agentId == "general" }
            .max(by: { $0.updatedAt < $1.updatedAt })
            ?? ChatSession(agentId: "general")
    }
}
