import Foundation
import Testing
@testable import Alakeya

@Test
func legacyChatSessionDecodesAsUnpinned() throws {
    let id = UUID()
    let created = Date(timeIntervalSince1970: 1_700_000_000)
    let payload: [String: Any] = [
        "id": id.uuidString,
        "agentId": "agent-test",
        "title": "Старый чат",
        "createdAt": ISO8601DateFormatter().string(from: created),
        "updatedAt": ISO8601DateFormatter().string(from: created),
        "messages": [],
    ]
    let data = try JSONSerialization.data(withJSONObject: payload)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let session = try decoder.decode(ChatSession.self, from: data)

    #expect(session.id == id)
    #expect(session.isPinned == false)
}

@Test
func pinnedStateSurvivesRoundTrip() throws {
    let original = ChatSession(title: "Важный чат", isPinned: true)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let restored = try decoder.decode(ChatSession.self, from: encoder.encode(original))

    #expect(restored.id == original.id)
    #expect(restored.isPinned)
}
