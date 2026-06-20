import Foundation

extension PromptComposer {
    static func composeWithSkill() -> String {
        let base = coreSystemPrompt
        let overlay = SkillStore.shared.activeSkillOverlay()
        guard !overlay.isEmpty else { return base }
        return base + "\n\n---\n\n" + overlay
    }
}
