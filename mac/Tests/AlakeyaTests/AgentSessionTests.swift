import Foundation
import Testing
@testable import Alakeya

@Test @MainActor
func launchPrefersLatestGeneralChat() {
    let oldGeneral = ChatSession(
        agentId: "general",
        title: "Старый чат Алакеи",
        updatedAt: Date(timeIntervalSince1970: 100)
    )
    let recentCustom = ChatSession(
        agentId: "agent-fox",
        title: "Новый чат Лисички",
        updatedAt: Date(timeIntervalSince1970: 300)
    )
    let latestGeneral = ChatSession(
        agentId: "general",
        title: "Последний чат Алакеи",
        updatedAt: Date(timeIntervalSince1970: 200)
    )

    let selected = AgentStore.preferredLaunchSession(
        in: [oldGeneral, recentCustom, latestGeneral]
    )

    #expect(selected.id == latestGeneral.id)
    #expect(selected.agentId == "general")
}
