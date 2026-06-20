import Foundation

// ============================================================
// ChatSession.swift — a named conversation with its messages.
// ============================================================

struct ChatSession: Identifiable, Codable {
    let id: UUID
    var agentId: String
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage]
    var isPinned: Bool

    init(id: UUID = UUID(),
         agentId: String = "general",
         title: String = "Новый чат",
         createdAt: Date = .now,
         updatedAt: Date = .now,
         messages: [ChatMessage] = [],
         isPinned: Bool = false) {
        self.id = id
        self.agentId = agentId
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.isPinned = isPinned
    }

    private enum CodingKeys: String, CodingKey {
        case id, agentId, title, createdAt, updatedAt, messages, isPinned
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        agentId = try values.decodeIfPresent(String.self, forKey: .agentId) ?? "general"
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? "Новый чат"
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        messages = try values.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
        isPinned = try values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }
}
