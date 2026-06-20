import SwiftUI

struct SkillsSettingsView: View {
    @ObservedObject var store: AgentStore
    @ObservedObject private var skillStore = SkillStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            skillsList
            hint
        }
    }

    private var header: some View {
        HStack {
            Text("Навыки")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(WAI.text)
            Spacer()
            Button("Обновить") { skillStore.reload() }
                .buttonStyle(.plain)
                .foregroundStyle(WAI.accentBright)
                .font(.system(size: 13))
        }
    }

    private var skillsList: some View {
        VStack(spacing: 4) {
            ForEach(skillStore.availableSkills) { skill in
                skillRow(skill)
            }
        }
    }

    private func skillRow(_ skill: Skill) -> some View {
        let isActive = store.settings.models.activeSkillID == skill.id
        return Button {
            store.settings.models.activeSkillID = skill.id
            store.settings.save()
            SkillStore.shared.setActive(skill.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isActive ? WAI.accentBright : WAI.textMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.title)
                        .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? WAI.text : WAI.textDim)
                    Text(skill.id)
                        .font(.system(size: 11))
                        .foregroundStyle(WAI.textFaint)
                }
                Spacer()
            }
            .padding(10)
            .background(isActive ? WAI.accentSoft : WAI.surfaceInset)
            .overlay(RoundedRectangle(cornerRadius: WAI.rMd)
                .stroke(isActive ? WAI.lineAccent : WAI.line))
            .clipShape(RoundedRectangle(cornerRadius: WAI.rMd))
        }
        .buttonStyle(.plain)
    }

    private var hint: some View {
        Text("Чтобы добавить свой навык, положите .md файл в\n~/Library/Application Support/Alakeya/Skills/")
            .font(.system(size: 11))
            .foregroundStyle(WAI.textFaint)
            .padding(.top, 4)
    }
}
