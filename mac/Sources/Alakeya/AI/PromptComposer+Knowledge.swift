import Foundation

extension PromptComposer {
    static func composeWithSkillAndKnowledge() -> String {
        let base = composeWithSkill()
        let knowledge = KnowledgeStore.shared.composeContext()
        guard !knowledge.isEmpty else { return base }
        return base + "\n\n---\n\n" + knowledge
    }
}
