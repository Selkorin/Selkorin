import Testing
@testable import Alakeya

@Test
func resolvesCommonAgentRolesInRussian() {
    #expect(
        AgentRoleResolver.roleLabel(
            name: "Лисичка",
            instructions: "Ты опытный UI/UX designer для мобильных продуктов."
        ) == "дизайнер"
    )
    #expect(
        AgentRoleResolver.roleLabel(
            name: "Контент",
            instructions: "Веди social media и составляй SMM-стратегии."
        ) == "SMM-специалист"
    )
    #expect(
        AgentRoleResolver.roleLabel(
            name: "Swift эксперт",
            instructions: "Разрабатывай приложения и исправляй код."
        ) == "кодер"
    )
}

@Test
func unknownAgentRoleFallsBackToAssistant() {
    #expect(
        AgentRoleResolver.roleLabel(
            name: "Босс",
            instructions: "Помогай решать разные ежедневные задачи."
        ) == "помощник"
    )
}
