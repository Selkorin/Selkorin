import Foundation

struct Skill: Identifiable, Equatable {
    let id: String
    let title: String
    let overlay: String
}

final class SkillStore: ObservableObject {
    static let shared = SkillStore()

    @Published private(set) var availableSkills: [Skill] = []
    private(set) var activeSkillID: String = "general"

    private let skillsDir: URL

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Alakeya", isDirectory: true)
        skillsDir = base.appendingPathComponent("Skills", isDirectory: true)
        activeSkillID = Settings.load().models.activeSkillID
        seedDefaultsIfNeeded()
        availableSkills = loadSkills()
    }

    // ── Active skill ──────────────────────────────────────

    func activeSkillOverlay() -> String {
        availableSkills.first(where: { $0.id == activeSkillID })?.overlay ?? ""
    }

    func setActive(_ id: String) {
        activeSkillID = id
    }

    // ── Reload ────────────────────────────────────────────

    func reload() {
        availableSkills = loadSkills()
    }

    // ── Seed defaults from bundle ─────────────────────────

    private func seedDefaultsIfNeeded() {
        let fm = FileManager.default
        try? fm.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        let defaults = ["general", "swift-developer", "business", "content-creator"]
        for name in defaults {
            let dest = skillsDir.appendingPathComponent("\(name).md")
            guard !fm.fileExists(atPath: dest.path) else { continue }
            guard let src = Bundle.module.url(
                forResource: name, withExtension: "md", subdirectory: "Skills"
            ) else { continue }
            try? fm.copyItem(at: src, to: dest)
        }
    }

    // ── Load from App Support ─────────────────────────────

    private func loadSkills() -> [Skill] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: skillsDir, includingPropertiesForKeys: nil
        ) else { return [] }

        return urls
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let content = try? String(contentsOf: url, encoding: .utf8),
                      !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { return nil }
                let id = url.deletingPathExtension().lastPathComponent
                let title = parseTitle(from: content) ?? id
                return Skill(id: id, title: title, overlay: content)
            }
    }

    private func parseTitle(from content: String) -> String? {
        for line in content.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("# ") {
                let title = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                return title.isEmpty ? nil : title
            }
        }
        return nil
    }
}
