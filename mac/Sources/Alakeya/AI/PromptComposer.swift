import Foundation

enum PromptComposer {
    // Cached once at startup — instruction files don't change at runtime.
    static let coreSystemPrompt: String = {
        let sections = ["Identity", "Behavior", "Logic", "Safety"]
        let loaded = sections.compactMap { name -> String? in
            guard let url = Bundle.module.url(
                forResource: name,
                withExtension: "md",
                subdirectory: "Instructions"
            ) else { return nil }
            return try? String(contentsOf: url, encoding: .utf8)
        }
        guard !loaded.isEmpty else {
            return "You are Alakeya, a macOS assistant. Be concise and helpful."
        }
        return loaded.joined(separator: "\n\n")
    }()

    static func composeCoreSystemPrompt() -> String {
        coreSystemPrompt
    }
}
