import Foundation

struct AgentProfile: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var instructions: String
    var providerID: String
    var modelName: String
    var skillIDs: [String]
    var createdAt: Date

    var roleLabel: String {
        AgentRoleResolver.roleLabel(name: name, instructions: instructions)
    }
}

enum AgentRoleResolver {
    static func roleLabel(name: String, instructions: String) -> String {
        let context = "\(name) \(instructions)".lowercased()
        let rules: [(patterns: [String], label: String)] = [
            (["smm", "social media", "социальн", "контент-стратег"], "SMM-специалист"),
            (["дизайн", "designer", "ui/ux", "ux/ui", "графическ"], "дизайнер"),
            (["кодер", "developer", "programmer", "разработ", "программист", "swift"], "кодер"),
            (["маркетолог", "marketing", "маркетинг"], "маркетолог"),
            (["исследоват", "researcher", "research", "аналитик"], "исследователь"),
            (["копирайт", "copywriter", "редактор текст"], "копирайтер"),
            (["продаж", "sales"], "специалист по продажам"),
            (["юрист", "legal"], "юрист"),
            (["финанс", "бухгалтер"], "финансовый помощник"),
        ]

        for rule in rules where rule.patterns.contains(where: context.contains) {
            return rule.label
        }
        return "помощник"
    }
}

@MainActor
final class AgentProfileStore: ObservableObject {
    static let shared = AgentProfileStore()

    @Published private(set) var agents: [AgentProfile] = []

    private let directory: URL
    private let metadataURL: URL
    private let skillsDirectory: URL

    private init() {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Alakeya", isDirectory: true)
        directory = base.appendingPathComponent("Agents", isDirectory: true)
        metadataURL = directory.appendingPathComponent("agents.json")
        skillsDirectory = base.appendingPathComponent("Skills", isDirectory: true)
        reload()
    }

    func reload() {
        let saved = loadMetadata()
        let migrated = migrateMarkdownAgents(existing: saved)
        agents = migrated.sorted { $0.createdAt < $1.createdAt }
        try? persist()
    }

    func create(
        name: String,
        instructions: String,
        providerID: String,
        modelName: String,
        skillIDs: [String]
    ) throws -> AgentProfile {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanInstructions.isEmpty, !cleanModel.isEmpty else {
            throw AgentProfileError.incomplete
        }

        let profile = AgentProfile(
            id: "agent-\(UUID().uuidString.lowercased().prefix(8))",
            name: cleanName,
            instructions: cleanInstructions,
            providerID: providerID,
            modelName: cleanModel,
            skillIDs: skillIDs,
            createdAt: .now
        )
        try writeSkillFile(for: profile)
        agents.append(profile)
        try persist()
        SkillStore.shared.reload()
        return profile
    }

    func profile(for id: String) -> AgentProfile? {
        agents.first(where: { $0.id == id })
    }

    func update(_ profile: AgentProfile) throws {
        guard let index = agents.firstIndex(where: { $0.id == profile.id }) else { return }
        var clean = profile
        clean.name = clean.name.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.instructions = clean.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.modelName = clean.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.name.isEmpty, !clean.instructions.isEmpty, !clean.modelName.isEmpty else {
            throw AgentProfileError.incomplete
        }
        try writeSkillFile(for: clean)
        agents[index] = clean
        try persist()
        SkillStore.shared.reload()
    }

    func resolvedSettings(base: Settings, activeAgentID: String) -> Settings {
        guard let profile = profile(for: activeAgentID) else { return base }
        var result = base
        result.models.activeProviderID = profile.providerID
        if let index = result.models.providers.firstIndex(where: { $0.id == profile.providerID }) {
            result.models.providers[index].modelName = profile.modelName
        }
        return result
    }

    private func loadMetadata() -> [AgentProfile] {
        guard let data = try? Data(contentsOf: metadataURL) else { return [] }
        return (try? JSONDecoder().decode([AgentProfile].self, from: data)) ?? []
    }

    private func migrateMarkdownAgents(existing: [AgentProfile]) -> [AgentProfile] {
        var result = existing
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: skillsDirectory,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return result }

        let fallback = (try? AIProviderStore.shared.activeConfiguration(in: Settings.load()))
            ?? .builtIn(.openAI)

        for url in urls where url.pathExtension == "md" {
            let id = url.deletingPathExtension().lastPathComponent
            guard id.hasPrefix("agent-"),
                  !result.contains(where: { $0.id == id }),
                  let content = try? String(contentsOf: url, encoding: .utf8)
            else { continue }

            result.append(AgentProfile(
                id: id,
                name: Self.title(from: content) ?? id,
                instructions: Self.instructions(from: content),
                providerID: fallback.id,
                modelName: fallback.modelName,
                skillIDs: [],
                createdAt: (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .now
            ))
        }
        return result
    }

    private func writeSkillFile(for profile: AgentProfile) throws {
        try FileManager.default.createDirectory(
            at: skillsDirectory,
            withIntermediateDirectories: true
        )
        let selectedSkills = SkillStore.shared.availableSkills
            .filter { profile.skillIDs.contains($0.id) && !$0.id.hasPrefix("agent-") }
            .map(\.overlay)
            .joined(separator: "\n\n---\n\n")
        let additions = selectedSkills.isEmpty ? "" : "\n\nAdditional skills:\n\(selectedSkills)"
        let content = """
        # \(profile.name)

        You are a specialized ALAKEYA agent.

        \(profile.instructions)\(additions)
        """
        try content.write(
            to: skillsDirectory.appendingPathComponent("\(profile.id).md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(agents)
        try data.write(to: metadataURL, options: .atomic)
    }

    private static func title(from content: String) -> String? {
        content.components(separatedBy: "\n")
            .first(where: { $0.hasPrefix("# ") })
            .map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
    }

    private static func instructions(from content: String) -> String {
        content.components(separatedBy: "\n")
            .drop(while: { !$0.contains("specialized ALAKEYA agent") })
            .dropFirst()
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum AgentProfileError: LocalizedError {
    case incomplete

    var errorDescription: String? {
        "Заполните имя, инструкции и модель агента."
    }
}
