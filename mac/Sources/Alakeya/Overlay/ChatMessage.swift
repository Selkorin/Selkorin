import Foundation

// ============================================================
// ChatMessage.swift — value type for a single chat turn.
// ============================================================

enum ChatRole: String, Codable { case user, assistant }

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: ChatRole
    let content: String
    let images: [Data]
    let timestamp: Date
    /// Sources shown as chips below assistant messages. Empty for user messages.
    var sources: [SourceReference]
    /// Structured file attachments produced by export tools.
    var fileAttachments: [ExportedFileAttachment]
    /// Structured tables produced by research coordinator (for lossless export).
    var structuredTables: [ParsedMarkdownTable]

    enum CodingKeys: String, CodingKey {
        case id, role, content, images, timestamp, sources, fileAttachments, structuredTables
    }

    init(role: ChatRole, content: String, images: [Data] = [],
         sources: [SourceReference] = [],
         fileAttachments: [ExportedFileAttachment] = [],
         structuredTables: [ParsedMarkdownTable] = [],
         timestamp: Date = .now, id: UUID = UUID()) {
        self.id               = id
        self.role             = role
        self.content          = content
        self.images           = images
        self.sources          = sources
        self.fileAttachments  = fileAttachments
        self.structuredTables = structuredTables
        self.timestamp        = timestamp
    }

    init(from decoder: Decoder) throws {
        let c        = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(UUID.self,     forKey: .id)
        role         = try c.decode(ChatRole.self,  forKey: .role)
        content      = try c.decode(String.self,   forKey: .content)
        images       = try c.decode([Data].self,   forKey: .images)
        timestamp    = try c.decode(Date.self,     forKey: .timestamp)
        sources          = (try? c.decode([SourceReference].self,         forKey: .sources))          ?? []
        fileAttachments  = (try? c.decode([ExportedFileAttachment].self,  forKey: .fileAttachments))  ?? []
        structuredTables = (try? c.decode([ParsedMarkdownTable].self,     forKey: .structuredTables)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,               forKey: .id)
        try c.encode(role,             forKey: .role)
        try c.encode(content,          forKey: .content)
        try c.encode(images,           forKey: .images)
        try c.encode(timestamp,        forKey: .timestamp)
        try c.encode(sources,          forKey: .sources)
        try c.encode(fileAttachments,  forKey: .fileAttachments)
        try c.encode(structuredTables, forKey: .structuredTables)
    }

    func strippingImages() -> ChatMessage {
        ChatMessage(role: role, content: content, images: [],
                    sources: sources, fileAttachments: fileAttachments,
                    structuredTables: structuredTables,
                    timestamp: timestamp, id: id)
    }
}

extension ChatMessage {
    static let greeting = ChatMessage(
        role:    .assistant,
        content: "Привет. Скажите «Алакея» или напишите команду."
    )
}
